//! Runs the network meter only while at least one subscriber asked for
//! network traffic: the first one starts it, the last one to leave stops it.

use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Instant;

use crate::nettop::{Launcher, MeterConfig, MeterStatus, NetMeter};

#[derive(Debug, Default)]
struct SlotState {
    users: usize,
    meter: Option<NetMeter>,
    /// Why the meter could not be started, while there are users.
    start_error: Option<String>,
    /// Set on daemon shutdown: no meter starts again.
    closed: bool,
}

pub struct NetworkSlot {
    launcher: Arc<dyn Launcher>,
    config: MeterConfig,
    state: Mutex<SlotState>,
}

impl std::fmt::Debug for NetworkSlot {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NetworkSlot")
            .field("state", &*self.lock())
            .finish_non_exhaustive()
    }
}

impl NetworkSlot {
    pub fn new(launcher: Arc<dyn Launcher>, config: MeterConfig) -> Self {
        Self {
            launcher,
            config,
            state: Mutex::new(SlotState::default()),
        }
    }

    fn lock(&self) -> MutexGuard<'_, SlotState> {
        self.state.lock().unwrap_or_else(|poisoned| {
            tracing::error!("the network slot lock was poisoned by a panic; using it anyway");
            poisoned.into_inner()
        })
    }

    /// One more subscriber wants network traffic.
    pub fn acquire(&self) {
        let mut st = self.lock();
        st.users += 1;
        if st.users > 1 || st.closed {
            return;
        }
        match NetMeter::start(Arc::clone(&self.launcher), self.config) {
            Ok(meter) => {
                tracing::info!("per-process network measuring started");
                st.meter = Some(meter);
                st.start_error = None;
            }
            Err(error) => {
                let message = format!("{error:#}");
                tracing::error!(
                    error = message,
                    "could not start per-process network measuring"
                );
                st.start_error = Some(message);
            }
        }
    }

    /// One subscriber that wanted network traffic left. The last one stops
    /// the meter, which kills and reaps its child before this returns.
    pub fn release(&self) {
        let meter = {
            let mut st = self.lock();
            st.users = st.users.saturating_sub(1);
            if st.users > 0 {
                return;
            }
            st.start_error = None;
            st.meter.take()
        };
        if let Some(meter) = meter {
            drop(meter);
            tracing::info!("per-process network measuring stopped: nobody is asking");
        }
    }

    /// Stops the meter for good, whoever is still subscribed.
    pub fn shutdown(&self) {
        let meter = {
            let mut st = self.lock();
            st.closed = true;
            st.meter.take()
        };
        if let Some(meter) = meter {
            drop(meter);
            tracing::info!("per-process network measuring stopped for shutdown");
        }
    }

    /// `None` while nobody asked for network traffic.
    pub fn status(&self, now: Instant) -> Option<MeterStatus> {
        let st = self.lock();
        if st.users == 0 {
            return None;
        }
        if let Some(meter) = &st.meter {
            return Some(meter.status(now));
        }
        let problem = st
            .start_error
            .clone()
            .unwrap_or_else(|| "the daemon is shutting down".to_owned());
        Some(MeterStatus {
            latest: None,
            problem: Some(problem),
        })
    }

    pub fn child_pid(&self) -> Option<u32> {
        self.lock().meter.as_ref().and_then(NetMeter::child_pid)
    }

    pub fn is_running(&self) -> bool {
        self.lock().meter.is_some()
    }
}

#[cfg(test)]
#[path = "network_tests.rs"]
mod tests;
