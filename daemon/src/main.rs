//! Entry point for the computad daemon.

use std::net::SocketAddr;

use anyhow::Context;
use tokio::net::TcpListener;

use computad::{DEFAULT_LISTEN_ADDR, rpc};

/// Overrides the listen address, for example `127.0.0.1:7301`.
const LISTEN_ENV: &str = "COMPUTAD_LISTEN";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_target(false).init();
    log_panics();

    let addr = listen_addr()?;
    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("could not listen on {addr}"))?;
    tracing::info!(%addr, version = env!("CARGO_PKG_VERSION"), "computad is listening");

    rpc::serve(listener, shutdown_signal())
        .await
        .inspect_err(|error| tracing::error!(%error, "the gRPC server stopped with an error"))
        .context("the gRPC server failed")?;

    tracing::info!("computad stopped");
    Ok(())
}

fn listen_addr() -> anyhow::Result<SocketAddr> {
    let raw = std::env::var(LISTEN_ENV).unwrap_or_else(|_| DEFAULT_LISTEN_ADDR.to_owned());
    raw.parse()
        .with_context(|| format!("{LISTEN_ENV} is not a valid address: {raw:?}"))
}

/// Completes when the daemon is asked to stop with Ctrl-C.
async fn shutdown_signal() {
    if let Err(error) = tokio::signal::ctrl_c().await {
        tracing::error!(%error, "could not listen for Ctrl-C; stopping now");
    } else {
        tracing::info!("received Ctrl-C; shutting down");
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
