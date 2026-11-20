//! The gRPC server and the service it exposes.

mod server;
mod watch;

pub use server::serve;
