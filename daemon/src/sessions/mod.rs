//! Rex sessions, tabs and panes, with the CPU and memory of the processes
//! running in each pane.
//!
//! The pane map comes from Rex (on events and a slow timer); usage comes
//! from the process sampler's frames. Combining them is a pure function,
//! [`snapshot::build`].

pub mod debounce;
pub mod map;
mod monitor;
pub mod snapshot;
mod tracker;

pub use monitor::{SessionMonitor, SessionSubscription};
pub use tracker::{FULL_REFRESH_EVERY, RETRY_EVERY, View};
