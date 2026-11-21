//! A scripted [`Launcher`] for tests.

use std::collections::VecDeque;
use std::io;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use super::{Chunk, Feed, Launcher};

/// What the next launch does.
#[derive(Debug, Clone)]
pub enum Script {
    Fail(String),
    /// Starts, returns these chunks in order, then stays quiet until stopped.
    Run(Vec<Chunk>),
    /// Like `Run`, one chunk per this long.
    Paced(Vec<Chunk>, Duration),
}

/// Counts launches and children that are still alive.
#[derive(Debug, Default)]
pub struct FakeLauncher {
    pub launches: AtomicUsize,
    pub live: Arc<AtomicUsize>,
    /// Used in order; when empty, a launch starts a quiet child.
    pub scripts: Mutex<VecDeque<Script>>,
}

impl FakeLauncher {
    pub fn new(scripts: Vec<Script>) -> Arc<Self> {
        Arc::new(Self {
            scripts: Mutex::new(scripts.into()),
            ..Self::default()
        })
    }

    pub fn launches(&self) -> usize {
        self.launches.load(Ordering::SeqCst)
    }

    pub fn live(&self) -> usize {
        self.live.load(Ordering::SeqCst)
    }
}

impl FakeLauncher {
    fn feed(&self, n: usize, chunks: Vec<Chunk>, gap: Duration) -> Box<dyn Feed> {
        self.live.fetch_add(1, Ordering::SeqCst);
        Box::new(FakeFeed {
            pid: 1000 + u32::try_from(n).expect("few launches"),
            chunks: chunks.into(),
            gap,
            next_at: Instant::now(),
            live: Some(Arc::clone(&self.live)),
        })
    }
}

impl Launcher for FakeLauncher {
    fn launch(&self) -> anyhow::Result<Box<dyn Feed>> {
        let n = self.launches.fetch_add(1, Ordering::SeqCst);
        let script = self
            .scripts
            .lock()
            .expect("fake lock")
            .pop_front()
            .unwrap_or(Script::Run(Vec::new()));
        match script {
            Script::Fail(why) => anyhow::bail!(why),
            Script::Run(chunks) => Ok(self.feed(n, chunks, Duration::ZERO)),
            Script::Paced(chunks, gap) => Ok(self.feed(n, chunks, gap)),
        }
    }
}

struct FakeFeed {
    pid: u32,
    chunks: VecDeque<Chunk>,
    gap: Duration,
    next_at: Instant,
    /// `Some` until stopped.
    live: Option<Arc<AtomicUsize>>,
}

impl Feed for FakeFeed {
    fn pid(&self) -> u32 {
        self.pid
    }

    fn read(&mut self, timeout: Duration) -> io::Result<Chunk> {
        if Instant::now() >= self.next_at
            && let Some(chunk) = self.chunks.pop_front()
        {
            self.next_at = Instant::now() + self.gap;
            if matches!(chunk, Chunk::Ended(_)) {
                self.stop()?;
            }
            return Ok(chunk);
        }
        std::thread::sleep(timeout.min(Duration::from_millis(10)));
        Ok(Chunk::Idle)
    }

    fn stop(&mut self) -> io::Result<()> {
        if let Some(live) = self.live.take() {
            live.fetch_sub(1, Ordering::SeqCst);
        }
        Ok(())
    }
}

impl Drop for FakeFeed {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

/// Output text as a chunk.
pub fn data(text: &str) -> Chunk {
    Chunk::Data(text.as_bytes().to_vec())
}
