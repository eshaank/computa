//! The task that keeps the pane map current while anyone is watching: one
//! long-running `rex events` stream, debounced refreshes of the sessions it
//! names, a full refresh every 30 seconds, and a retry every 5 seconds while
//! Rex cannot be reached.

use std::sync::Arc;
use std::time::Duration;

use tokio::sync::{oneshot, watch};
use tokio::time::{Instant, sleep_until};

use super::debounce::Debouncer;
use super::map::PaneMap;
use crate::pb::RexStatus;
use crate::rex::events::{Trigger, classify};
use crate::rex::{EventLines, RexClient, RexError};

pub const FULL_REFRESH_EVERY: Duration = Duration::from_secs(30);
pub const RETRY_EVERY: Duration = Duration::from_secs(5);
/// The first delay before restarting `rex events` after it exits. It doubles,
/// up to the maximum, while the stream keeps dying young.
const EVENTS_RESTART_MIN: Duration = Duration::from_secs(1);
const EVENTS_RESTART_MAX: Duration = Duration::from_secs(30);
const EVENTS_HEALTHY_AFTER: Duration = Duration::from_secs(10);

/// What the tracker publishes: the map and whether Rex could be reached.
#[derive(Debug, Clone, Default)]
pub struct View {
    /// Bumped on every change.
    pub seq: u64,
    pub status: RexStatus,
    pub map: PaneMap,
}

/// `None` until the first attempt to reach Rex has finished.
pub type ViewTx = watch::Sender<Option<Arc<View>>>;

enum Wake {
    Line(Result<Option<String>, RexError>),
    RestartEvents,
    Debounce,
    FullRefresh,
    Retry,
}

struct Tracker {
    client: Arc<dyn RexClient>,
    tx: ViewTx,
    view: View,
    debounce: Debouncer,
    events: Option<Box<dyn EventLines>>,
    events_started: Instant,
    restart_delay: Duration,
    restart_at: Option<Instant>,
    full_at: Option<Instant>,
    retry_at: Option<Instant>,
}

/// Runs until `stop` resolves (its sender is dropped). Dropping the task's
/// state kills the `rex events` process.
pub async fn run(client: Arc<dyn RexClient>, tx: ViewTx, mut stop: oneshot::Receiver<()>) {
    let mut t = Tracker {
        client,
        tx,
        view: View::default(),
        debounce: Debouncer::default(),
        events: None,
        events_started: Instant::now(),
        restart_delay: EVENTS_RESTART_MIN,
        restart_at: None,
        full_at: None,
        retry_at: None,
    };
    tokio::select! {
        _ = &mut stop => return,
        () = t.connect() => {}
    }
    loop {
        let wake = tokio::select! {
            _ = &mut stop => break,
            line = next_line(&mut t.events) => Wake::Line(line),
            () = sleep_opt(t.restart_at) => Wake::RestartEvents,
            () = sleep_opt(t.debounce.deadline()) => Wake::Debounce,
            () = sleep_opt(t.full_at) => Wake::FullRefresh,
            () = sleep_opt(t.retry_at) => Wake::Retry,
        };
        tokio::select! {
            _ = &mut stop => break,
            () = t.handle(wake) => {}
        }
    }
    tracing::info!("Rex session tracking stopped: no subscribers");
}

async fn next_line(events: &mut Option<Box<dyn EventLines>>) -> Result<Option<String>, RexError> {
    match events {
        Some(e) => e.next_line().await,
        None => std::future::pending().await,
    }
}

async fn sleep_opt(at: Option<Instant>) {
    match at {
        Some(at) => sleep_until(at).await,
        None => std::future::pending().await,
    }
}

impl Tracker {
    async fn handle(&mut self, wake: Wake) {
        match wake {
            Wake::Line(Ok(Some(line))) => self.on_line(&line),
            Wake::Line(Ok(None)) => self.events_ended(None),
            Wake::Line(Err(e)) => self.events_ended(Some(e)),
            Wake::RestartEvents => {
                self.restart_at = None;
                if self.start_events().await {
                    // Events may have been missed while it was down.
                    self.full_refresh(false).await;
                }
            }
            Wake::Debounce => {
                if let Some(work) = self.debounce.take_due(Instant::now()) {
                    self.refresh(work).await;
                }
            }
            Wake::FullRefresh => self.full_refresh(true).await,
            Wake::Retry => {
                self.retry_at = None;
                self.connect().await;
            }
        }
    }

    /// Reads the version, starts the event stream, then reads everything.
    /// The stream starts first so nothing that happens during the read is
    /// missed.
    async fn connect(&mut self) {
        match self.client.version().await {
            Ok(version) => {
                self.view.status.version = version;
                self.start_events().await;
                if self.retry_at.is_none() {
                    self.full_refresh(false).await;
                }
            }
            Err(e) => self.unreachable(&e),
        }
    }

    async fn start_events(&mut self) -> bool {
        match self.client.events().await {
            Ok(events) => {
                self.events = Some(events);
                self.events_started = Instant::now();
                true
            }
            Err(e @ (RexError::ServerNotRunning { .. } | RexError::NotFound { .. })) => {
                self.unreachable(&e);
                false
            }
            Err(error) => {
                tracing::warn!(%error, "could not start the Rex event stream; using the 30 s refresh until it starts");
                self.schedule_events_restart();
                false
            }
        }
    }

    fn events_ended(&mut self, error: Option<RexError>) {
        match error {
            Some(error) => tracing::warn!(%error, "the Rex event stream failed"),
            None => tracing::warn!("the Rex event stream ended"),
        }
        self.events = None;
        if self.events_started.elapsed() >= EVENTS_HEALTHY_AFTER {
            self.restart_delay = EVENTS_RESTART_MIN;
        }
        self.schedule_events_restart();
    }

    fn schedule_events_restart(&mut self) {
        self.restart_at = Some(Instant::now() + self.restart_delay);
        self.restart_delay = (self.restart_delay * 2).min(EVENTS_RESTART_MAX);
    }

    fn on_line(&mut self, line: &str) {
        let now = Instant::now();
        let trigger = match classify(line) {
            Ok(t) => t,
            Err(error) => {
                let shown: String = line.chars().take(200).collect();
                tracing::warn!(%error, line = shown, "could not read a Rex event; ignoring it");
                return;
            }
        };
        match trigger {
            Trigger::Ignore => {}
            Trigger::Session(id) => self.debounce.session(id, now),
            Trigger::Pane { session, block } => self.debounce.pane(session, block, now),
            Trigger::PaneClosed { session, block } => {
                if self.view.map.remove_pane(&session, &block) {
                    self.publish();
                }
                self.debounce.session(session, now);
            }
            Trigger::SessionGone(id) => {
                self.debounce.forget_session(&id);
                if self.view.map.remove_session(&id) {
                    self.publish();
                }
            }
        }
    }
}

#[path = "tracker_refresh.rs"]
mod refresh;

#[cfg(test)]
#[path = "tracker_tests.rs"]
mod tests;
