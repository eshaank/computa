//! The `Monitor` gRPC service and the function that serves it.

use std::future::Future;
use std::pin::Pin;

use tokio::net::TcpListener;
use tokio_stream::wrappers::{IntervalStream, TcpListenerStream};
use tokio_stream::{Stream, StreamExt};
use tonic::transport::Server;
use tonic::{Request, Response, Status};

use super::ticks::{clamp_interval, make_tick};
use crate::pb::monitor_server::{Monitor, MonitorServer};
use crate::pb::{Tick, WatchTicksRequest};

type TickStream = Pin<Box<dyn Stream<Item = Result<Tick, Status>> + Send>>;

#[derive(Debug, Default)]
struct MonitorService;

#[tonic::async_trait]
impl Monitor for MonitorService {
    type WatchTicksStream = TickStream;

    async fn watch_ticks(
        &self,
        request: Request<WatchTicksRequest>,
    ) -> Result<Response<Self::WatchTicksStream>, Status> {
        let peer = request.remote_addr();
        let interval = clamp_interval(request.into_inner().interval_ms);
        tracing::info!(?peer, ?interval, "client started watching ticks");

        let mut sequence = 0_u64;
        let ticks = IntervalStream::new(tokio::time::interval(interval)).map(move |_| {
            sequence += 1;
            Ok(make_tick(sequence))
        });
        Ok(Response::new(Box::pin(ticks)))
    }
}

/// Serves the API on `listener` until `shutdown` completes.
///
/// # Errors
///
/// Returns the transport error if the server stops for any reason other
/// than `shutdown` completing.
pub async fn serve(
    listener: TcpListener,
    shutdown: impl Future<Output = ()>,
) -> Result<(), tonic::transport::Error> {
    Server::builder()
        .add_service(MonitorServer::new(MonitorService))
        .serve_with_incoming_shutdown(TcpListenerStream::new(listener), shutdown)
        .await
}
