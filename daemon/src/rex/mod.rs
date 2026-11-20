//! Talking to Rex, the terminal multiplexer, through its `rex` CLI.
//!
//! [`RexClient`] is what the sessions monitor needs from Rex. [`CliRex`]
//! runs the real CLI; tests use a fake.

mod cli;
mod error;
pub mod events;
mod locate;
pub mod model;

#[cfg(test)]
pub mod fake;

pub use cli::CliRex;
pub use error::RexError;
pub use locate::{KNOWN_LOCATION, REX_ENV, locate, locate_from_env};
pub use model::{PaneProcess, ProcInfo, SessionRef, SessionView};

/// What the daemon asks of Rex. Every call may fail; errors say which
/// command failed and why.
#[tonic::async_trait]
pub trait RexClient: Send + Sync + 'static {
    /// The Rex server's version, for example "0.1.0-preview.14". Also proves
    /// the server can be reached.
    async fn version(&self) -> Result<String, RexError>;
    async fn list_sessions(&self) -> Result<Vec<SessionRef>, RexError>;
    async fn view_session(&self, session_id: &str) -> Result<SessionView, RexError>;
    /// The processes in one pane.
    async fn pane_process(&self, session_id: &str, block_id: &str)
    -> Result<PaneProcess, RexError>;
    /// Starts one stream of every server event. Dropping it stops the
    /// stream (and kills the process behind it).
    async fn events(&self) -> Result<Box<dyn EventLines>, RexError>;
}

/// A running event stream, one JSON object per line.
#[tonic::async_trait]
pub trait EventLines: Send {
    /// The next line, or `None` when the stream ended cleanly.
    async fn next_line(&mut self) -> Result<Option<String>, RexError>;
}
