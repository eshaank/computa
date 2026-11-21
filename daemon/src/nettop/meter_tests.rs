use super::*;
use crate::nettop::fake::{FakeLauncher, Script, data};

fn quick() -> MeterConfig {
    MeterConfig {
        retry_first: Duration::from_millis(40),
        retry_max: Duration::from_millis(160),
        stale_after: Duration::from_secs(5),
        poll: Duration::from_millis(10),
    }
}

/// Waits up to two seconds for `ready` to hold.
fn until(what: &str, mut ready: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(2);
    while !ready() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn readings_are_published_as_samples_complete() {
    let fake = FakeLauncher::new(vec![Script::Run(vec![
        data(",bytes_in,bytes_out,\r\ncurl.9,100,1,\r\n"),
        data(",bytes_in,bytes_out,\r\ncurl.9,900,2,\r\n"),
        data(",bytes_in,bytes_out,\r\n"),
    ])]);
    let meter = NetMeter::start(fake.clone(), quick()).expect("starts");
    until("two readings", || {
        meter
            .status(Instant::now())
            .latest
            .is_some_and(|r| r.seq == 2)
    });
    let status = meter.status(Instant::now());
    let latest = status.latest.expect("reading");
    assert_eq!(latest.counters[&9].rx, 900);
    assert!(status.problem.is_none());
    assert_eq!(meter.child_pid(), Some(1000));
    drop(meter);
    assert_eq!((fake.launches(), fake.live()), (1, 0), "stopped on drop");
}

#[test]
fn a_launch_failure_is_a_problem_and_retries_back_off() {
    let fake = FakeLauncher::new(vec![
        Script::Fail(
            "could not start /usr/bin/nettop: No such file".into()
        );
        20
    ]);
    let meter = NetMeter::start(fake.clone(), quick()).expect("starts");
    until("a problem", || {
        meter.status(Instant::now()).problem.is_some()
    });
    let problem = meter.status(Instant::now()).problem.expect("problem");
    assert!(
        problem.starts_with("could not start /usr/bin/nettop"),
        "{problem}"
    );
    assert!(problem.contains("trying again in"), "{problem}");
    thread::sleep(Duration::from_millis(400));
    // 40 + 80 + 160 + 160 ms of waiting fit in 400 ms: about five tries,
    // where a tight loop would have made thousands.
    let tries = fake.launches();
    assert!((2..=6).contains(&tries), "{tries} launches in 400 ms");
    assert_eq!(meter.child_pid(), None);
}

#[test]
fn an_exit_says_what_nettop_printed_and_it_restarts() {
    let fake = FakeLauncher::new(vec![
        Script::Run(vec![
            data("nettop: NStatManagerCreate failed\r\n"),
            Chunk::Ended("exit status: 70".into()),
        ]),
        Script::Run(vec![data(
            ",bytes_in,bytes_out,\r\na.1,1,1,\r\n,bytes_in,bytes_out,\r\n",
        )]),
    ]);
    let meter = NetMeter::start(fake.clone(), quick()).expect("starts");
    until("the exit", || {
        meter.status(Instant::now()).problem.is_some()
    });
    let problem = meter.status(Instant::now()).problem.expect("problem");
    assert!(
        problem.starts_with(
            "nettop exited (exit status: 70) after printing \u{201c}nettop: NStatManagerCreate failed\u{201d}"
        ),
        "{problem}"
    );
    until("the restart", || {
        meter.status(Instant::now()).latest.is_some()
    });
    let status = meter.status(Instant::now());
    assert!(
        status.problem.is_none(),
        "a good reading clears the problem"
    );
    assert_eq!(fake.launches(), 2);
    assert_eq!(fake.live(), 1);
    drop(meter);
    assert_eq!(fake.live(), 0);
}

#[test]
fn an_odd_line_is_a_problem_until_the_next_reading() {
    let fake = FakeLauncher::new(vec![Script::Run(vec![data(
        ",bytes_in,bytes_out,\r\nwhat is this\r\n",
    )])]);
    let meter = NetMeter::start(fake, quick()).expect("starts");
    until("a problem", || {
        meter.status(Instant::now()).problem.is_some()
    });
    let problem = meter.status(Instant::now()).problem.expect("problem");
    assert!(problem.contains("what is this"), "{problem}");
}

#[test]
fn an_old_reading_is_reported_as_stale() {
    let fake = FakeLauncher::new(vec![Script::Run(vec![data(
        ",bytes_in,bytes_out,\r\n,bytes_in,bytes_out,\r\n",
    )])]);
    let meter = NetMeter::start(fake, quick()).expect("starts");
    until("a reading", || {
        meter.status(Instant::now()).latest.is_some()
    });
    assert!(meter.status(Instant::now()).problem.is_none());
    let later = Instant::now() + Duration::from_secs(9);
    let problem = meter.status(later).problem.expect("stale");
    assert!(
        problem.starts_with("nettop has not reported for"),
        "{problem}"
    );
}
