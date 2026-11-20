//! The background sampler: reads system metrics once per sample interval,
//! keeps them in a history ring, and publishes the newest to subscribers.

mod battery;
mod collector;
mod cpu;
mod disk;
mod ffi;
mod host;
mod iokit;
mod log_once;
mod memory;
mod netif;
mod network;
mod rate;
mod sysctl;
mod topology;
mod volumes;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::Context;
use tokio::sync::watch;

use crate::history::{HistoryRing, downsample};
use crate::pb::{History, Host, SystemSample};
use collector::{Collector, history_point, unix_ms_now};

/// How often the daemon takes a sample.
pub const SAMPLE_INTERVAL_MS: u32 = 1000;
const SAMPLE_INTERVAL: Duration = Duration::from_millis(SAMPLE_INTERVAL_MS as u64);
/// How many samples history keeps: one hour at one per second.
pub const HISTORY_CAPACITY: u32 = 3600;

/// A sample with its sequence number. The first sample is number 0 and each
/// later one is one more, so subscribers can tell how many have passed.
#[derive(Debug)]
pub struct Published {
    pub seq: u64,
    pub sample: SystemSample,
}

/// A handle to the running sampler. Dropping it stops the sampling thread.
#[derive(Debug)]
pub struct Sampler {
    host: Host,
    latest: watch::Receiver<Arc<Published>>,
    history: Arc<Mutex<HistoryRing>>,
    stop: Arc<AtomicBool>,
}

impl Sampler {
    /// Reads the host facts, takes the first sample, and starts sampling on
    /// a thread of its own so system calls never block the async runtime.
    ///
    /// # Errors
    ///
    /// Returns an error if the sampling thread cannot be started.
    pub fn start() -> anyhow::Result<Self> {
        let facts = host::read(SAMPLE_INTERVAL_MS, HISTORY_CAPACITY);
        let mut collector = Collector::new(&facts);
        let first = collector.sample();
        let mut ring = HistoryRing::new(HISTORY_CAPACITY as usize);
        ring.push(history_point(&first));
        let history = Arc::new(Mutex::new(ring));
        let (tx, latest) = watch::channel(Arc::new(Published {
            seq: 0,
            sample: first,
        }));
        let stop = Arc::new(AtomicBool::new(false));
        let (thread_history, thread_stop) = (Arc::clone(&history), Arc::clone(&stop));
        thread::Builder::new()
            .name("computad-sampler".to_owned())
            .spawn(move || run(collector, &tx, &thread_history, &thread_stop))
            .context("could not start the sampling thread")?;
        Ok(Self {
            host: facts.host,
            latest,
            history,
            stop,
        })
    }

    pub fn host(&self) -> &Host {
        &self.host
    }

    /// A receiver that always holds the newest sample.
    pub fn subscribe(&self) -> watch::Receiver<Arc<Published>> {
        self.latest.clone()
    }

    /// Stored samples for `GetHistory`, oldest first.
    pub fn history(&self, window_seconds: u32, max_points: u32) -> History {
        let points = lock(&self.history).window(unix_ms_now(), u64::from(window_seconds) * 1000);
        let out = downsample(&points, max_points as usize, SAMPLE_INTERVAL_MS);
        History {
            points: out.points,
            step_ms: out.step_ms,
        }
    }
}

impl Drop for Sampler {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// Locks the ring. The ring is valid after any panic, so a poisoned lock is
/// logged and used rather than passed on.
fn lock(history: &Mutex<HistoryRing>) -> MutexGuard<'_, HistoryRing> {
    history.lock().unwrap_or_else(|poisoned| {
        tracing::error!("the history lock was poisoned by a panic; using it anyway");
        poisoned.into_inner()
    })
}

/// Samples on a fixed schedule until `stop` is set. If ticks are missed (for
/// example while the machine is busy), the schedule restarts from now
/// instead of catching up with a burst of samples.
fn run(
    mut collector: Collector,
    tx: &watch::Sender<Arc<Published>>,
    history: &Mutex<HistoryRing>,
    stop: &AtomicBool,
) {
    let mut next = Instant::now() + SAMPLE_INTERVAL;
    let mut seq = 0;
    while !stop.load(Ordering::Relaxed) {
        if let Some(wait) = next.checked_duration_since(Instant::now()) {
            thread::sleep(wait);
        }
        let sample = collector.sample();
        lock(history).push(history_point(&sample));
        seq += 1;
        tx.send_replace(Arc::new(Published { seq, sample }));
        next += SAMPLE_INTERVAL;
        let now = Instant::now();
        if next <= now {
            next = now + SAMPLE_INTERVAL;
        }
    }
    tracing::debug!("sampling thread stopped");
}
