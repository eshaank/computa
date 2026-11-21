//! Per-process CPU and memory, grouped by app, sampled only while a client
//! is watching.
//!
//! The daemon runs as the user, so it can list every process (with its
//! parent, owner and path) but read usage only for the user's own.

mod cpu;
mod darwin;
pub mod group;
mod kinfo;
mod monitor;
mod reader;
mod table;

pub use monitor::{FIRST_FRAME_DELAY, Frame, Pass, PassFactory, ProcessMonitor, Subscription};
pub use table::{ProcessEntry, ProcessTable, SubtreeUsage, Usage};
