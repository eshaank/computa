use super::*;
use crate::processes::table::fixture::proc;

const CHROME: &str = "/Applications/Google Chrome.app";
const REX: &str = "/Applications/Rex.app";

fn table() -> ProcessTable {
    ProcessTable::new(vec![
        proc(0, 0, "", None),
        proc(1, 0, "/sbin/launchd", None),
        // Chrome and a nested helper bundle.
        proc(
            10,
            1,
            &format!("{CHROME}/Contents/MacOS/Google Chrome"),
            Some(100),
        ),
        proc(
            11,
            10,
            &format!(
                "{CHROME}/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/\
                 Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
            ),
            Some(30),
        ),
        // A terminal pane: Rex server -> login (root) -> zsh -> claude.
        proc(20, 1, &format!("{REX}/Contents/MacOS/rex-server"), Some(50)),
        proc(21, 20, "/usr/bin/login", None),
        proc(22, 21, "/bin/zsh", Some(5)),
        proc(
            23,
            22,
            "/Users/me/.local/share/claude/versions/2.1.328",
            Some(400),
        ),
        // System daemons, readable and not.
        proc(30, 1, "/usr/libexec/trustd", Some(8)),
        proc(
            31,
            1,
            "/System/Library/Frameworks/X.framework/xpcd",
            Some(2),
        ),
        proc(32, 1, "/Library/Apple/System/Library/foo", Some(1)),
        proc(33, 1, "/usr/sbin/rootd", None),
        // User software outside any app.
        proc(40, 1, "/usr/local/bin/tmux", Some(6)),
        proc(41, 40, "/opt/homebrew/bin/node", Some(60)),
        proc(42, 41, "/opt/homebrew/bin/esbuild", Some(9)),
        proc(43, 41, "/bin/sh", Some(1)),
    ])
}

fn key_of(t: &ProcessTable, pid: i32) -> GroupKey {
    group_key(t, t.get(pid).expect("pid in fixture"))
}

#[test]
fn outermost_app_is_found_and_must_be_a_directory() {
    let helper = format!("{CHROME}/Contents/Frameworks/H.app/Contents/MacOS/H");
    assert_eq!(outermost_app(&helper), Some(CHROME));
    assert_eq!(outermost_app("/usr/bin/zsh"), None);
    assert_eq!(
        outermost_app("/tmp/weird.app"),
        None,
        "a file, not a bundle"
    );
    assert_eq!(outermost_app("/tmp/.app/x"), None, "no name before .app");
    assert_eq!(outermost_app(""), None);
}

#[test]
fn nested_helper_belongs_to_the_outermost_app() {
    let t = table();
    assert_eq!(key_of(&t, 11), GroupKey::App(CHROME.to_owned()));
    assert_eq!(key_of(&t, 10), GroupKey::App(CHROME.to_owned()));
}

#[test]
fn children_inherit_the_app_through_an_unreadable_parent() {
    let t = table();
    let rex = GroupKey::App(REX.to_owned());
    for pid in [21, 22, 23] {
        assert_eq!(key_of(&t, pid), rex, "pid {pid}");
    }
}

#[test]
fn system_paths_go_to_the_system_group() {
    let t = table();
    for pid in [0, 1, 30, 31, 32, 33, 43] {
        assert_eq!(key_of(&t, pid), GroupKey::System, "pid {pid}");
    }
}

#[test]
fn usr_local_is_not_system() {
    assert!(!is_system_path("/usr/local/bin/tmux"));
    assert!(is_system_path("/usr/bin/login"));
    assert!(!is_system_path("/usrx/bin/a"));
    assert_eq!(key_of(&table(), 40), GroupKey::Pid(40));
}

#[test]
fn other_processes_group_under_their_top_ancestor_below_launchd() {
    let t = table();
    assert_eq!(key_of(&t, 41), GroupKey::Pid(40));
    assert_eq!(key_of(&t, 42), GroupKey::Pid(40));
}

#[test]
fn missing_parent_makes_the_process_its_own_top() {
    let t = ProcessTable::new(vec![proc(70, 69, "/opt/x/bin/orphan", Some(1))]);
    assert_eq!(key_of(&t, 70), GroupKey::Pid(70));
}

#[test]
fn parent_cycle_terminates_and_members_agree() {
    let t = ProcessTable::new(vec![
        proc(1, 0, "/sbin/launchd", None),
        proc(50, 52, "/opt/a", Some(1)),
        proc(51, 50, "/opt/b", Some(1)),
        proc(52, 51, "/opt/c", Some(1)),
        proc(53, 53, "/opt/self", Some(1)),
    ]);
    for pid in [50, 51, 52] {
        assert_eq!(key_of(&t, pid), GroupKey::Pid(50), "pid {pid}");
    }
    assert_eq!(key_of(&t, 53), GroupKey::Pid(53));
}

#[test]
fn snapshot_lists_readable_processes_and_sums_groups() {
    let t = table();
    let s = snapshot(&t, 7, None);
    assert_eq!(s.unix_ms, 7);
    assert_eq!(s.process_count, 16);
    let hidden = s.hidden.expect("hidden");
    assert_eq!(hidden.process_count, 4);
    let listed: usize = s.groups.iter().map(|g| g.processes.len()).sum();
    assert_eq!(listed + hidden.process_count as usize, 16);

    let rex = s.groups.iter().find(|g| g.id == REX).expect("rex group");
    assert_eq!((rex.name.as_str(), rex.bundle_path.as_str()), ("Rex", REX));
    let mut pids: Vec<i32> = rex.processes.iter().map(|p| p.pid).collect();
    pids.sort_unstable();
    assert_eq!(pids, vec![20, 22, 23], "unreadable login is not listed");
    assert_eq!(rex.memory_bytes, 455);
    assert_eq!(rex.resident_bytes, 2 * 455, "in-RAM size is summed too");
    assert!((rex.cpu_percent - 45.5).abs() < 1e-9);

    let tmux = s
        .groups
        .iter()
        .find(|g| g.id == "pid:40")
        .expect("tmux group");
    assert_eq!(
        (tmux.name.as_str(), tmux.bundle_path.as_str()),
        ("tmux", "")
    );
    let system = s.groups.iter().find(|g| g.id == SYSTEM_ID).expect("system");
    assert_eq!(system.name, "System");
    assert_eq!(system.memory_bytes, 8 + 2 + 1 + 1);
    assert_eq!(system.resident_bytes, 2 * (8 + 2 + 1 + 1));
}

#[test]
fn groups_without_readable_processes_are_left_out() {
    let t = ProcessTable::new(vec![
        proc(1, 0, "/sbin/launchd", None),
        proc(60, 1, "/opt/rootonly", None),
    ]);
    let s = snapshot(&t, 0, None);
    assert!(s.groups.is_empty());
    assert_eq!(s.hidden.expect("hidden").process_count, 2);
}
