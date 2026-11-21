//! The `Monitor` gRPC service and the function that serves it.

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use tokio::net::TcpListener;
use tokio_stream::Stream;
use tokio_stream::wrappers::TcpListenerStream;
use tonic::transport::Server;
use tonic::{Request, Response, Status};

use super::{processes, sessions, watch};
use crate::icons::{IconError, IconService};
use crate::pb::monitor_server::{Monitor, MonitorServer};
use crate::pb::{
    AppIcon, GetAppIconRequest, GetHistoryRequest, GetHostRequest, History, Host, ProcessSnapshot,
    SessionsSnapshot, SystemSample, WatchProcessesRequest, WatchSessionsRequest,
    WatchSystemRequest,
};
use crate::processes::ProcessMonitor;
use crate::sampler::{SAMPLE_INTERVAL_MS, Sampler};
use crate::sessions::SessionMonitor;

type SampleStream = Pin<Box<dyn Stream<Item = Result<SystemSample, Status>> + Send>>;
type SnapshotStream = Pin<Box<dyn Stream<Item = Result<ProcessSnapshot, Status>> + Send>>;
type SessionsStream = Pin<Box<dyn Stream<Item = Result<SessionsSnapshot, Status>> + Send>>;

#[derive(Debug)]
struct MonitorService {
    sampler: Arc<Sampler>,
    processes: ProcessMonitor,
    sessions: SessionMonitor,
    icons: IconService,
}

#[tonic::async_trait]
impl Monitor for MonitorService {
    type WatchSystemStream = SampleStream;
    type WatchProcessesStream = SnapshotStream;
    type WatchSessionsStream = SessionsStream;

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

    async fn watch_processes(
        &self,
        request: Request<WatchProcessesRequest>,
    ) -> Result<Response<Self::WatchProcessesStream>, Status> {
        let request = request.into_inner();
        let (requested, network) = (request.interval_ms, request.include_network);
        let interval_ms = processes::round_interval(requested);
        tracing::debug!(
            requested,
            interval_ms,
            network,
            "starting a WatchProcesses stream"
        );
        let interval = Duration::from_millis(u64::from(interval_ms));
        let subscription = self
            .processes
            .subscribe_with(interval, network)
            .map_err(|error| {
                tracing::error!(
                    error = format!("{error:#}"),
                    "could not start process sampling"
                );
                Status::internal("could not start process sampling")
            })?;
        let stream = processes::stream(subscription, interval, network);
        Ok(Response::new(Box::pin(stream)))
    }

    async fn watch_sessions(
        &self,
        request: Request<WatchSessionsRequest>,
    ) -> Result<Response<Self::WatchSessionsStream>, Status> {
        let requested = request.into_inner().interval_ms;
        let interval_ms = processes::round_interval(requested);
        tracing::debug!(requested, interval_ms, "starting a WatchSessions stream");
        let interval = Duration::from_millis(u64::from(interval_ms));
        let subscription = self.sessions.subscribe(interval).map_err(|error| {
            tracing::error!(
                error = format!("{error:#}"),
                "could not start watching Rex sessions"
            );
            Status::internal("could not start process sampling")
        })?;
        let stream = sessions::stream(subscription, interval);
        Ok(Response::new(Box::pin(stream)))
    }

    async fn get_app_icon(
        &self,
        request: Request<GetAppIconRequest>,
    ) -> Result<Response<AppIcon>, Status> {
        let bundle_path = request.into_inner().bundle_path;
        match self.icons.png(bundle_path).await {
            Ok(png) => Ok(Response::new(AppIcon { png })),
            Err(IconError::InvalidPath(message)) => {
                tracing::debug!(message, "refused a GetAppIcon request");
                Err(Status::invalid_argument(message))
            }
            Err(IconError::Internal) => Err(Status::internal("could not read the app icon")),
        }
    }
}

/// Serves the API on `listener`, with system numbers from `sampler`,
/// process numbers from `processes` and Rex sessions from `sessions`, until
/// `shutdown` completes.
///
/// # Errors
///
/// Returns the transport error if the server stops for any reason other
/// than `shutdown` completing.
pub async fn serve(
    listener: TcpListener,
    sampler: Arc<Sampler>,
    processes: ProcessMonitor,
    sessions: SessionMonitor,
    shutdown: impl Future<Output = ()>,
) -> Result<(), tonic::transport::Error> {
    Server::builder()
        .add_service(MonitorServer::new(MonitorService {
            sampler,
            processes,
            sessions,
            icons: IconService::default(),
        }))
        .serve_with_incoming_shutdown(TcpListenerStream::new(listener), shutdown)
        .await
}
