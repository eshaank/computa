//! The tracker and its lifecycle, against a fake Rex, on paused time.

use std::sync::Arc;
use std::time::Duration;

use crate::processes::{PassFactory, ProcessMonitor, ProcessTable};
use crate::rex::RexError;
use crate::rex::fake::{self, FakeRex};
use crate::sessions::{RETRY_EVERY, SessionMonitor, SessionSubscription, View};

const S: &str = "session:a";

fn setup() -> (SessionMonitor, ProcessMonitor, Arc<FakeRex>) {
    let rex = Arc::new(FakeRex::default());
    rex.set_sessions(vec![fake::session(
        S,
        "work",
        &[("window:1", &["block:1", "block:2"])],
    )]);
    let factory: PassFactory = Arc::new(|| Box::new(|_| ProcessTable::new(vec![])));
    let processes = ProcessMonitor::new(factory, Duration::from_millis(5));
    let client: Arc<dyn crate::rex::RexClient> = rex.clone();
    (
        SessionMonitor::new(client, processes.clone()),
        processes,
        rex,
    )
}

/// Waits (in virtual time) for a published view that satisfies `pred`.
async fn wait_view(sub: &SessionSubscription, pred: impl Fn(&View) -> bool) -> Arc<View> {
    let mut rx = sub.views();
    let found = tokio::time::timeout(Duration::from_secs(120), async {
        loop {
            if let Some(v) = rx.borrow_and_update().clone().filter(|v| pred(v)) {
                return v;
            }
            rx.changed().await.expect("tracker alive");
        }
    })
    .await;
    found.expect("the expected view in time")
}

/// Lets spawned tasks run without moving the clock much.
async fn settle() {
    for _ in 0..20 {
        tokio::task::yield_now().await;
    }
}

async fn wait_until(what: &str, cond: impl Fn() -> bool) {
    for _ in 0..200 {
        if cond() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("timed out waiting until {what}");
}

#[tokio::test(start_paused = true)]
async fn starts_on_the_first_subscriber_and_stops_after_the_last() {
    let (monitor, processes, rex) = setup();
    settle().await;
    assert!(
        rex.calls().is_empty(),
        "nothing is asked of Rex without subscribers"
    );
    assert!(!processes.is_sampling() && !monitor.is_tracking());

    let a = monitor
        .subscribe(Duration::from_secs(2))
        .expect("subscribe");
    let b = monitor
        .subscribe(Duration::from_secs(1))
        .expect("subscribe");
    let v = wait_view(&a, |v| v.status.reachable).await;
    assert_eq!(v.map.pane_count(), 2);
    assert_eq!(v.status.version, "0.1.0-test");
    assert_eq!(rex.live_event_streams(), 1, "one event stream for both");
    assert!(processes.is_sampling());

    drop(a);
    settle().await;
    assert_eq!(rex.live_event_streams(), 1);
    assert!(processes.is_sampling() && monitor.is_tracking());

    drop(b);
    wait_until("the event stream is dropped", || {
        rex.live_event_streams() == 0
    })
    .await;
    assert!(!processes.is_sampling() && !monitor.is_tracking());

    let c = monitor
        .subscribe(Duration::from_secs(2))
        .expect("subscribe");
    wait_view(&c, |v| v.status.reachable).await;
    assert_eq!(
        rex.live_event_streams(),
        1,
        "a new subscriber starts afresh"
    );
}

#[tokio::test(start_paused = true)]
async fn unreachable_says_why_then_recovers_on_retry() {
    let (monitor, _processes, rex) = setup();
    rex.set_failure(Some(RexError::ServerNotRunning {
        command: "rex api call server.version".into(),
        stderr: "no Rex server is running".into(),
    }));
    let sub = monitor
        .subscribe(Duration::from_secs(2))
        .expect("subscribe");
    let down = wait_view(&sub, |_| true).await;
    assert!(!down.status.reachable);
    assert!(
        down.status.problem.contains("not running"),
        "{}",
        down.status.problem
    );
    assert!(down.map.sessions.is_empty());
    assert_eq!(rex.live_event_streams(), 0);

    rex.set_failure(None);
    let started = tokio::time::Instant::now();
    let up = wait_view(&sub, |v| v.status.reachable).await;
    let waited = started.elapsed();
    assert!(
        waited >= RETRY_EVERY - Duration::from_millis(50) && waited < RETRY_EVERY * 2,
        "retried after {waited:?}"
    );
    assert!(up.status.problem.is_empty());
    assert_eq!(up.map.pane_count(), 2);
    assert_eq!(rex.live_event_streams(), 1);

    // Rex goes away again: found at the next refresh, the stream is dropped.
    rex.set_failure(Some(RexError::NotFound {
        detail: "COMPUTAD_REX is /nonexistent/rex".into(),
    }));
    rex.end_event_streams();
    let gone = wait_view(&sub, |v| !v.status.reachable).await;
    assert!(
        gone.status
            .problem
            .starts_with("The rex command was not found")
    );
    assert_eq!(rex.live_event_streams(), 0);
}

const CLOSED: &str = r#"{"type":"session_event","payload":{"session_id":"session:a","event":{"type":"block_closed","payload":{"block_id":"block:2"}}}}"#;
const VIEW_CHANGED: &str = r#"{"type":"session_event","payload":{"session_id":"session:a","event":{"type":"session_view_changed","payload":{"revision":9}}}}"#;
const PROCESS_CHANGED: &str = r#"{"type":"session_event","payload":{"session_id":"session:a","event":{"type":"block_event","payload":{"block_id":"block:1","creator_name":"com.superlogical.terminal","name":"process_changed","payload":{"generation":2,"foreground":null}}}}}"#;

#[tokio::test(start_paused = true)]
async fn a_closed_pane_is_dropped_at_once_and_bursts_are_debounced() {
    let (monitor, _processes, rex) = setup();
    let sub = monitor
        .subscribe(Duration::from_secs(2))
        .expect("subscribe");
    wait_view(&sub, |v| v.status.reachable).await;
    rex.clear_calls();

    // Rex has already removed the pane when the event arrives.
    rex.set_sessions(vec![fake::session(
        S,
        "work",
        &[("window:1", &["block:1"])],
    )]);
    rex.push_event(CLOSED);
    for _ in 0..5 {
        rex.push_event(VIEW_CHANGED);
    }
    let v = wait_view(&sub, |v| v.map.pane_count() == 1).await;
    assert_eq!(v.map.sessions[0].windows[0].panes[0].id, "block:1");
    assert!(
        !rex.calls().iter().any(|c| c.starts_with("view")),
        "removed before any Rex call"
    );
    tokio::time::sleep(Duration::from_millis(400)).await;
    let views = rex.calls().iter().filter(|c| c.starts_with("view")).count();
    assert_eq!(views, 1, "six events, one refresh: {:?}", rex.calls());

    rex.clear_calls();
    rex.push_event(PROCESS_CHANGED);
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(
        rex.calls(),
        vec!["process block:1".to_owned()],
        "only that pane is re-read"
    );
}

#[tokio::test(start_paused = true)]
async fn the_event_stream_restarts_and_a_full_refresh_runs_every_30_seconds() {
    let (monitor, _processes, rex) = setup();
    let sub = monitor
        .subscribe(Duration::from_secs(2))
        .expect("subscribe");
    wait_view(&sub, |v| v.status.reachable).await;
    rex.clear_calls();

    rex.end_event_streams();
    tokio::time::sleep(Duration::from_millis(1500)).await;
    assert_eq!(rex.live_event_streams(), 1, "restarted");
    let calls = rex.calls();
    assert_eq!(
        &calls[..2],
        ["events", "list"],
        "restart, then catch up: {calls:?}"
    );
    let processes = calls.iter().filter(|c| c.starts_with("process")).count();
    assert_eq!(processes, 2, "after a gap every pane is re-read: {calls:?}");

    rex.clear_calls();
    tokio::time::sleep(Duration::from_secs(31)).await;
    let calls = rex.calls();
    assert_eq!(
        calls.iter().filter(|c| *c == "list").count(),
        1,
        "{calls:?}"
    );
    assert!(
        !calls.iter().any(|c| c.starts_with("process")),
        "the 30 s refresh reuses known panes' processes: {calls:?}"
    );
}
