//! Starts session tracking for the first subscriber and stops it after the
//! last. Each subscriber also holds a process-sampler subscription, so
//! processes are read only while someone watches.

use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use tokio::sync::{oneshot, watch};

use super::tracker::{self, View};
use crate::processes::{ProcessMonitor, Subscription};
use crate::rex::RexClient;

type ViewRx = watch::Receiver<Option<Arc<View>>>;

struct Run {
    /// Dropping it stops the tracker task.
    _stop: oneshot::Sender<()>,
    views: ViewRx,
}

#[derive(Default)]
struct State {
    subscribers: usize,
    run: Option<Run>,
}

struct Shared {
    client: Arc<dyn RexClient>,
    processes: ProcessMonitor,
    state: Mutex<State>,
}

/// Rex session tracking. Cheap to clone; clones share one tracker.
#[derive(Clone)]
pub struct SessionMonitor {
    shared: Arc<Shared>,
}

impl std::fmt::Debug for SessionMonitor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionMonitor")
            .field("subscribers", &lock(&self.shared.state).subscribers)
            .finish_non_exhaustive()
    }
}

impl SessionMonitor {
    pub fn new(client: Arc<dyn RexClient>, processes: ProcessMonitor) -> Self {
        Self {
            shared: Arc::new(Shared {
                client,
                processes,
                state: Mutex::new(State::default()),
            }),
        }
    }

    /// Subscribes, starting tracking and process sampling if nobody else is
    /// subscribed. Must be called inside a tokio runtime.
    ///
    /// # Errors
    ///
    /// Returns an error if process sampling cannot be started.
    pub fn subscribe(&self, interval: Duration) -> anyhow::Result<SessionSubscription> {
        let processes = self.shared.processes.subscribe(interval)?;
        let mut st = lock(&self.shared.state);
        let views = match &st.run {
            Some(run) => run.views.clone(),
            None => {
                let (tx, views) = watch::channel(None);
                let (stop, stop_rx) = oneshot::channel();
                tokio::spawn(tracker::run(Arc::clone(&self.shared.client), tx, stop_rx));
                tracing::info!("Rex session tracking started");
                st.run = Some(Run {
                    _stop: stop,
                    views: views.clone(),
                });
                views
            }
        };
        st.subscribers += 1;
        Ok(SessionSubscription {
            shared: Arc::clone(&self.shared),
            processes,
            views,
        })
    }

    /// Whether the tracker task has been asked to run.
    pub fn is_tracking(&self) -> bool {
        lock(&self.shared.state).run.is_some()
    }
}

/// A claim on session tracking and on the process sampler. Dropping the
/// last one stops both.
pub struct SessionSubscription {
    shared: Arc<Shared>,
    processes: Subscription,
    views: ViewRx,
}

impl std::fmt::Debug for SessionSubscription {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionSubscription")
            .field("processes", &self.processes)
            .finish_non_exhaustive()
    }
}

impl SessionSubscription {
    /// The newest pane map and Rex status, `None` until Rex was first asked.
    pub fn views(&self) -> ViewRx {
        self.views.clone()
    }

    pub fn processes(&self) -> &Subscription {
        &self.processes
    }
}

impl Drop for SessionSubscription {
    fn drop(&mut self) {
        let mut st = lock(&self.shared.state);
        st.subscribers = st.subscribers.saturating_sub(1);
        if st.subscribers == 0 && st.run.take().is_some() {
            tracing::info!("stopping Rex session tracking: no subscribers");
        }
    }
}

/// The state is valid after any panic, so a poisoned lock is logged and used.
fn lock(state: &Mutex<State>) -> MutexGuard<'_, State> {
    state.lock().unwrap_or_else(|poisoned| {
        tracing::error!("the session monitor lock was poisoned by a panic; using it anyway");
        poisoned.into_inner()
    })
}
