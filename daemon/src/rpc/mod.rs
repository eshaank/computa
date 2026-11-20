//! The gRPC server and the service it exposes.

mod processes;
mod server;
mod sessions;
mod watch;

pub use server::serve;
