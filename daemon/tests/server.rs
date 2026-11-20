//! Starts the real daemon on a free port and checks facts that must hold
//! for numbers read from this machine.

use std::sync::Arc;
use std::time::Duration;

use computad::pb::monitor_client::MonitorClient;
use computad::pb::{
    GetHistoryRequest, GetHostRequest, History, Host, SystemSample, WatchSystemRequest,
};
use computad::processes::ProcessMonitor;
use computad::rex::CliRex;
use computad::rpc;
use computad::sampler::Sampler;
use computad::sessions::SessionMonitor;
use tokio::net::TcpListener;
use tonic::transport::Channel;

async fn start() -> (MonitorClient<Channel>, tokio::sync::oneshot::Sender<()>) {
    let sampler = Arc::new(Sampler::start().expect("sampler starts"));
    let processes = ProcessMonitor::darwin();
    let sessions = SessionMonitor::new(Arc::new(CliRex::from_env()), processes.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    tokio::spawn(async move {
        let shutdown = async {
            let _ = stop_rx.await;
        };
        rpc::serve(listener, sampler, processes, sessions, shutdown)
            .await
            .expect("server runs");
    });
    let client = MonitorClient::connect(format!("http://{addr}"))
        .await
        .expect("connect");
    (client, stop_tx)
}

fn check_sample(s: &SystemSample, core_total: usize) {
    check_cpu(s, core_total);
    check_memory_and_volumes(s);
    check_network_and_battery(s);
}

fn check_cpu(s: &SystemSample, core_total: usize) {
    let cpu = s.cpu.as_ref().expect("cpu");
    assert_eq!(cpu.cores.len(), core_total, "one entry per core");
    for pct in [cpu.usage_percent, cpu.user_percent, cpu.system_percent] {
        assert!((0.0..=100.0).contains(&pct), "cpu percent {pct}");
    }
    assert!((cpu.usage_percent - cpu.user_percent - cpu.system_percent).abs() < 1e-6);
    for (i, core) in cpu.cores.iter().enumerate() {
        assert_eq!(core.index as usize, i);
        assert!(
            (0.0..=100.0).contains(&core.usage_percent),
            "core {i}: {}",
            core.usage_percent
        );
    }
}

fn check_memory_and_volumes(s: &SystemSample) {
    let mem = s.memory.as_ref().expect("memory");
    assert!(
        mem.used_bytes > 0 && mem.used_bytes <= mem.total_bytes,
        "{mem:?}"
    );
    assert_eq!(
        mem.app_bytes + mem.wired_bytes + mem.compressed_bytes,
        mem.used_bytes
    );
    assert!(mem.swap_used_bytes <= mem.swap_total_bytes);

    let startup = s.volumes.first().expect("at least the startup volume");
    assert_eq!(startup.mount_point, "/");
    assert!(!startup.name.is_empty());
    for v in &s.volumes {
        assert!(v.total_bytes > 0, "{v:?}");
        assert!(v.used_bytes <= v.total_bytes, "{v:?}");
        assert_eq!(v.used_bytes + v.available_bytes, v.total_bytes, "{v:?}");
    }
}

fn check_network_and_battery(s: &SystemSample) {
    let net = s.network.as_ref().expect("network");
    assert!(net.rx_bytes_per_sec >= 0.0 && net.tx_bytes_per_sec >= 0.0);
    for iface in &net.interfaces {
        assert_ne!(iface.name, "lo0");
        assert!(!iface.addresses.is_empty());
        assert!(
            iface
                .addresses
                .iter()
                .all(|a| !a.to_lowercase().starts_with("fe80:"))
        );
    }
    if let Some(b) = &s.battery {
        assert!((0.0..=100.0).contains(&b.charge_percent));
    }
}

async fn history(
    client: &mut MonitorClient<Channel>,
    window_seconds: u32,
    max_points: u32,
) -> History {
    client
        .get_history(GetHistoryRequest {
            window_seconds,
            max_points,
        })
        .await
        .expect("GetHistory")
        .into_inner()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn host_and_samples_are_consistent() {
    let (mut client, _stop) = start().await;
    let host = check_host(&mut client).await;
    check_stream(&mut client, &host).await;
    check_history(&mut client).await;
}

async fn check_host(client: &mut MonitorClient<Channel>) -> Host {
    let host = client
        .get_host(GetHostRequest {})
        .await
        .expect("GetHost")
        .into_inner();
    assert!(!host.hostname.is_empty());
    assert!(host.memory_total_bytes > 0);
    assert!(host.os_version.starts_with("macOS "), "{}", host.os_version);
    assert_eq!(host.sample_interval_ms, 1000);
    assert_eq!(host.history_capacity, 3600);
    let core_total: u32 = host.core_groups.iter().map(|g| g.core_count).sum();
    assert!(core_total > 0);
    host
}

async fn check_stream(client: &mut MonitorClient<Channel>, host: &Host) {
    let core_total: u32 = host.core_groups.iter().map(|g| g.core_count).sum();
    let mut stream = client
        .watch_system(WatchSystemRequest { interval_ms: 2000 })
        .await
        .expect("WatchSystem")
        .into_inner();
    let mut times = Vec::new();
    for _ in 0..3 {
        let s = tokio::time::timeout(Duration::from_secs(5), stream.message())
            .await
            .expect("sample in time")
            .expect("stream ok")
            .expect("stream open");
        check_sample(&s, core_total as usize);
        assert_eq!(
            s.memory.as_ref().map(|m| m.total_bytes),
            Some(host.memory_total_bytes)
        );
        times.push(s.unix_ms);
    }
    // The first sample is sent at once; after that, one every 2 s.
    let gap = times[2] - times[1];
    assert!(
        (1700..=2300).contains(&gap),
        "gap between samples was {gap} ms"
    );
}

async fn check_history(client: &mut MonitorClient<Channel>) {
    let all = history(client, 0, 0).await;
    assert!(
        all.points.len() >= 3,
        "history has {} points",
        all.points.len()
    );
    assert_eq!(all.step_ms, 1000);
    assert!(
        all.points.windows(2).all(|w| w[0].unix_ms < w[1].unix_ms),
        "oldest first"
    );

    let few = history(client, 0, 2).await;
    assert!(few.points.len() <= 2 && !few.points.is_empty());
    assert!(
        few.step_ms > 1000,
        "step {} should cover averaged samples",
        few.step_ms
    );
    // A new sample may land between the two calls, so the newest point is
    // at least as new as before.
    assert!(few.points.last().map(|p| p.unix_ms) >= all.points.last().map(|p| p.unix_ms));

    let recent = history(client, 2, 0).await;
    assert!(recent.points.len() <= 3 && recent.points.len() < all.points.len());
}
