//! The real pty launcher on real children (a shell script that prints the
//! nettop format). Needs a pseudo-terminal, which Claude's sandbox refuses,
//! so run these outside it.

use std::io;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use computad::nettop::{Chunk, Feed, Launcher, MeterConfig, PtyLauncher};
use computad::processes::{PassFactory, ProcessMonitor, ProcessTable};

const EVERY: Duration = Duration::from_millis(30);

/// Prints the nettop format once a second, forever.
const LOOP: &str = "while :; do printf ',bytes_in,bytes_out,\\nsh.%d,1,2,\\n' $$; sleep 1; done";

/// Whether `pid` names any process, a zombie included.
fn exists(pid: u32) -> bool {
    let pid = libc::pid_t::try_from(pid).expect("pid fits");
    // SAFETY: signal 0 only checks that the process exists.
    let rc = unsafe { libc::kill(pid, 0) };
    rc == 0 || io::Error::last_os_error().raw_os_error() != Some(libc::ESRCH)
}

/// Reads until the output contains `want` or the child ends.
fn read_until(feed: &mut dyn Feed, want: &str) -> (String, Option<String>) {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut text = String::new();
    while Instant::now() < deadline {
        match feed.read(Duration::from_millis(100)).expect("reads") {
            Chunk::Data(d) => text.push_str(&String::from_utf8_lossy(&d)),
            Chunk::Idle => {}
            Chunk::Ended(how) => return (text, Some(how)),
        }
        if text.contains(want) {
            return (text, None);
        }
    }
    panic!("no {want:?} within 5 s; got {text:?}");
}

#[test]
fn output_arrives_line_by_line_and_stop_reaps_the_child() {
    let launcher = PtyLauncher::new("/bin/sh", &["-c", LOOP]);
    let mut feed = launcher.launch().expect("starts");
    let pid = feed.pid();
    let (text, ended) = read_until(feed.as_mut(), &format!("sh.{pid},1,2,"));
    assert!(ended.is_none());
    assert!(text.starts_with(",bytes_in,bytes_out,\r\n"), "{text:?}");
    assert!(exists(pid));
    feed.stop().expect("stops");
    assert!(!exists(pid), "pid {pid} is gone, not a zombie");
    feed.stop().expect("a second stop does nothing");
}

#[test]
fn dropping_the_feed_reaps_the_child() {
    let launcher = PtyLauncher::new("/bin/sh", &["-c", LOOP]);
    let feed = launcher.launch().expect("starts");
    let pid = feed.pid();
    drop(feed);
    assert!(!exists(pid));
}

#[test]
fn an_exit_is_reported_with_what_it_printed() {
    let launcher = PtyLauncher::new("/bin/sh", &["-c", "echo 'nettop: failed' >&2; exit 70"]);
    let mut feed = launcher.launch().expect("starts");
    let pid = feed.pid();
    let (text, ended) = read_until(feed.as_mut(), "\u{0}never");
    assert!(
        text.contains("nettop: failed"),
        "stderr goes to the pty: {text:?}"
    );
    assert_eq!(ended.as_deref(), Some("exit status: 70"));
    assert!(!exists(pid));
}

#[test]
fn a_missing_program_says_so() {
    let launcher = PtyLauncher::new("/nonexistent/nettop", &[]);
    let error = launcher.launch().err().expect("fails");
    let text = format!("{error:#}");
    assert!(
        text.contains("could not start /nonexistent/nettop"),
        "{text}"
    );
    assert!(text.contains("ships with macOS"), "{text}");
}

/// The real launcher on a real child: when the last network subscriber
/// leaves, the child is gone (not running, not a zombie), though a plain
/// subscriber keeps sampling.
#[test]
fn the_real_child_is_reaped_when_the_last_network_subscriber_leaves() {
    let factory: PassFactory = Arc::new(|| Box::new(|_now| ProcessTable::default()));
    let launcher = Arc::new(PtyLauncher::new("/bin/sh", &["-c", LOOP]));
    let config = MeterConfig {
        poll: Duration::from_millis(10),
        ..MeterConfig::default()
    };
    let m = ProcessMonitor::with_network(factory, Duration::from_millis(20), launcher, config);
    let plain = m.subscribe(EVERY).expect("subscribe");
    let net = m.subscribe_with(EVERY, true).expect("subscribe");
    let deadline = Instant::now() + Duration::from_secs(3);
    let pid = loop {
        if let Some(pid) = m.network_child_pid() {
            break pid;
        }
        assert!(Instant::now() < deadline, "the child never started");
        thread::sleep(Duration::from_millis(5));
    };
    assert!(exists(pid));
    drop(net);
    assert!(!exists(pid), "pid {pid} was killed and reaped");
    assert!(m.is_sampling());
    drop(plain);
}
