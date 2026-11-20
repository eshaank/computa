use std::sync::atomic::{AtomicUsize, Ordering};

use super::*;
use crate::processes::table::fixture::proc;

const FIRST: Duration = Duration::from_millis(20);

/// Counts how often sampling started and how many passes ran.
#[derive(Default)]
struct Counts {
    starts: AtomicUsize,
    passes: AtomicUsize,
}

fn monitor() -> (ProcessMonitor, Arc<Counts>) {
    let counts = Arc::new(Counts::default());
    let c = Arc::clone(&counts);
    let factory: PassFactory = Arc::new(move || {
        c.starts.fetch_add(1, Ordering::SeqCst);
        let c = Arc::clone(&c);
        Box::new(move |_now| {
            c.passes.fetch_add(1, Ordering::SeqCst);
            ProcessTable::new(vec![proc(5, 1, "/opt/x", Some(100))])
        })
    });
    let m = ProcessMonitor::new(factory, FIRST);
    (m, counts)
}

/// Waits up to two seconds for the subscription's next frame.
fn next_frame(sub: &Subscription, after_seq: u64) -> Arc<Frame> {
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if let Some(f) = sub.latest().filter(|f| f.seq > after_seq) {
            return f;
        }
        thread::sleep(Duration::from_millis(2));
    }
    panic!("no frame after seq {after_seq}");
}

/// Waits until the sampling thread has stopped taking passes.
fn settled(counts: &Counts) -> usize {
    let mut last = counts.passes.load(Ordering::SeqCst);
    loop {
        thread::sleep(Duration::from_millis(80));
        let now = counts.passes.load(Ordering::SeqCst);
        if now == last {
            return now;
        }
        last = now;
    }
}

#[test]
fn nothing_is_sampled_without_a_subscriber() {
    let (m, counts) = monitor();
    thread::sleep(Duration::from_millis(60));
    assert_eq!(counts.starts.load(Ordering::SeqCst), 0);
    assert_eq!(counts.passes.load(Ordering::SeqCst), 0);
    assert!(!m.is_sampling());
}

#[test]
fn first_subscriber_starts_sampling_and_last_one_stops_it() {
    let (m, counts) = monitor();
    let a = m.subscribe(Duration::from_millis(30)).expect("subscribe");
    let frame = next_frame(&a, 0);
    assert_eq!(frame.seq, 1);
    assert_eq!(frame.snapshot.process_count, 1);
    assert!(
        counts.passes.load(Ordering::SeqCst) >= 2,
        "priming pass first"
    );

    let b = m.subscribe(Duration::from_millis(30)).expect("subscribe");
    assert_eq!(m.subscriber_count(), 2);
    drop(a);
    assert!(m.is_sampling(), "one subscriber left");
    let before = b.latest().map_or(0, |f| f.seq);
    next_frame(&b, before);
    drop(b);
    assert!(!m.is_sampling());
    assert_eq!(m.subscriber_count(), 0);
    let stopped_at = settled(&counts);
    thread::sleep(Duration::from_millis(150));
    assert_eq!(
        counts.passes.load(Ordering::SeqCst),
        stopped_at,
        "no passes after the last left"
    );
    assert_eq!(
        counts.starts.load(Ordering::SeqCst),
        1,
        "both shared one sampler"
    );
}

#[test]
fn a_new_session_starts_fresh_with_no_stale_frame() {
    let (m, counts) = monitor();
    let a = m.subscribe(Duration::from_millis(30)).expect("subscribe");
    next_frame(&a, 0);
    drop(a);
    let b = m.subscribe(Duration::from_millis(30)).expect("subscribe");
    assert!(b.latest().is_none(), "the old frame was cleared");
    assert_eq!(next_frame(&b, 0).seq, 1);
    assert_eq!(counts.starts.load(Ordering::SeqCst), 2);
}

#[test]
fn sampler_runs_at_the_shortest_interval_requested() {
    let (m, _counts) = monitor();
    let slow = m.subscribe(Duration::from_millis(400)).expect("subscribe");
    let f1 = next_frame(&slow, 0);
    let fast = m.subscribe(Duration::from_millis(40)).expect("subscribe");
    let f2 = next_frame(&fast, f1.seq);
    let f3 = next_frame(&fast, f2.seq);
    let gap = f3.at.duration_since(f2.at);
    assert!(
        gap >= Duration::from_millis(35) && gap < Duration::from_millis(200),
        "gap {gap:?} should follow the 40 ms subscriber"
    );
    drop(fast);
    let f4 = next_frame(&slow, f3.seq);
    let f5 = next_frame(&slow, f4.seq);
    let gap = f5.at.duration_since(f4.at);
    assert!(
        gap >= Duration::from_millis(380),
        "gap {gap:?} back to 400 ms"
    );
}
