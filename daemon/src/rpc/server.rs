//! The `Monitor` gRPC service and the function that serves it.

use std::future::Future;
use std::pin::Pin;

use tokio::net::TcpListener;
use tokio_stream::Stream;
use tokio_stream::wrappers::TcpListenerStream;
use tonic::transport::Server;
use tonic::{Request, Response, Status};

use crate::pb::monitor_server::{Monitor, MonitorServer};
use crate::pb::{
    GetHistoryRequest, GetHostRequest, History, Host, SystemSample, WatchSystemRequest,
};

type SampleStream = Pin<Box<dyn Stream<Item = Result<SystemSample, Status>> + Send>>;

#[derive(Debug, Default)]
struct MonitorService;

#[tonic::async_trait]
impl Monitor for MonitorService {
    type WatchSystemStream = SampleStream;

    async fn get_host(&self, _request: Request<GetHostRequest>) -> Result<Response<Host>, Status> {
        Err(Status::unimplemented("GetHost is not implemented yet"))
    }

    async fn watch_system(
        &self,
        _request: Request<WatchSystemRequest>,
    ) -> Result<Response<Self::WatchSystemStream>, Status> {
        Err(Status::unimplemented("WatchSystem is not implemented yet"))
    }

    async fn get_history(
        &self,
        _request: Request<GetHistoryRequest>,
    ) -> Result<Response<History>, Status> {
        Err(Status::unimplemented("GetHistory is not implemented yet"))
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
