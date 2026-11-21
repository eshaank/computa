//! Builds a `SessionsSnapshot` from the pane map and one process table. A
//! pure function: no Rex calls, no clock.

use crate::pb::{Pane, PaneKind, RexStatus, Session, SessionWindow, SessionsSnapshot};
use crate::processes::group::process_message;
use crate::processes::{ProcessEntry, ProcessTable};
use crate::rex::{PaneProcess, ProcInfo};

use super::map::{PaneInfo, PaneMap, SessionInfo, WindowInfo};

/// Programs counted as a pane's own shell when they are in the foreground.
const SHELLS: [&str; 11] = [
    "zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "xonsh",
];
/// Claude Code's native installer puts each version here; the executable's
/// name is the version number.
const CLAUDE_VERSIONS_DIR: &str = "/claude/versions/";
const CLAUDE: &str = "claude";

pub fn build(
    map: &PaneMap,
    table: &ProcessTable,
    rex: RexStatus,
    unix_ms: i64,
) -> SessionsSnapshot {
    SessionsSnapshot {
        unix_ms,
        rex: Some(rex),
        sessions: map.sessions.iter().map(|s| session(s, table)).collect(),
    }
}

fn session(s: &SessionInfo, table: &ProcessTable) -> Session {
    let windows: Vec<SessionWindow> = s.windows.iter().map(|w| window(w, table)).collect();
    Session {
        id: s.id.clone(),
        label: s.label.clone(),
        cpu_percent: windows.iter().map(|w| w.cpu_percent).sum(),
        memory_bytes: windows.iter().map(|w| w.memory_bytes).sum(),
        process_count: windows.iter().map(|w| w.process_count).sum(),
        windows,
    }
}

fn window(w: &WindowInfo, table: &ProcessTable) -> SessionWindow {
    let panes: Vec<Pane> = w.panes.iter().map(|p| pane(p, table)).collect();
    SessionWindow {
        id: w.id.clone(),
        label: w.label.clone(),
        cpu_percent: panes.iter().map(|p| p.cpu_percent).sum(),
        memory_bytes: panes.iter().map(|p| p.memory_bytes).sum(),
        process_count: panes.iter().map(|p| p.process_count).sum(),
        panes,
    }
}

/// One pane. A pane whose root process has exited reports zero usage.
pub fn pane(p: &PaneInfo, table: &ProcessTable) -> Pane {
    let mut out = Pane {
        id: p.id.clone(),
        label: p.label.clone(),
        ..Pane::default()
    };
    let Some(process) = &p.process else {
        return out;
    };
    let root = process.child.as_ref().map(|c| c.pid);
    let subtree = root.and_then(|pid| table.subtree_usage(pid));
    let mut claude_below = false;
    if let Some(sub) = subtree {
        out.cpu_percent = sub.cpu_percent;
        out.memory_bytes = sub.memory_bytes;
        out.process_count = sub.process_count;
        let entries = sub.pids.iter().filter_map(|&pid| table.get(pid));
        for e in entries {
            claude_below |= is_claude_entry(e);
            if let Some(u) = e.usage {
                out.processes.push(process_message(e, u));
            }
        }
    }
    let (kind, program) = kind_and_program(process, claude_below);
    out.kind = kind.into();
    out.program = program;
    out.working_directory = process
        .foreground
        .as_ref()
        .map(|f| f.cwd.clone())
        .unwrap_or_default();
    out
}

/// What is running in the pane, and the foreground program's name.
pub fn kind_and_program(p: &PaneProcess, claude_in_subtree: bool) -> (PaneKind, String) {
    let fg = p.foreground.as_ref();
    if claude_in_subtree || fg.is_some_and(is_claude_info) {
        return (PaneKind::Claude, CLAUDE.to_owned());
    }
    let Some(fg) = fg else {
        return (PaneKind::Shell, String::new());
    };
    let program = program_name(fg);
    let own_shell = shell_pid(p) == Some(fg.pid) && SHELLS.contains(&program.as_str());
    let kind = if own_shell {
        PaneKind::Shell
    } else {
        PaneKind::Program
    };
    (kind, program)
}

/// The pid of the pane's own shell: the process `login` started, or the
/// pane's root when there is no `login`.
fn shell_pid(p: &PaneProcess) -> Option<i32> {
    let child = p.child.as_ref()?;
    if child.name != "login" {
        return Some(child.pid);
    }
    // The chain runs from the foreground up to the root, nearest first.
    let chain: Vec<i32> = p
        .foreground
        .iter()
        .chain(&p.ancestors)
        .map(|i| i.pid)
        .collect();
    let at = chain.iter().position(|&pid| pid == child.pid)?;
    at.checked_sub(1).map(|i| chain[i])
}

/// `argv0` as a person would say it: no login-shell dash, no directory.
/// Falls back to the executable's name.
pub fn program_name(fg: &ProcInfo) -> String {
    let argv0 = fg.argv0.trim_start_matches('-');
    let base = argv0.rsplit('/').next().unwrap_or(argv0);
    if base.is_empty() {
        fg.name.clone()
    } else {
        base.to_owned()
    }
}

pub fn is_claude_info(p: &ProcInfo) -> bool {
    program_name(p) == CLAUDE || p.name == CLAUDE || p.path.contains(CLAUDE_VERSIONS_DIR)
}

pub fn is_claude_entry(e: &ProcessEntry) -> bool {
    &*e.name == CLAUDE || e.path.contains(CLAUDE_VERSIONS_DIR)
}

#[cfg(test)]
#[path = "snapshot_tests.rs"]
mod tests;
