//! Starts the real daemon with the real `nettop` and checks per-process
//! network traffic end to end. Run outside Claude's sandbox: inside it,
//! `nettop` cannot start and ports cannot be opened.
//!
//! `reconcile_with_the_interface_totals` downloads 1 GB from the internet,
//! so it is ignored by default: `cargo test --test network -- --ignored
//! --nocapture` prints the comparison.

use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, Instant};

use computad::pb::monitor_client::MonitorClient;
use computad::pb::{ProcessSnapshot, WatchProcessesRequest, WatchSystemRequest};
use computad::processes::ProcessMonitor;
use computad::rex::CliRex;
use computad::rpc;
use computad::sampler::Sampler;
use computad::sessions::SessionMonitor;
use tokio::net::TcpListener;
use tonic::Streaming;
use tonic::transport::Channel;

async fn start() -> (MonitorClient<Channel>, ProcessMonitor) {
    let sampler = Arc::new(Sampler::start().expect("sampler starts"));
    let processes = ProcessMonitor::darwin();
    let sessions = SessionMonitor::new(Arc::new(CliRex::from_env()), processes.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let served = processes.clone();
    tokio::spawn(async move {
        rpc::serve(listener, sampler, served, sessions, std::future::pending())
            .await
            .expect("server runs");
    });
    let client = MonitorClient::connect(format!("http://{addr}"))
        .await
        .expect("connect");
    (client, processes)
}

async fn watch(client: &mut MonitorClient<Channel>, network: bool) -> Streaming<ProcessSnapshot> {
    let request = WatchProcessesRequest {
        interval_ms: 1000,
        include_network: network,
    };
    client
        .watch_processes(request)
        .await
        .expect("WatchProcesses")
        .into_inner()
}

async fn next(stream: &mut Streaming<ProcessSnapshot>) -> ProcessSnapshot {
    tokio::time::timeout(Duration::from_secs(5), stream.message())
        .await
        .expect("snapshot in time")
        .expect("stream ok")
        .expect("stream open")
}

/// Whether `pid` names any process, a zombie included.
fn exists(pid: u32) -> bool {
    let pid = libc::pid_t::try_from(pid).expect("pid fits");
    // SAFETY: signal 0 only checks that the process exists.
    let rc = unsafe { libc::kill(pid, 0) };
    rc == 0 || std::io::Error::last_os_error().raw_os_error() != Some(libc::ESRCH)
}

/// The command line of `pid` and its parent, from `ps`.
fn ps(pid: u32) -> Option<(u32, String)> {
    let out = Command::new("ps")
        .args(["-o", "ppid=,command=", "-p", &pid.to_string()])
        .output()
        .expect("ps runs");
    let text = String::from_utf8_lossy(&out.stdout).trim().to_owned();
    let (ppid, command) = text.split_once(' ')?;
    Some((ppid.parse().ok()?, command.to_owned()))
}

/// Waits up to three seconds for the meter's nettop to start.
async fn child_pid(processes: &ProcessMonitor) -> u32 {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if let Some(pid) = processes.network_child_pid() {
            return pid;
        }
        assert!(Instant::now() < deadline, "nettop never started");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

/// Waits up to three seconds for `pid` to be killed and reaped.
async fn wait_reaped(processes: &ProcessMonitor, pid: u32) {
    let deadline = Instant::now() + Duration::from_secs(3);
    while exists(pid) || processes.network_child_pid().is_some() {
        assert!(
            Instant::now() < deadline,
            "nettop {pid} outlived its last client"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn check_group_sums(s: &ProcessSnapshot) {
    for g in &s.groups {
        let rx: f64 = g.processes.iter().map(|p| p.rx_bytes_per_sec).sum();
        let tx: f64 = g.processes.iter().map(|p| p.tx_bytes_per_sec).sum();
        assert!((g.rx_bytes_per_sec - rx).abs() < 1e-6, "group {} rx", g.id);
        assert!((g.tx_bytes_per_sec - tx).abs() < 1e-6, "group {} tx", g.id);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn nettop_runs_only_while_asked_and_is_reaped_after() {
    let (mut client, processes) = start().await;
    let mut plain = watch(&mut client, false).await;
    for _ in 0..2 {
        let s = next(&mut plain).await;
        assert!(s.network.is_none());
        assert!(s.groups.iter().all(|g| g.rx_bytes_per_sec == 0.0));
    }
    assert_eq!(processes.network_child_pid(), None, "no nettop for plain");

    let mut net = watch(&mut client, true).await;
    let first = next(&mut net).await;
    let status = first.network.expect("status");
    assert!(!status.available && status.problem.is_empty(), "{status:?}");
    let pid = child_pid(&processes).await;
    let (ppid, command) = ps(pid).expect("nettop is listed");
    assert_eq!(ppid, std::process::id(), "a child of this process");
    assert!(command.starts_with("/usr/bin/nettop -P"), "{command}");

    let deadline = Instant::now() + Duration::from_secs(8);
    let available = loop {
        let s = next(&mut net).await;
        let status = s.network.clone().expect("status");
        assert!(status.problem.is_empty(), "{}", status.problem);
        if status.available {
            break s;
        }
        assert!(Instant::now() < deadline, "rates never became available");
    };
    check_group_sums(&available);

    drop(net);
    wait_reaped(&processes, pid).await;
    assert!(
        next(&mut plain).await.network.is_none(),
        "plain keeps going"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "downloads 1 GB; run by hand outside the sandbox"]
async fn reconcile_with_the_interface_totals() {
    let (mut client, _processes) = start().await;
    let mut curl = Command::new("curl")
        .args(["-s", "-o", "/dev/null", "--max-time", "25"])
        .arg("https://ash-speed.hetzner.com/1GB.bin")
        .spawn()
        .expect("curl starts");
    let mut net = watch(&mut client, true).await;
    let mut system = client
        .watch_system(WatchSystemRequest { interval_ms: 1000 })
        .await
        .expect("WatchSystem")
        .into_inner();
    let (mut procs, mut ifaces, mut n) = ((0.0, 0.0), (0.0, 0.0), 0);
    while n < 12 {
        let s = next(&mut net).await;
        let sample = system.message().await.expect("ok").expect("open");
        if !s.network.as_ref().is_some_and(|st| st.available) {
            continue;
        }
        let rx: f64 = s.groups.iter().map(|g| g.rx_bytes_per_sec).sum();
        let tx: f64 = s.groups.iter().map(|g| g.tx_bytes_per_sec).sum();
        let link = sample.network.expect("network");
        println!(
            "processes rx {:9.0} tx {:8.0}   interfaces rx {:9.0} tx {:8.0}",
            rx, tx, link.rx_bytes_per_sec, link.tx_bytes_per_sec
        );
        procs = (procs.0 + rx, procs.1 + tx);
        ifaces = (
            ifaces.0 + link.rx_bytes_per_sec,
            ifaces.1 + link.tx_bytes_per_sec,
        );
        n += 1;
    }
    curl.kill().expect("curl stops");
    curl.wait().expect("curl reaped");
    println!(
        "over {n} s: processes/interfaces rx {:.3} tx {:.3}",
        procs.0 / ifaces.0,
        procs.1 / ifaces.1
    );
}
