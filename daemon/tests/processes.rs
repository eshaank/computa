//! Starts the real daemon on a free port, calls `WatchProcesses`, and checks
//! facts that must hold for this machine's processes. Run outside Claude's
//! sandbox, which hides other processes.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use computad::pb::monitor_client::MonitorClient;
use computad::pb::{ProcessSnapshot, WatchProcessesRequest};
use computad::processes::ProcessMonitor;
use computad::rpc;
use computad::sampler::Sampler;
use tokio::net::TcpListener;
use tonic::Streaming;
use tonic::transport::Channel;

async fn start() -> (MonitorClient<Channel>, tokio::sync::oneshot::Sender<()>) {
    let sampler = Arc::new(Sampler::start().expect("sampler starts"));
    let processes = ProcessMonitor::darwin();
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    tokio::spawn(async move {
        let shutdown = async {
            let _ = stop_rx.await;
        };
        rpc::serve(listener, sampler, processes, shutdown)
            .await
            .expect("server runs");
    });
    let client = MonitorClient::connect(format!("http://{addr}"))
        .await
        .expect("connect");
    (client, stop_tx)
}

async fn next(stream: &mut Streaming<ProcessSnapshot>) -> ProcessSnapshot {
    tokio::time::timeout(Duration::from_secs(5), stream.message())
        .await
        .expect("snapshot in time")
        .expect("stream ok")
        .expect("stream open")
}

/// Each listed pid appears once; group totals are sums of their processes.
fn check_consistent(s: &ProcessSnapshot) {
    let mut seen: HashMap<i32, &str> = HashMap::new();
    for g in &s.groups {
        assert!(!g.processes.is_empty(), "group {} is listed empty", g.id);
        let mem: u64 = g.processes.iter().map(|p| p.memory_bytes).sum();
        let cpu: f64 = g.processes.iter().map(|p| p.cpu_percent).sum();
        assert_eq!(g.memory_bytes, mem, "group {} memory", g.id);
        assert!((g.cpu_percent - cpu).abs() < 1e-6, "group {} cpu", g.id);
        assert_eq!(g.bundle_path.is_empty(), !g.id.starts_with('/'), "{}", g.id);
        for p in &g.processes {
            assert!(p.cpu_percent >= 0.0, "pid {} cpu {}", p.pid, p.cpu_percent);
            if let Some(other) = seen.insert(p.pid, &g.id) {
                panic!("pid {} is in groups {other} and {}", p.pid, g.id);
            }
        }
    }
    let hidden = s.hidden.expect("hidden");
    assert_eq!(
        seen.len() + hidden.process_count as usize,
        s.process_count as usize
    );
    assert!(s.process_count > 1, "more than this test is visible");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn snapshots_are_consistent_and_include_this_process() {
    let (mut client, _stop) = start().await;
    let started = Instant::now();
    let mut stream = client
        .watch_processes(WatchProcessesRequest { interval_ms: 2000 })
        .await
        .expect("WatchProcesses")
        .into_inner();

    let first = next(&mut stream).await;
    let first_after = started.elapsed();
    assert!(
        first_after < Duration::from_millis(2500),
        "first after {first_after:?}"
    );
    check_consistent(&first);

    let me = i32::try_from(std::process::id()).expect("pid fits");
    let mine: Vec<_> = first
        .groups
        .iter()
        .flat_map(|g| g.processes.iter().map(move |p| (g, p)))
        .filter(|(_, p)| p.pid == me)
        .collect();
    assert_eq!(mine.len(), 1, "own pid appears exactly once");
    let (group, me_proc) = mine[0];
    assert!(me_proc.memory_bytes > 0 && me_proc.resident_bytes > 0);
    assert!(!me_proc.path.is_empty() && !me_proc.name.is_empty());
    assert!(!group.name.is_empty());

    let second = next(&mut stream).await;
    check_consistent(&second);
    let gap = second.unix_ms - first.unix_ms;
    assert!(
        (1700..=2400).contains(&gap),
        "gap between snapshots {gap} ms"
    );
}
