//! One pass over every process, and queries over its parent links.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

/// Usage of a process the daemon is allowed to read.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Usage {
    /// 100 means one core fully busy.
    pub cpu_percent: f64,
    /// Physical footprint, Activity Monitor's "Memory".
    pub memory_bytes: u64,
    pub resident_bytes: u64,
}

/// One process. `usage` is `None` when it could not be read (another
/// user's process, or one that exited during the pass).
#[derive(Debug, Clone, PartialEq)]
pub struct ProcessEntry {
    pub pid: i32,
    pub parent_pid: i32,
    pub uid: u32,
    /// The executable's file name, or the kernel's short name when the path
    /// is unknown.
    pub name: Arc<str>,
    /// The executable's full path; empty when unknown.
    pub path: Arc<str>,
    pub usage: Option<Usage>,
}

/// Every process from one pass.
#[derive(Debug, Clone, Default)]
pub struct ProcessTable {
    entries: Vec<ProcessEntry>,
    by_pid: HashMap<i32, usize>,
}

/// Usage added up over a process and everything started under it.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct SubtreeUsage {
    /// Sums over the readable processes in the subtree.
    pub cpu_percent: f64,
    pub memory_bytes: u64,
    /// Every process in the subtree, the root included, readable or not.
    pub process_count: u32,
    /// How many of those could not be read.
    pub hidden_count: u32,
    /// The pids in the subtree, the root first.
    pub pids: Vec<i32>,
}

impl ProcessTable {
    /// Builds a table. If a pid appears twice, the later entry wins.
    pub fn new(entries: Vec<ProcessEntry>) -> Self {
        let mut by_pid = HashMap::with_capacity(entries.len());
        let mut kept: Vec<ProcessEntry> = Vec::with_capacity(entries.len());
        for e in entries {
            if let Some(&i) = by_pid.get(&e.pid) {
                kept[i] = e;
            } else {
                by_pid.insert(e.pid, kept.len());
                kept.push(e);
            }
        }
        Self {
            entries: kept,
            by_pid,
        }
    }

    pub fn entries(&self) -> &[ProcessEntry] {
        &self.entries
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get(&self, pid: i32) -> Option<&ProcessEntry> {
        self.by_pid.get(&pid).map(|&i| &self.entries[i])
    }

    /// The entry's parent, unless it is its own parent or not listed.
    pub fn parent(&self, entry: &ProcessEntry) -> Option<&ProcessEntry> {
        if entry.parent_pid == entry.pid {
            return None;
        }
        self.get(entry.parent_pid)
    }

    /// Adds up usage over `root_pid` and every process below it, following
    /// parent links down. `None` if `root_pid` is not in the table. The
    /// root may be unreadable (a root-owned `login`, say); its descendants
    /// still count.
    pub fn subtree_usage(&self, root_pid: i32) -> Option<SubtreeUsage> {
        let root = self.by_pid.get(&root_pid).copied()?;
        let children = self.children();
        let mut out = SubtreeUsage::default();
        let mut seen = HashSet::from([root]);
        let mut queue = std::collections::VecDeque::from([root]);
        while let Some(i) = queue.pop_front() {
            let e = &self.entries[i];
            out.pids.push(e.pid);
            out.process_count += 1;
            match e.usage {
                Some(u) => {
                    out.cpu_percent += u.cpu_percent;
                    out.memory_bytes += u.memory_bytes;
                }
                None => out.hidden_count += 1,
            }
            for &c in children.get(&e.pid).map_or(&[][..], Vec::as_slice) {
                if seen.insert(c) {
                    queue.push_back(c);
                }
            }
        }
        Some(out)
    }

    /// Indexes of each pid's children, leaving out self-parented entries.
    fn children(&self) -> HashMap<i32, Vec<usize>> {
        let mut map: HashMap<i32, Vec<usize>> = HashMap::new();
        for (i, e) in self.entries.iter().enumerate() {
            if e.parent_pid != e.pid {
                map.entry(e.parent_pid).or_default().push(i);
            }
        }
        map
    }
}

#[cfg(test)]
pub(crate) mod fixture {
    use super::*;

    /// A test entry. `mem` of `None` means unreadable.
    pub fn proc(pid: i32, ppid: i32, path: &str, mem: Option<u64>) -> ProcessEntry {
        let name = path.rsplit('/').next().unwrap_or(path);
        ProcessEntry {
            pid,
            parent_pid: ppid,
            uid: if mem.is_some() { 501 } else { 0 },
            name: name.into(),
            path: path.into(),
            usage: mem.map(|m| Usage {
                cpu_percent: m as f64 / 10.0,
                memory_bytes: m,
                resident_bytes: m * 2,
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::fixture::proc;
    use super::*;

    fn pane() -> ProcessTable {
        ProcessTable::new(vec![
            proc(1, 0, "/sbin/launchd", None),
            proc(
                100,
                1,
                "/Applications/Rex.app/Contents/MacOS/rex-server",
                Some(50),
            ),
            proc(200, 100, "/usr/bin/login", None),
            proc(201, 200, "/bin/zsh", Some(10)),
            proc(202, 201, "/Users/me/.local/bin/claude", Some(300)),
            proc(203, 202, "/opt/homebrew/bin/node", Some(40)),
            proc(204, 202, "/bin/sleep", None),
            proc(300, 100, "/usr/bin/login", None),
            proc(301, 300, "/bin/zsh", Some(7)),
        ])
    }

    #[test]
    fn subtree_adds_up_readable_processes_under_an_unreadable_root() {
        let s = pane().subtree_usage(200).expect("root present");
        assert_eq!(s.pids[0], 200);
        let mut pids = s.pids.clone();
        pids.sort_unstable();
        assert_eq!(pids, vec![200, 201, 202, 203, 204]);
        assert_eq!(s.memory_bytes, 10 + 300 + 40);
        assert!((s.cpu_percent - 35.0).abs() < 1e-9);
        assert_eq!((s.process_count, s.hidden_count), (5, 2));
    }

    #[test]
    fn subtree_of_a_leaf_and_of_a_missing_pid() {
        let t = pane();
        let leaf = t.subtree_usage(301).expect("present");
        assert_eq!((leaf.pids, leaf.memory_bytes), (vec![301], 7));
        assert!(t.subtree_usage(999).is_none());
    }

    #[test]
    fn subtree_survives_a_parent_cycle() {
        let t = ProcessTable::new(vec![
            proc(5, 6, "/a", Some(1)),
            proc(6, 5, "/b", Some(2)),
            proc(0, 0, "", None),
        ]);
        let s = t.subtree_usage(5).expect("present");
        assert_eq!((s.process_count, s.memory_bytes), (2, 3));
        let k = t.subtree_usage(0).expect("present");
        assert_eq!(k.pids, vec![0], "a self-parented pid is not its own child");
    }

    #[test]
    fn duplicate_pids_keep_the_later_entry() {
        let t = ProcessTable::new(vec![proc(9, 1, "/old", None), proc(9, 1, "/new", Some(1))]);
        assert_eq!(t.len(), 1);
        assert_eq!(&*t.get(9).expect("present").path, "/new");
    }
}
