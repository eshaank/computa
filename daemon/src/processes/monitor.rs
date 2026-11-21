//! Samples processes on a thread of its own, but only while someone is
//! subscribed. Subscribers share one sampler, which runs at the shortest
//! interval any of them asked for.

use std::collections::HashMap;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::Context;
use tokio::sync::watch;

use super::group;
use super::table::ProcessTable;
use crate::pb::ProcessSnapshot;
use crate::sampler::unix_ms_now;

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
    pub snapshot: ProcessSnapshot,
}

/// Takes one pass at the given time. A new one is made each time sampling
/// starts, so nothing from an earlier session leaks into the next.
pub type Pass = Box<dyn FnMut(Instant) -> ProcessTable + Send>;
pub type PassFactory = Arc<dyn Fn() -> Pass + Send + Sync>;
type Latest = Option<Arc<Frame>>;

#[derive(Debug, Default)]
struct State {
    intervals: HashMap<u64, Duration>,
    next_id: u64,
    /// Bumped whenever sampling starts or stops; a thread from an older
    /// generation exits and may not publish.
    generation: u64,
    running: bool,
}

impl State {
    fn interval(&self) -> Option<Duration> {
        self.intervals.values().min().copied()
    }
}

struct Shared {
    state: Mutex<State>,
    wake: Condvar,
    tx: watch::Sender<Latest>,
    factory: PassFactory,
    first_delay: Duration,
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
    /// Reads this machine's processes.
    pub fn darwin() -> Self {
        let factory: PassFactory = Arc::new(|| {
            let mut reader = super::reader::Reader::new(super::reader::Darwin);
            Box::new(move |now| reader.read(now))
        });
        Self::new(factory, FIRST_FRAME_DELAY)
    }

    pub fn new(factory: PassFactory, first_delay: Duration) -> Self {
        let (tx, _) = watch::channel(None);
        Self {
            shared: Arc::new(Shared {
                state: Mutex::new(State::default()),
                wake: Condvar::new(),
                tx,
                factory,
                first_delay,
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
        let shared = &self.shared;
        let mut st = lock(&shared.state);
        let id = st.next_id;
        st.next_id += 1;
        if !st.running {
            let generation = st.generation + 1;
            let thread_shared = Arc::clone(shared);
            thread::Builder::new()
                .name("computad-processes".to_owned())
                .spawn(move || run(&thread_shared, generation))
                .context("could not start the process sampling thread")?;
            st.generation = generation;
            st.running = true;
            tracing::info!("process sampling started");
        }
        st.intervals.insert(id, interval);
        shared.wake.notify_all();
        Ok(Subscription {
            id,
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
}

/// A claim on the process sampler. Holds it running until dropped.
pub struct Subscription {
    id: u64,
    shared: Arc<Shared>,
    rx: watch::Receiver<Latest>,
}

impl std::fmt::Debug for Subscription {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Subscription")
            .field("id", &self.id)
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
fn lock(state: &Mutex<State>) -> MutexGuard<'_, State> {
    state.lock().unwrap_or_else(|poisoned| {
        tracing::error!("the process sampler lock was poisoned by a panic; using it anyway");
        poisoned.into_inner()
    })
}

/// Takes a priming pass, then one pass per interval until this generation
/// ends. If a pass runs late, the schedule restarts from it.
fn run(shared: &Shared, generation: u64) {
    let mut pass = (shared.factory)();
    let mut last = Instant::now();
    pass(last);
    let mut first = true;
    let mut seq = 0;
    while wait_for_turn(shared, generation, last, first) {
        let now = Instant::now();
        let table = Arc::new(pass(now));
        let snapshot = group::snapshot(&table, unix_ms_now());
        seq += 1;
        let frame = Arc::new(Frame {
            seq,
            at: now,
            table,
            snapshot,
        });
        let st = lock(&shared.state);
        if st.generation != generation {
            break;
        }
        shared.tx.send_replace(Some(frame));
        drop(st);
        (last, first) = (now, false);
    }
    tracing::debug!(generation, "process sampling thread exited");
}

/// Sleeps until the next pass is due. Returns false if this generation has
/// ended. Wakes early when subscribers come or go, so a shorter interval
/// takes effect at once.
fn wait_for_turn(shared: &Shared, generation: u64, last: Instant, first: bool) -> bool {
    let mut st = lock(&shared.state);
    loop {
        if st.generation != generation {
            return false;
        }
        let step = match st.interval() {
            Some(interval) if !first => interval,
            _ => shared.first_delay,
        };
        let now = Instant::now();
        let Some(wait) = (last + step)
            .checked_duration_since(now)
            .filter(|w| !w.is_zero())
        else {
            return true;
        };
        st = shared
            .wake
            .wait_timeout(st, wait)
            .map(|(guard, _)| guard)
            .unwrap_or_else(|poisoned| {
                tracing::error!(
                    "the process sampler lock was poisoned by a panic; using it anyway"
                );
                poisoned.into_inner().0
            });
    }
}

#[cfg(test)]
#[path = "monitor_tests.rs"]
mod tests;
