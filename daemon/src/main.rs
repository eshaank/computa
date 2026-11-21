//! Entry point for the computad daemon.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use tokio::net::TcpListener;
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::Notify;

use computad::processes::ProcessMonitor;
use computad::rex::CliRex;
use computad::sampler::Sampler;
use computad::sessions::SessionMonitor;
use computad::{DEFAULT_LISTEN_ADDR, rpc};

/// Overrides the listen address, for example `127.0.0.1:7301`.
const LISTEN_ENV: &str = "COMPUTAD_LISTEN";
/// How long open client streams may delay stopping.
const SHUTDOWN_GRACE: Duration = Duration::from_millis(500);

/// Two workers are plenty for a handful of local clients and keep memory low.
#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_target(false).init();
    log_panics();

    let addr = listen_addr()?;
    let sampler = Arc::new(Sampler::start().inspect_err(|error| {
        tracing::error!(error = format!("{error:#}"), "could not start sampling")
    })?);
    let processes = ProcessMonitor::darwin();
    let sessions = SessionMonitor::new(Arc::new(CliRex::from_env()), processes.clone());
    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("could not listen on {addr}"))?;
    tracing::info!(%addr, version = env!("CARGO_PKG_VERSION"), "computad is listening");

    let stopping = Arc::new(Notify::new());
    let signal = {
        let stopping = Arc::clone(&stopping);
        async move {
            shutdown_signal().await;
            stopping.notify_one();
        }
    };
    // Open streams never end on their own, so a graceful shutdown would wait
    // for clients forever. Give them a moment, then stop regardless.
    let grace = async {
        stopping.notified().await;
        tokio::time::sleep(SHUTDOWN_GRACE).await;
    };
    let served = tokio::select! {
        result = rpc::serve(listener, sampler, processes.clone(), sessions, signal) => result
            .inspect_err(|error| tracing::error!(%error, "the gRPC server stopped with an error"))
            .context("the gRPC server failed"),
        () = grace => {
            tracing::info!("clients were still connected; closing their streams");
            Ok(())
        }
    };
    // Streams that are still open hold the network meter; stop its nettop
    // child now, however the server ended, rather than leave it to whichever
    // task is dropped last.
    processes.shutdown_network();
    served?;

    tracing::info!("computad stopped");
    Ok(())
}

fn listen_addr() -> anyhow::Result<SocketAddr> {
    let raw = std::env::var(LISTEN_ENV).unwrap_or_else(|_| DEFAULT_LISTEN_ADDR.to_owned());
    raw.parse()
        .with_context(|| format!("{LISTEN_ENV} is not a valid address: {raw:?}"))
}

/// Completes when the daemon is asked to stop: Ctrl-C in a terminal, or
/// SIGTERM, which launchd sends.
async fn shutdown_signal() {
    let terminate = async {
        match signal(SignalKind::terminate()) {
            Ok(mut stream) => {
                stream.recv().await;
            }
            Err(error) => {
                tracing::error!(%error, "could not listen for SIGTERM; only Ctrl-C stops the daemon");
                std::future::pending::<()>().await;
            }
        }
    };
    tokio::select! {
        result = tokio::signal::ctrl_c() => match result {
            Ok(()) => tracing::info!("received Ctrl-C; shutting down"),
            Err(error) => tracing::error!(%error, "could not listen for Ctrl-C; stopping now"),
        },
        () = terminate => tracing::info!("received SIGTERM; shutting down"),
    }
}

/// Sends panics to the log, so a crash under launchd leaves a record.
fn log_panics() {
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        tracing::error!(%info, "computad panicked");
        default_hook(info);
    }));
}
