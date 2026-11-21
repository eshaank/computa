use std::time::{Duration, Instant};

use super::*;
use crate::nettop::parse::Counter;

fn reading(run: u64, seq: u64, at: Instant, rows: &[(i32, &str, u64, u64)]) -> Reading {
    let counters = rows
        .iter()
        .map(|&(pid, name, rx, tx)| {
            let c = Counter {
                name: name.into(),
                rx,
                tx,
            };
            (pid, c)
        })
        .collect();
    Reading {
        run,
        seq,
        at,
        counters,
    }
}

fn status(latest: Option<&Arc<Reading>>, problem: Option<&str>) -> MeterStatus {
    MeterStatus {
        latest: latest.cloned(),
        problem: problem.map(str::to_owned),
    }
}

#[test]
fn rates_are_deltas_over_the_seconds_between_readings() {
    let t0 = Instant::now();
    let a = reading(1, 1, t0, &[(10, "curl", 1_000, 50), (11, "apsd", 500, 500)]);
    let b = reading(
        1,
        2,
        t0 + Duration::from_secs(2),
        &[(10, "curl", 9_000, 250), (11, "apsd", 500, 500)],
    );
    let r = rates(&a, &b).expect("later");
    assert_eq!(
        r[&10],
        Rate {
            rx: 4_000.0,
            tx: 100.0
        }
    );
    assert_eq!(r[&11], Rate::default());
}

#[test]
fn falling_counters_new_pids_and_reused_pids() {
    let t0 = Instant::now();
    let a = reading(1, 1, t0, &[(10, "curl", 9_000, 900), (12, "old", 5_000, 0)]);
    let b = reading(
        1,
        2,
        t0 + Duration::from_secs(1),
        &[
            (10, "curl", 1_000, 1_000),
            (12, "new", 300, 30),
            (13, "fresh", 70, 7),
        ],
    );
    let r = rates(&a, &b).expect("later");
    assert_eq!(
        r[&10],
        Rate { rx: 0.0, tx: 100.0 },
        "a drop is clamped to zero"
    );
    assert_eq!(
        r[&12],
        Rate {
            rx: 300.0,
            tx: 30.0
        },
        "a reused pid starts at zero"
    );
    assert_eq!(
        r[&13],
        Rate { rx: 70.0, tx: 7.0 },
        "a new pid starts at zero"
    );
    assert!(!r.contains_key(&99));
}

#[test]
fn readings_at_the_same_moment_give_no_rates() {
    let t0 = Instant::now();
    let a = reading(1, 1, t0, &[]);
    assert!(rates(&a, &a).is_none());
    let earlier = reading(1, 0, t0 - Duration::from_secs(1), &[]);
    assert!(rates(&a, &earlier).is_none());
}

#[test]
fn tracker_needs_two_readings_and_reuses_rates_until_a_new_one() {
    let t0 = Instant::now();
    let a = Arc::new(reading(1, 1, t0, &[(10, "curl", 0, 0)]));
    let b = Arc::new(reading(
        1,
        2,
        t0 + Duration::from_secs(1),
        &[(10, "curl", 800, 8)],
    ));
    let mut t = NetTracker::default();

    let first = t.update(Some(&status(None, None))).expect("asked");
    assert!(!first.status.available && first.status.problem.is_empty());

    let second = t.update(Some(&status(Some(&a), None))).expect("asked");
    assert!(!second.status.available, "one reading is not enough");
    assert!(second.status.problem.is_empty());
    assert_eq!(second.rates[&10], Rate::default(), "listed, at zero");

    let third = t.update(Some(&status(Some(&b), None))).expect("asked");
    assert!(third.status.available);
    assert_eq!(third.rates[&10], Rate { rx: 800.0, tx: 8.0 });

    let again = t.update(Some(&status(Some(&b), None))).expect("asked");
    assert_eq!(again, third, "no new reading: same rates");
}

#[test]
fn a_new_run_starts_over_and_a_problem_makes_it_unavailable() {
    let t0 = Instant::now();
    let a = Arc::new(reading(1, 1, t0, &[(10, "curl", 0, 0)]));
    let b = Arc::new(reading(
        1,
        2,
        t0 + Duration::from_secs(1),
        &[(10, "curl", 10, 0)],
    ));
    let restarted = Arc::new(reading(
        2,
        1,
        t0 + Duration::from_secs(2),
        &[(10, "curl", 5, 0)],
    ));
    let mut t = NetTracker::default();
    t.update(Some(&status(Some(&a), None)));
    assert!(
        t.update(Some(&status(Some(&b), None)))
            .expect("asked")
            .status
            .available
    );

    let failed = t
        .update(Some(&status(Some(&b), Some("nettop exited"))))
        .expect("asked");
    assert_eq!(
        (failed.status.available, failed.status.problem.as_str()),
        (false, "nettop exited")
    );
    assert_eq!(failed.rates[&10], Rate::default());

    let fresh = t
        .update(Some(&status(Some(&restarted), None)))
        .expect("asked");
    assert!(!fresh.status.available, "counters restarted with the run");
    assert!(fresh.status.problem.is_empty());

    assert!(t.update(None).is_none(), "nobody asked");
    let after = t
        .update(Some(&status(Some(&restarted), None)))
        .expect("asked");
    assert!(!after.status.available, "stopping forgot the old reading");
}
