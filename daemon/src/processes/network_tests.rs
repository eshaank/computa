//! The process monitor with network measuring: when the meter runs, and
//! what the frames carry.

use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use crate::nettop::fake::{FakeLauncher, Script, data};
use crate::nettop::{Chunk, Launcher, MeterConfig};
use crate::processes::table::fixture::proc;
use crate::processes::{Frame, PassFactory, ProcessMonitor, ProcessTable, Subscription};

const EVERY: Duration = Duration::from_millis(30);

fn quick() -> MeterConfig {
    MeterConfig {
        poll: Duration::from_millis(10),
        ..MeterConfig::default()
    }
}

/// A readable process (pid 5, its own group) and a hidden root daemon
/// (pid 7, in the system group with readable pid 8).
fn monitor(launcher: Arc<dyn Launcher>) -> ProcessMonitor {
    let factory: PassFactory = Arc::new(|| {
        Box::new(|_now| {
            ProcessTable::new(vec![
                proc(5, 1, "/opt/x", Some(100)),
                proc(7, 1, "/usr/sbin/mDNSResponder", None),
                proc(8, 1, "/usr/libexec/y", Some(10)),
            ])
        })
    });
    ProcessMonitor::with_network(factory, Duration::from_millis(20), launcher, quick())
}

/// Counters that grow by 1000 in and 100 out per sample for pid 5, and by
/// 50 in for the hidden pid 7.
fn growing(samples: u64) -> Vec<Chunk> {
    (0..samples)
        .map(|i| {
            let (rx, tx, hidden) = (1000 * i, 100 * i, 50 * i);
            data(&format!(
                ",bytes_in,bytes_out,\r\nx.5,{rx},{tx},\r\nmDNSResponder.7,{hidden},0,\r\n"
            ))
        })
        .collect()
}

fn wait_for(sub: &Subscription, what: &str, ok: impl Fn(&Frame) -> bool) -> Arc<Frame> {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if let Some(f) = sub.latest().filter(|f| ok(f)) {
            return f;
        }
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn a_plain_subscriber_never_starts_the_meter() {
    let fake = FakeLauncher::new(vec![]);
    let m = monitor(fake.clone());
    let plain = m.subscribe(EVERY).expect("subscribe");
    let frame = wait_for(&plain, "two frames", |f| f.seq >= 2);
    assert!(frame.networked.is_none());
    assert!(frame.snapshot.network.is_none());
    assert_eq!(fake.launches(), 0);
    assert!(!m.is_measuring_network());
}

#[test]
fn the_meter_runs_while_any_network_subscriber_remains() {
    let fake = FakeLauncher::new(vec![]);
    let m = monitor(fake.clone());
    let plain = m.subscribe(EVERY).expect("subscribe");
    let a = m.subscribe_with(EVERY, true).expect("subscribe");
    let b = m.subscribe_with(EVERY, true).expect("subscribe");
    wait_for(&plain, "a networked frame", |f| f.networked.is_some());
    assert_eq!((fake.launches(), fake.live()), (1, 1), "one shared child");
    drop(a);
    assert_eq!(fake.live(), 1, "b still wants it");
    drop(b);
    assert_eq!(fake.live(), 0, "stopped as the last one left");
    assert!(!m.is_measuring_network());
    assert!(m.is_sampling(), "the plain subscriber keeps sampling");
    let after = plain.latest().map_or(0, |f| f.seq);
    let frame = wait_for(&plain, "a later frame", |f| f.seq > after);
    assert!(frame.networked.is_none());
}

#[test]
fn networked_frames_carry_rates_and_list_hidden_processes_with_traffic() {
    let paced = Script::Paced(growing(200), Duration::from_millis(15));
    let fake = FakeLauncher::new(vec![paced]);
    let m = monitor(fake);
    let sub = m.subscribe_with(EVERY, true).expect("subscribe");
    let frame = wait_for(&sub, "rates", |f| {
        f.networked
            .as_ref()
            .is_some_and(|s| s.network.as_ref().is_some_and(|n| n.available))
    });
    let plain = &frame.snapshot;
    assert!(plain.network.is_none(), "the plain snapshot has no traffic");
    assert_eq!(
        plain
            .groups
            .iter()
            .map(|g| g.processes.len())
            .sum::<usize>(),
        2
    );

    let s = frame.networked.as_ref().expect("networked");
    assert_eq!(s.hidden.expect("hidden").process_count, 1, "still hidden");
    let x = s.groups.iter().find(|g| g.id == "pid:5").expect("x");
    let p5 = &x.processes[0];
    assert!(p5.rx_bytes_per_sec > 0.0 && p5.tx_bytes_per_sec > 0.0);
    assert!((p5.rx_bytes_per_sec / p5.tx_bytes_per_sec - 10.0).abs() < 1e-6);
    assert_eq!(x.rx_bytes_per_sec, p5.rx_bytes_per_sec);

    let system = s.groups.iter().find(|g| g.id == "system").expect("system");
    let mut pids: Vec<i32> = system.processes.iter().map(|p| p.pid).collect();
    pids.sort_unstable();
    assert_eq!(
        pids,
        vec![7, 8],
        "the hidden daemon is listed for its traffic"
    );
    let hidden = system.processes.iter().find(|p| p.pid == 7).expect("7");
    assert_eq!((hidden.cpu_percent, hidden.memory_bytes), (0.0, 0));
    assert!(hidden.rx_bytes_per_sec > 0.0);
    let sum: f64 = system.processes.iter().map(|p| p.rx_bytes_per_sec).sum();
    assert_eq!(system.rx_bytes_per_sec, sum);
    assert_eq!(system.memory_bytes, 10, "the hidden one adds no memory");
}

#[test]
fn the_first_networked_frames_are_not_available_and_have_no_problem() {
    let fake = FakeLauncher::new(vec![Script::Run(Vec::new())]);
    let m = monitor(fake);
    let sub = m.subscribe_with(EVERY, true).expect("subscribe");
    let frame = wait_for(&sub, "a networked frame", |f| f.networked.is_some());
    let status = frame.networked.as_ref().and_then(|s| s.network.clone());
    let status = status.expect("status");
    assert!(!status.available && status.problem.is_empty(), "{status:?}");
}

#[test]
fn shutdown_stops_the_meter_while_subscribers_remain() {
    let fake = FakeLauncher::new(vec![]);
    let m = monitor(fake.clone());
    let sub = m.subscribe_with(EVERY, true).expect("subscribe");
    wait_for(&sub, "a networked frame", |f| f.networked.is_some());
    m.shutdown_network();
    assert_eq!(fake.live(), 0);
    let after = sub.latest().map_or(0, |f| f.seq);
    let frame = wait_for(&sub, "a later frame", |f| f.seq > after);
    let status = frame.networked.as_ref().and_then(|s| s.network.clone());
    assert_eq!(
        status.expect("status").problem,
        "the daemon is shutting down"
    );
    let again = m.subscribe_with(EVERY, true).expect("subscribe");
    assert_eq!(fake.launches(), 1, "no restart after shutdown");
    drop(again);
}
