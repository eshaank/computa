//! Groups a process table by app, and estimates what the daemon cannot see.

use std::collections::HashMap;

use super::table::{ProcessEntry, ProcessTable};
use crate::pb::{HiddenProcesses, Process, ProcessGroup, ProcessSnapshot};

/// The id of the group that holds the operating system's own processes.
pub const SYSTEM_ID: &str = "system";
const SYSTEM_NAME: &str = "System";

/// Path prefixes of software that ships with macOS.
const SYSTEM_PREFIXES: [&str; 5] = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"];
/// Inside `/usr`, but installed by the user.
const NOT_SYSTEM_PREFIX: &str = "/usr/local/";

/// The group a process belongs to.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum GroupKey {
    /// The outermost app bundle in the path of the process or an ancestor.
    App(String),
    System,
    /// The top-most ancestor below launchd.
    Pid(i32),
}

impl GroupKey {
    pub fn id(&self) -> String {
        match self {
            Self::App(bundle) => bundle.clone(),
            Self::System => SYSTEM_ID.to_owned(),
            Self::Pid(pid) => format!("pid:{pid}"),
        }
    }
}

/// The outermost `.app` directory in `path`, for example
/// `/Applications/Google Chrome.app` for a Chrome helper. The bundle must be
/// a directory, so a final component ending in `.app` does not count.
pub fn outermost_app(path: &str) -> Option<&str> {
    let mut end = 0;
    for component in path.split('/') {
        end += component.len();
        if component.len() > ".app".len() && component.ends_with(".app") && end < path.len() {
            return Some(&path[..end]);
        }
        end += 1; // the '/'
    }
    None
}

pub fn is_system_path(path: &str) -> bool {
    !path.starts_with(NOT_SYSTEM_PREFIX) && SYSTEM_PREFIXES.iter().any(|p| path.starts_with(p))
}

/// The ancestors of `entry`, itself first, stopping at launchd (pid 1, not
/// included), the kernel, a missing parent or a cycle.
fn lineage<'a>(table: &'a ProcessTable, entry: &'a ProcessEntry) -> Vec<&'a ProcessEntry> {
    let mut chain = vec![entry];
    let mut cur = entry;
    while let Some(parent) = table.parent(cur) {
        if parent.pid <= 1 || chain.iter().any(|e| e.pid == parent.pid) {
            break;
        }
        chain.push(parent);
        cur = parent;
    }
    chain
}

/// Applies the grouping rules, in order:
/// 1. the outermost app bundle in the path of the process or its nearest
///    ancestor that has one, readable or not;
/// 2. the system group, for the kernel and for executables under system
///    paths;
/// 3. the top-most ancestor below launchd. In a parent cycle, the lowest pid
///    in the chain stands in for it, so every member agrees.
pub fn group_key(table: &ProcessTable, entry: &ProcessEntry) -> GroupKey {
    let chain = lineage(table, entry);
    if let Some(bundle) = chain.iter().find_map(|e| outermost_app(&e.path)) {
        return GroupKey::App(bundle.to_owned());
    }
    if entry.pid == 0 || is_system_path(&entry.path) {
        return GroupKey::System;
    }
    let top = chain.last().map_or(entry, |e| *e);
    let cyclic = table
        .parent(top)
        .is_some_and(|p| p.pid > 1 && chain.iter().any(|e| e.pid == p.pid));
    if cyclic {
        let lowest = chain.iter().map(|e| e.pid).min().unwrap_or(entry.pid);
        return GroupKey::Pid(lowest);
    }
    GroupKey::Pid(top.pid)
}

/// The group's display name and bundle path.
fn describe(table: &ProcessTable, key: &GroupKey) -> (String, String) {
    match key {
        GroupKey::App(bundle) => {
            let file = bundle.rsplit('/').next().unwrap_or(bundle);
            let name = file.strip_suffix(".app").unwrap_or(file);
            (name.to_owned(), bundle.clone())
        }
        GroupKey::System => (SYSTEM_NAME.to_owned(), String::new()),
        GroupKey::Pid(pid) => {
            let name = table
                .get(*pid)
                .map_or_else(|| pid.to_string(), |e| e.name.to_string());
            (name, String::new())
        }
    }
}

/// Builds the `WatchProcesses` message. Only readable processes are listed,
/// and a group with none is left out.
pub fn snapshot(table: &ProcessTable, unix_ms: i64) -> ProcessSnapshot {
    let mut groups: HashMap<GroupKey, ProcessGroup> = HashMap::new();
    let mut hidden_count = 0u32;
    for entry in table.entries() {
        let Some(usage) = entry.usage else {
            hidden_count += 1;
            continue;
        };
        let key = group_key(table, entry);
        let group = groups.entry(key.clone()).or_insert_with(|| {
            let (name, bundle_path) = describe(table, &key);
            ProcessGroup {
                id: key.id(),
                name,
                bundle_path,
                ..ProcessGroup::default()
            }
        });
        group.cpu_percent += usage.cpu_percent;
        group.memory_bytes = group.memory_bytes.saturating_add(usage.memory_bytes);
        group.processes.push(Process {
            pid: entry.pid,
            parent_pid: entry.parent_pid,
            name: entry.name.to_string(),
            path: entry.path.to_string(),
            cpu_percent: usage.cpu_percent,
            memory_bytes: usage.memory_bytes,
            resident_bytes: usage.resident_bytes,
        });
    }
    ProcessSnapshot {
        unix_ms,
        groups: groups.into_values().collect(),
        hidden: Some(HiddenProcesses {
            process_count: hidden_count,
        }),
        process_count: u32::try_from(table.len()).unwrap_or(u32::MAX),
    }
}

#[cfg(test)]
#[path = "group_tests.rs"]
mod tests;
