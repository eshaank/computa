//! The gRPC server and the service it exposes.

mod processes;
mod server;
mod watch;

pub use server::serve;
