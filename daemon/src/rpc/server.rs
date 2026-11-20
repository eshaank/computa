//! The `Monitor` gRPC service and the function that serves it.

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use tokio::net::TcpListener;
use tokio_stream::Stream;
use tokio_stream::wrappers::TcpListenerStream;
use tonic::transport::Server;
use tonic::{Request, Response, Status};

use super::watch;
use crate::pb::monitor_server::{Monitor, MonitorServer};
use crate::pb::{
    GetHistoryRequest, GetHostRequest, History, Host, SystemSample, WatchSystemRequest,
};
use crate::sampler::{SAMPLE_INTERVAL_MS, Sampler};

type SampleStream = Pin<Box<dyn Stream<Item = Result<SystemSample, Status>> + Send>>;

#[derive(Debug)]
struct MonitorService {
    sampler: Arc<Sampler>,
}

#[tonic::async_trait]
impl Monitor for MonitorService {
    type WatchSystemStream = SampleStream;

    async fn get_host(&self, _request: Request<GetHostRequest>) -> Result<Response<Host>, Status> {
        Ok(Response::new(self.sampler.host().clone()))
    }

    async fn watch_system(
        &self,
        request: Request<WatchSystemRequest>,
    ) -> Result<Response<Self::WatchSystemStream>, Status> {
        let requested = request.into_inner().interval_ms;
        let (interval_ms, steps) = watch::round_interval(requested, SAMPLE_INTERVAL_MS);
        tracing::debug!(requested, interval_ms, "starting a WatchSystem stream");
        let stream = watch::stream(self.sampler.subscribe(), steps);
        Ok(Response::new(Box::pin(stream)))
    }

    async fn get_history(
        &self,
        request: Request<GetHistoryRequest>,
    ) -> Result<Response<History>, Status> {
        let req = request.into_inner();
        Ok(Response::new(
            self.sampler.history(req.window_seconds, req.max_points),
        ))
    }
}

/// Serves the API on `listener`, with numbers from `sampler`, until
/// `shutdown` completes.
///
/// # Errors
///
/// Returns the transport error if the server stops for any reason other
/// than `shutdown` completing.
pub async fn serve(
    listener: TcpListener,
    sampler: Arc<Sampler>,
    shutdown: impl Future<Output = ()>,
) -> Result<(), tonic::transport::Error> {
    Server::builder()
        .add_service(MonitorServer::new(MonitorService { sampler }))
        .serve_with_incoming_shutdown(TcpListenerStream::new(listener), shutdown)
        .await
}
