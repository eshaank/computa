//! The gRPC server and the service it exposes.

mod server;
mod ticks;

pub use server::serve;
pub use ticks::{clamp_interval, tick_value};
