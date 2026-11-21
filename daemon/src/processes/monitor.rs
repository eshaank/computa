//! Samples processes on a thread of its own, but only while someone is
//! subscribed. Subscribers share one sampler, which runs at the shortest
//! interval any of them asked for. Network traffic is measured only while
//! at least one subscriber asked for it.

use std::collections::HashMap;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::Context;
use tokio::sync::watch;

use super::network::NetworkSlot;
use super::sampling;
use super::table::ProcessTable;
use crate::nettop::{Launcher, MeterConfig, NoLauncher, PtyLauncher};
use crate::pb::ProcessSnapshot;

/// How long after the first subscriber arrives the first frame is ready: CPU
/// percent needs two readings this far apart.
pub const FIRST_FRAME_DELAY: Duration = Duration::from_secs(1);

/// One pass over every process, and the message built from it.
#[derive(Debug)]
pub struct Frame {
    /// Counts frames since the sampler last started, from 1.
    pub seq: u64,
    /// When the pass began.
    pub at: Instant,
    pub table: Arc<ProcessTable>,
    /// Without network traffic, for subscribers that did not ask for it.
    pub snapshot: ProcessSnapshot,
    /// With network traffic; `None` while nobody asked for it.
    pub networked: Option<ProcessSnapshot>,
}

/// Takes one pass at the given time. A new one is made each time sampling
/// starts, so nothing from an earlier session leaks into the next.
pub type Pass = Box<dyn FnMut(Instant) -> ProcessTable + Send>;
pub type PassFactory = Arc<dyn Fn() -> Pass + Send + Sync>;
type Latest = Option<Arc<Frame>>;

#[derive(Debug, Default)]
pub(super) struct State {
    pub(super) intervals: HashMap<u64, Duration>,
    next_id: u64,
    /// Bumped whenever sampling starts or stops; a thread from an older
    /// generation exits and may not publish.
    pub(super) generation: u64,
    running: bool,
}

impl State {
    pub(super) fn interval(&self) -> Option<Duration> {
        self.intervals.values().min().copied()
    }
}

pub(super) struct Shared {
    pub(super) state: Mutex<State>,
    pub(super) wake: Condvar,
    pub(super) tx: watch::Sender<Latest>,
    pub(super) factory: PassFactory,
    pub(super) first_delay: Duration,
    pub(super) network: NetworkSlot,
}

/// The process sampler. Cheap to clone; clones share one sampler.
#[derive(Clone)]
pub struct ProcessMonitor {
    shared: Arc<Shared>,
}

impl std::fmt::Debug for ProcessMonitor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProcessMonitor")
            .field("subscribers", &self.subscriber_count())
            .finish_non_exhaustive()
    }
}

impl ProcessMonitor {
    /// Reads this machine's processes, and their traffic from `nettop`.
    pub fn darwin() -> Self {
        let factory: PassFactory = Arc::new(|| {
            let mut reader = super::reader::Reader::new(super::reader::Darwin);
            Box::new(move |now| reader.read(now))
        });
        let nettop = Arc::new(PtyLauncher::nettop());
        Self::with_network(factory, FIRST_FRAME_DELAY, nettop, MeterConfig::default())
    }

    /// A monitor that cannot measure network traffic.
    pub fn new(factory: PassFactory, first_delay: Duration) -> Self {
        Self::with_network(
            factory,
            first_delay,
            Arc::new(NoLauncher),
            MeterConfig::default(),
        )
    }

    pub fn with_network(
        factory: PassFactory,
        first_delay: Duration,
        launcher: Arc<dyn Launcher>,
        config: MeterConfig,
    ) -> Self {
        let (tx, _) = watch::channel(None);
        Self {
            shared: Arc::new(Shared {
                state: Mutex::new(State::default()),
                wake: Condvar::new(),
                tx,
                factory,
                first_delay,
                network: NetworkSlot::new(launcher, config),
            }),
        }
    }

    /// Starts sampling if nobody else is subscribed. Frames arrive at most
    /// `interval` apart (sooner if another subscriber asked for less).
    /// Dropping the subscription unsubscribes.
    ///
    /// # Errors
    ///
    /// Returns an error if the sampling thread cannot be started.
    pub fn subscribe(&self, interval: Duration) -> anyhow::Result<Subscription> {
        self.subscribe_with(interval, false)
    }

    /// Like [`Self::subscribe`]; with `network`, also measures network
    /// traffic until this subscription and every other one that asked for
    /// it are dropped.
    ///
    /// # Errors
    ///
    /// Returns an error if the sampling thread cannot be started.
    pub fn subscribe_with(
        &self,
        interval: Duration,
        network: bool,
    ) -> anyhow::Result<Subscription> {
        let mut subscription = self.subscribe_plain(interval)?;
        if network {
            self.shared.network.acquire();
            subscription.network = true;
        }
        Ok(subscription)
    }

    fn subscribe_plain(&self, interval: Duration) -> anyhow::Result<Subscription> {
        let shared = &self.shared;
        let mut st = lock(&shared.state);
        let id = st.next_id;
        st.next_id += 1;
        if !st.running {
            let generation = st.generation + 1;
            let thread_shared = Arc::clone(shared);
            thread::Builder::new()
                .name("computad-processes".to_owned())
                .spawn(move || sampling::run(&thread_shared, generation))
                .context("could not start the process sampling thread")?;
            st.generation = generation;
            st.running = true;
            tracing::info!("process sampling started");
        }
        st.intervals.insert(id, interval);
        shared.wake.notify_all();
        Ok(Subscription {
            id,
            network: false,
            shared: Arc::clone(shared),
            rx: shared.tx.subscribe(),
        })
    }

    pub fn subscriber_count(&self) -> usize {
        lock(&self.shared.state).intervals.len()
    }

    pub fn is_sampling(&self) -> bool {
        lock(&self.shared.state).running
    }

    /// Whether the network meter is running.
    pub fn is_measuring_network(&self) -> bool {
        self.shared.network.is_running()
    }

    /// The pid of the running `nettop`, if any.
    pub fn network_child_pid(&self) -> Option<u32> {
        self.shared.network.child_pid()
    }

    /// Stops network measuring for good and reaps its child, for daemon
    /// shutdown while streams may still be open.
    pub fn shutdown_network(&self) {
        self.shared.network.shutdown();
    }
}

/// A claim on the process sampler. Holds it running until dropped.
pub struct Subscription {
    id: u64,
    network: bool,
    shared: Arc<Shared>,
    rx: watch::Receiver<Latest>,
}

impl std::fmt::Debug for Subscription {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Subscription")
            .field("id", &self.id)
            .field("network", &self.network)
            .finish()
    }
}

impl Subscription {
    /// A receiver that holds the newest frame, or `None` until the first.
    pub fn receiver(&self) -> watch::Receiver<Latest> {
        self.rx.clone()
    }

    /// The newest frame, if one has been taken since sampling started.
    pub fn latest(&self) -> Latest {
        self.rx.borrow().clone()
    }
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.unsubscribe();
        if self.network {
            self.shared.network.release();
        }
    }
}

impl Subscription {
    fn unsubscribe(&self) {
        let mut st = lock(&self.shared.state);
        st.intervals.remove(&self.id);
        if st.intervals.is_empty() && st.running {
            st.running = false;
            st.generation += 1;
            // The next subscriber must not see a stale frame.
            self.shared.tx.send_replace(None);
            tracing::info!("process sampling stopped: no subscribers");
        }
        self.shared.wake.notify_all();
    }
}

/// The state is valid after any panic, so a poisoned lock is logged and used.
pub(super) fn lock(state: &Mutex<State>) -> MutexGuard<'_, State> {
    state.lock().unwrap_or_else(|poisoned| {
        tracing::error!("the process sampler lock was poisoned by a panic; using it anyway");
        poisoned.into_inner()
    })
}

#[cfg(test)]
#[path = "monitor_tests.rs"]
mod tests;
