//! Per-process network traffic, read from macOS's `nettop`.
//!
//! `nettop` prints, once a second, each process's bytes in and out since it
//! started watching. The daemon runs it only while a client asked for
//! network numbers ([`NetMeter`]), parses its CSV ([`parse`]) and turns two
//! readings into rates ([`rates`]).
//!
//! The child process sits behind [`Launcher`] and [`Feed`]: [`PtyLauncher`]
//! runs the real program, tests use a fake.

mod meter;
pub mod parse;
mod pty;
pub mod rates;

#[cfg(test)]
pub mod fake;

use std::io;
use std::time::Duration;

pub use meter::{MeterConfig, MeterStatus, NetMeter};
pub use parse::{Counter, Reading};
pub use pty::{NETTOP, NETTOP_ARGS, PtyLauncher};
pub use rates::{NetTracker, NetView, Rate};

/// Starts the program that reports traffic.
pub trait Launcher: Send + Sync + 'static {
    /// Starts one run. The error says what could not be started and why.
    fn launch(&self) -> anyhow::Result<Box<dyn Feed>>;
}

/// What one wait for output produced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Chunk {
    /// Some bytes of output, not necessarily whole lines.
    Data(Vec<u8>),
    /// Nothing arrived within the timeout.
    Idle,
    /// The program exited and has been reaped; how it exited, in words.
    Ended(String),
}

/// One running child.
pub trait Feed: Send {
    fn pid(&self) -> u32;
    /// Waits up to `timeout` for output.
    ///
    /// # Errors
    ///
    /// Returns the I/O error if the output cannot be read.
    fn read(&mut self, timeout: Duration) -> io::Result<Chunk>;
    /// Kills the child if it is still running and waits for it, so it is
    /// neither left running nor left a zombie. Calling it again does nothing.
    ///
    /// # Errors
    ///
    /// Returns the I/O error if the child could not be killed or waited for.
    fn stop(&mut self) -> io::Result<()>;
}

/// A launcher that always fails, for monitors built without network support.
#[derive(Debug, Default)]
pub struct NoLauncher;

impl Launcher for NoLauncher {
    fn launch(&self) -> anyhow::Result<Box<dyn Feed>> {
        anyhow::bail!("this daemon was built without per-process network measuring")
    }
}
