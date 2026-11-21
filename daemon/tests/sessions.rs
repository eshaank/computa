//! Starts the real daemon on a free port, creates a throwaway Rex session,
//! calls `WatchSessions`, and checks the session is reported with sensible
//! numbers. Skips itself (with a printed reason) when Rex is not available.
//! Run outside Claude's sandbox, which blocks the Rex socket.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;

use computad::pb::monitor_client::MonitorClient;
use computad::pb::{PaneKind, Session, SessionsSnapshot, WatchSessionsRequest};
use computad::processes::ProcessMonitor;
use computad::rex::{CliRex, locate_from_env};
use computad::rpc;
use computad::sampler::Sampler;
use computad::sessions::SessionMonitor;
use tokio::net::TcpListener;
use tonic::Streaming;
use tonic::transport::Channel;

/// Kills the throwaway session when the test ends, pass or fail.
struct Throwaway {
    rex: PathBuf,
    id: String,
}

impl Drop for Throwaway {
    fn drop(&mut self) {
        let out = Command::new(&self.rex)
            .args(["--autostart=false", "kill", &self.id])
            .output();
        match out {
            Ok(o) if o.status.success() => {}
            Ok(o) => eprintln!(
                "could not kill {}: {}: {}",
                self.id,
                o.status,
                String::from_utf8_lossy(&o.stderr)
            ),
            Err(e) => eprintln!("could not run rex kill {}: {e}", self.id),
        }
    }
}

/// Creates a session running `sleep 600`, or says why it could not.
fn create_session(rex: &Path, label: &str) -> Result<Throwaway, String> {
    let out = Command::new(rex)
        .args([
            "--autostart=false",
            "new",
            label,
            "--json",
            "--",
            "sleep",
            "600",
        ])
        .output()
        .map_err(|e| format!("could not run rex: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "rex new failed ({}): {}",
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let v: serde_json::Value =
        serde_json::from_slice(&out.stdout).map_err(|e| format!("rex new printed: {e}"))?;
    let id = v["session_id"].as_str().ok_or("no session_id")?.to_owned();
    Ok(Throwaway {
        rex: rex.to_owned(),
        id,
    })
}

/// Serves the API on a free port for the rest of the test.
async fn start(rex: PathBuf) -> MonitorClient<Channel> {
    let sampler = Arc::new(Sampler::start().expect("sampler starts"));
    let processes = ProcessMonitor::darwin();
    let sessions = SessionMonitor::new(Arc::new(CliRex::at(rex)), processes.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("local addr");
    tokio::spawn(async move {
        rpc::serve(
            listener,
            sampler,
            processes,
            sessions,
            std::future::pending(),
        )
        .await
        .expect("server runs");
    });
    MonitorClient::connect(format!("http://{addr}"))
        .await
        .expect("connect")
}

async fn next(stream: &mut Streaming<SessionsSnapshot>) -> SessionsSnapshot {
    tokio::time::timeout(Duration::from_secs(10), stream.message())
        .await
        .expect("snapshot in time")
        .expect("stream ok")
        .expect("stream open")
}

fn check_totals(s: &Session) {
    let mut mem = 0;
    let mut cpu = 0.0;
    let mut count = 0;
    for w in &s.windows {
        let pm: u64 = w.panes.iter().map(|p| p.memory_bytes).sum();
        let pc: f64 = w.panes.iter().map(|p| p.cpu_percent).sum();
        let pn: u32 = w.panes.iter().map(|p| p.process_count).sum();
        assert_eq!(w.memory_bytes, pm, "tab {} memory", w.id);
        assert!((w.cpu_percent - pc).abs() < 1e-6, "tab {} cpu", w.id);
        assert_eq!(w.process_count, pn, "tab {} processes", w.id);
        for p in &w.panes {
            let readable: u64 = p.processes.iter().map(|x| x.memory_bytes).sum();
            assert_eq!(p.memory_bytes, readable, "pane {} memory", p.id);
        }
        (mem, cpu, count) = (mem + w.memory_bytes, cpu + w.cpu_percent, count + pn);
    }
    assert_eq!(s.memory_bytes, mem, "session {} memory", s.label);
    assert!(
        (s.cpu_percent - cpu).abs() < 1e-6,
        "session {} cpu",
        s.label
    );
    assert_eq!(s.process_count, count, "session {} processes", s.label);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn reports_a_throwaway_session_with_consistent_totals() {
    let rex = match locate_from_env() {
        Ok(p) => p,
        Err(e) => {
            println!("SKIPPED: Rex is not available here: {e}");
            return;
        }
    };
    let label = format!("computa-it-{}", std::process::id());
    let session = match create_session(&rex, &label) {
        Ok(s) => s,
        Err(reason) => {
            println!("SKIPPED: could not create a Rex session: {reason}");
            return;
        }
    };

    let mut client = start(rex).await;
    let mut stream = client
        .watch_sessions(WatchSessionsRequest { interval_ms: 1000 })
        .await
        .expect("WatchSessions")
        .into_inner();

    let snap = next(&mut stream).await;
    let status = snap.rex.clone().expect("rex status");
    assert!(status.reachable, "unreachable: {}", status.problem);
    assert!(!status.version.is_empty());
    let mine = snap
        .sessions
        .iter()
        .find(|s| s.label == label)
        .unwrap_or_else(|| panic!("{label} is listed"));
    assert_eq!(mine.id, session.id);
    let panes: Vec<_> = mine.windows.iter().flat_map(|w| &w.panes).collect();
    assert_eq!(panes.len(), 1, "one pane");
    assert!(panes[0].process_count >= 1);
    assert_eq!(
        (panes[0].kind(), panes[0].program.as_str()),
        (PaneKind::Program, "sleep")
    );
    for s in &snap.sessions {
        check_totals(s);
    }
}
