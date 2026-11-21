//! Keeps one `nettop` running on a thread of its own, restarts it with a
//! growing delay when it fails, and holds its newest reading.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::Context;

use super::parse::{Assembler, LineBuffer, Reading};
use super::{Chunk, Feed, Launcher};

/// Numbers runs across every meter, so a reading never matches one from an
/// earlier run, whichever meter took it.
static RUNS: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy)]
pub struct MeterConfig {
    /// The wait before the first restart; it doubles up to `retry_max`.
    pub retry_first: Duration,
    pub retry_max: Duration,
    /// A reading older than this is reported as a problem.
    pub stale_after: Duration,
    /// How often the thread checks whether it should stop.
    pub poll: Duration,
}

impl Default for MeterConfig {
    fn default() -> Self {
        Self {
            retry_first: Duration::from_secs(5),
            retry_max: Duration::from_secs(60),
            stale_after: Duration::from_secs(5),
            poll: Duration::from_millis(100),
        }
    }
}

/// The newest reading and what is wrong, if anything.
#[derive(Debug, Clone, Default)]
pub struct MeterStatus {
    pub latest: Option<Arc<Reading>>,
    /// Why the numbers cannot be trusted, in words a person can act on.
    pub problem: Option<String>,
}

#[derive(Debug, Default)]
struct State {
    status: MeterStatus,
    child: Option<u32>,
    stopping: bool,
}

#[derive(Debug, Default)]
struct Inner {
    state: Mutex<State>,
    wake: Condvar,
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|poisoned| {
            tracing::error!("the network meter lock was poisoned by a panic; using it anyway");
            poisoned.into_inner()
        })
    }

    fn stopping(&self) -> bool {
        self.lock().stopping
    }

    /// Sleeps for `delay` unless asked to stop first. True if stopping.
    fn wait_or_stop(&self, delay: Duration) -> bool {
        let deadline = Instant::now() + delay;
        let mut st = self.lock();
        while !st.stopping {
            let Some(left) = deadline.checked_duration_since(Instant::now()) else {
                return false;
            };
            st = match self.wake.wait_timeout(st, left) {
                Ok((guard, _)) => guard,
                Err(poisoned) => poisoned.into_inner().0,
            };
        }
        true
    }
}

/// A running meter. Dropping it stops the child, waits for it to exit and
/// joins the thread, so nothing is left behind.
pub struct NetMeter {
    inner: Arc<Inner>,
    thread: Option<JoinHandle<()>>,
    config: MeterConfig,
}

impl std::fmt::Debug for NetMeter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NetMeter")
            .field("child", &self.child_pid())
            .finish_non_exhaustive()
    }
}

impl NetMeter {
    /// Starts the thread, which starts the child.
    ///
    /// # Errors
    ///
    /// Returns an error if the thread cannot be started.
    pub fn start(launcher: Arc<dyn Launcher>, config: MeterConfig) -> anyhow::Result<Self> {
        let inner = Arc::new(Inner::default());
        let thread_inner = Arc::clone(&inner);
        let thread = thread::Builder::new()
            .name("computad-nettop".to_owned())
            .spawn(move || supervise(&thread_inner, launcher.as_ref(), config))
            .context("could not start the network measuring thread")?;
        Ok(Self {
            inner,
            thread: Some(thread),
            config,
        })
    }

    /// The newest reading, with a problem if it is older than it should be.
    pub fn status(&self, now: Instant) -> MeterStatus {
        let mut status = self.inner.lock().status.clone();
        if status.problem.is_none()
            && let Some(latest) = &status.latest
        {
            let age = now.saturating_duration_since(latest.at);
            if age > self.config.stale_after {
                status.problem = Some(format!(
                    "nettop has not reported for {} seconds",
                    age.as_secs()
                ));
            }
        }
        status
    }

    /// The running child's pid, if one is running.
    pub fn child_pid(&self) -> Option<u32> {
        self.inner.lock().child
    }
}

impl Drop for NetMeter {
    fn drop(&mut self) {
        self.inner.lock().stopping = true;
        self.inner.wake.notify_all();
        if let Some(thread) = self.thread.take()
            && thread.join().is_err()
        {
            tracing::error!("the network measuring thread panicked");
        }
    }
}

/// Runs the child until asked to stop, restarting it after failures.
fn supervise(inner: &Inner, launcher: &dyn Launcher, config: MeterConfig) {
    let mut delay = config.retry_first;
    while !inner.stopping() {
        let started = Instant::now();
        let run = RUNS.fetch_add(1, Ordering::Relaxed) + 1;
        let failure = match launcher.launch() {
            Ok(feed) => match watch(inner, feed, run, config) {
                None => break,
                Some(failure) => failure,
            },
            Err(error) => format!("{error:#}"),
        };
        if started.elapsed() > config.retry_max {
            delay = config.retry_first;
        }
        let problem = format!("{failure}; trying again in {} s", delay.as_secs());
        tracing::error!(problem, "per-process network traffic is unavailable");
        {
            let mut st = inner.lock();
            st.status = MeterStatus {
                latest: None,
                problem: Some(problem),
            };
            st.child = None;
        }
        if inner.wait_or_stop(delay) {
            break;
        }
        delay = (delay * 2).min(config.retry_max);
    }
    inner.lock().child = None;
    tracing::debug!("network measuring thread exited");
}

/// Reads one run. `None` when asked to stop; otherwise why the run ended.
/// The child is stopped and reaped either way.
fn watch(inner: &Inner, mut feed: Box<dyn Feed>, run: u64, config: MeterConfig) -> Option<String> {
    inner.lock().child = Some(feed.pid());
    let mut lines = LineBuffer::default();
    let mut samples = Assembler::new(run);
    let mut last_odd: Option<String> = None;
    let outcome = loop {
        if inner.stopping() {
            break None;
        }
        let chunk = match feed.read(config.poll) {
            Ok(chunk) => chunk,
            Err(error) => break Some(format!("could not read nettop's output: {error}")),
        };
        let bytes = match chunk {
            Chunk::Data(bytes) => bytes,
            Chunk::Idle => continue,
            Chunk::Ended(how) => break Some(ended_message(&how, last_odd.as_deref())),
        };
        let now = Instant::now();
        for line in lines.push(&bytes) {
            match samples.line(&line, now) {
                Ok(Some(reading)) => publish(inner, reading),
                Ok(None) => {}
                Err(odd) => {
                    tracing::warn!(line = odd, "nettop printed a line the daemon cannot read");
                    inner.lock().status.problem = Some(format!(
                        "nettop printed something unexpected: \u{201c}{odd}\u{201d}"
                    ));
                    last_odd = Some(odd);
                }
            }
        }
    };
    if let Err(error) = feed.stop() {
        tracing::error!(%error, pid = feed.pid(), "could not stop nettop");
    }
    outcome
}

fn publish(inner: &Inner, reading: Reading) {
    let mut st = inner.lock();
    st.status = MeterStatus {
        latest: Some(Arc::new(reading)),
        problem: None,
    };
}

fn ended_message(how: &str, last_odd: Option<&str>) -> String {
    match last_odd {
        Some(said) => format!("nettop exited ({how}) after printing \u{201c}{said}\u{201d}"),
        None => format!("nettop exited ({how})"),
    }
}

#[cfg(test)]
#[path = "meter_tests.rs"]
mod tests;
