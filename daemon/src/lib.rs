//! computad: collects system metrics and serves them over gRPC.

pub mod rpc;

/// Types and service traits generated from `proto/computa/v1/monitor.proto`.
pub mod pb {
    tonic::include_proto!("computa.v1");
}

/// The address the daemon listens on unless told otherwise. It is the local
/// machine only: the API has no authentication of its own.
pub const DEFAULT_LISTEN_ADDR: &str = "127.0.0.1:7300";
