use super::*;
use crate::processes::fixture::proc;
use crate::rex::fake;

fn info(pid: i32, name: &str, path: &str, argv0: &str) -> ProcInfo {
    ProcInfo {
        pid,
        name: name.into(),
        path: path.into(),
        argv0: argv0.into(),
        cwd: format!("/work/{pid}"),
    }
}

fn zsh(pid: i32) -> ProcInfo {
    info(pid, "zsh", "/bin/zsh", "-zsh")
}

fn login(pid: i32) -> ProcInfo {
    info(pid, "login", "/usr/bin/login", "login")
}

fn claude_fg(pid: i32) -> ProcInfo {
    info(
        pid,
        "2.1.328",
        "/Users/me/.local/share/claude/versions/2.1.328",
        "claude",
    )
}

/// Pane A (root 200): login > zsh > claude > node.
/// Pane B (root 300): login > zsh, idle.
/// Pane C (root 400): login > zsh > nvim.
/// Pane D (root 500): exited, not in the table.
fn table() -> ProcessTable {
    ProcessTable::new(vec![
        proc(1, 0, "/sbin/launchd", None),
        proc(200, 1, "/usr/bin/login", None),
        proc(201, 200, "/bin/zsh", Some(10)),
        proc(
            202,
            201,
            "/Users/me/.local/share/claude/versions/2.1.328",
            Some(300),
        ),
        proc(203, 202, "/opt/homebrew/bin/node", Some(40)),
        proc(300, 1, "/usr/bin/login", None),
        proc(301, 300, "/bin/zsh", Some(7)),
        proc(400, 1, "/usr/bin/login", None),
        proc(401, 400, "/bin/zsh", Some(5)),
        proc(402, 401, "/opt/homebrew/bin/nvim", Some(60)),
    ])
}

fn pane_info(id: &str, process: PaneProcess) -> PaneInfo {
    PaneInfo {
        id: id.into(),
        label: "shell".into(),
        process: Some(process),
    }
}

fn map() -> PaneMap {
    let a = fake::process(200, Some(claude_fg(202)), vec![zsh(201), login(200)]);
    let b = fake::process(300, Some(zsh(301)), vec![login(300)]);
    let c = fake::process(400, Some(info(402, "nvim", "/x/nvim", "nvim")), vec![]);
    let d = fake::process(500, Some(zsh(501)), vec![login(500)]);
    PaneMap {
        sessions: vec![SessionInfo {
            id: "session:s".into(),
            label: "work".into(),
            windows: vec![
                WindowInfo {
                    id: "window:1".into(),
                    label: "one".into(),
                    panes: vec![pane_info("block:a", a), pane_info("block:b", b)],
                },
                WindowInfo {
                    id: "window:2".into(),
                    label: "two".into(),
                    panes: vec![pane_info("block:c", c), pane_info("block:d", d)],
                },
            ],
        }],
    }
}

fn status() -> RexStatus {
    RexStatus {
        reachable: true,
        problem: String::new(),
        version: "v".into(),
    }
}

#[test]
fn roll_ups_add_up_and_the_unreadable_root_is_counted() {
    let snap = build(&map(), &table(), status(), 42);
    assert_eq!(snap.unix_ms, 42);
    let s = &snap.sessions[0];
    let (w1, w2) = (&s.windows[0], &s.windows[1]);
    let a = &w1.panes[0];
    assert_eq!(a.memory_bytes, 10 + 300 + 40);
    assert!((a.cpu_percent - 35.0).abs() < 1e-9);
    assert_eq!(a.process_count, 4, "login is counted though unreadable");
    let mut pids: Vec<i32> = a.processes.iter().map(|p| p.pid).collect();
    pids.sort_unstable();
    assert_eq!(
        pids,
        vec![201, 202, 203],
        "only readable processes are listed"
    );
    assert_eq!(w1.memory_bytes, 350 + 7);
    assert_eq!(w1.process_count, 4 + 2);
    assert_eq!(w2.memory_bytes, 65);
    assert_eq!(s.memory_bytes, w1.memory_bytes + w2.memory_bytes);
    assert_eq!(s.process_count, w1.process_count + w2.process_count);
    let cpu: f64 = s
        .windows
        .iter()
        .flat_map(|w| &w.panes)
        .map(|p| p.cpu_percent)
        .sum();
    assert!((s.cpu_percent - cpu).abs() < 1e-9);
}

#[test]
fn a_pane_whose_root_exited_reports_zero() {
    let snap = build(&map(), &table(), status(), 0);
    let d = &snap.sessions[0].windows[1].panes[1];
    assert_eq!(d.id, "block:d");
    assert_eq!(
        (d.memory_bytes, d.process_count, d.cpu_percent),
        (0, 0, 0.0)
    );
    assert!(d.processes.is_empty());
}

#[test]
fn kinds_and_program_names() {
    let snap = build(&map(), &table(), status(), 0);
    let panes: Vec<_> = snap.sessions[0]
        .windows
        .iter()
        .flat_map(|w| &w.panes)
        .collect();
    let kp = |i: usize| (panes[i].kind(), panes[i].program.as_str());
    assert_eq!(kp(0), (PaneKind::Claude, "claude"));
    assert_eq!(panes[0].working_directory, "/work/202");
    assert_eq!(kp(1), (PaneKind::Shell, "zsh"), "leading dash dropped");
    assert_eq!(kp(2), (PaneKind::Program, "nvim"));
}

#[test]
fn claude_is_found_in_the_subtree_when_something_else_is_in_front() {
    // Claude has started `cargo` in the foreground.
    let p = fake::process(
        200,
        Some(info(250, "cargo", "/x/cargo", "cargo")),
        vec![claude_fg(202), zsh(201), login(200)],
    );
    let m = PaneMap {
        sessions: vec![SessionInfo {
            windows: vec![WindowInfo {
                panes: vec![pane_info("block:a", p)],
                ..WindowInfo::default()
            }],
            ..SessionInfo::default()
        }],
    };
    let snap = build(&m, &table(), status(), 0);
    let pane = &snap.sessions[0].windows[0].panes[0];
    assert_eq!(
        (pane.kind(), pane.program.as_str()),
        (PaneKind::Claude, "claude")
    );
}

#[test]
fn claude_is_recognised_by_argv0_or_path_despite_its_version_name() {
    let by_argv0 = info(9, "2.1.328", "/somewhere/else", "claude");
    let by_path = info(9, "2.1.328", "/u/.local/share/claude/versions/2.1.328", "");
    let version_only = info(9, "2.1.328", "/opt/2.1.328", "2.1.328");
    assert!(is_claude_info(&by_argv0) && is_claude_info(&by_path));
    assert!(!is_claude_info(&version_only));
    let p = fake::process(1, Some(by_path), vec![]);
    assert_eq!(kind_and_program(&p, false).0, PaneKind::Claude);
}

#[test]
fn shell_versus_program() {
    // An exec'd command: the root is the program itself.
    let sleep = info(42, "sleep", "/bin/sleep", "sleep");
    let mut p = fake::process(42, Some(sleep.clone()), vec![]);
    p.child = Some(sleep);
    assert_eq!(
        kind_and_program(&p, false),
        (PaneKind::Program, "sleep".into())
    );
    // A nested shell is a program, not the pane's own shell.
    let nested = fake::process(
        200,
        Some(info(260, "bash", "/bin/bash", "bash")),
        vec![zsh(201), login(200)],
    );
    assert_eq!(
        kind_and_program(&nested, false),
        (PaneKind::Program, "bash".into())
    );
    // No foreground yet.
    let none = fake::process(200, None, vec![]);
    assert_eq!(
        kind_and_program(&none, false),
        (PaneKind::Shell, String::new())
    );
    // A shell started directly, without login.
    let mut direct = fake::process(70, Some(info(70, "fish", "/x/fish", "fish")), vec![]);
    direct.child = Some(info(70, "fish", "/x/fish", "fish"));
    assert_eq!(kind_and_program(&direct, false).0, PaneKind::Shell);
}

#[test]
fn program_names_fall_back_to_the_executable_name() {
    assert_eq!(
        program_name(&info(1, "nvim", "/x", "/opt/bin/nvim")),
        "nvim"
    );
    assert_eq!(program_name(&info(1, "python3.12", "/x", "")), "python3.12");
    assert_eq!(program_name(&info(1, "zsh", "/x", "-zsh")), "zsh");
}

#[test]
fn a_pane_rex_could_not_describe_is_listed_empty() {
    let m = PaneMap {
        sessions: vec![SessionInfo {
            windows: vec![WindowInfo {
                panes: vec![PaneInfo {
                    id: "block:x".into(),
                    ..PaneInfo::default()
                }],
                ..WindowInfo::default()
            }],
            ..SessionInfo::default()
        }],
    };
    let pane = &build(&m, &table(), status(), 0).sessions[0].windows[0].panes[0];
    assert_eq!((pane.kind(), pane.memory_bytes), (PaneKind::Unspecified, 0));
}
