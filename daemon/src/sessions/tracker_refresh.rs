//! Reading the map from Rex, and saying when Rex cannot be reached.

use std::sync::Arc;

use tokio::task::JoinSet;
use tokio::time::Instant;

use super::{EVENTS_RESTART_MIN, FULL_REFRESH_EVERY, RETRY_EVERY, Tracker};
use crate::pb::RexStatus;
use crate::rex::RexError;
use crate::sessions::debounce::{Debouncer, Work};
use crate::sessions::map::{self, PaneMap};

impl Tracker {
    /// Reads every session. With `reuse`, panes already known keep their
    /// process info (only the 30 s safety refresh does this; after a gap in
    /// the event stream everything is read again).
    pub(super) async fn full_refresh(&mut self, reuse: bool) {
        let known = if reuse {
            self.view.map.known_processes()
        } else {
            map::Known::new()
        };
        match map::fetch_all(&self.client, known).await {
            Ok(fresh) => {
                let was_unreachable = !self.view.status.reachable;
                self.view.status.reachable = true;
                self.view.status.problem.clear();
                self.full_at = Some(Instant::now() + FULL_REFRESH_EVERY);
                if was_unreachable {
                    tracing::info!(
                        sessions = fresh.sessions.len(),
                        panes = fresh.pane_count(),
                        "Rex is reachable"
                    );
                }
                if was_unreachable || fresh != self.view.map {
                    self.view.map = fresh;
                    self.publish();
                }
            }
            Err(e) => self.unreachable(&e),
        }
    }

    /// Re-reads the sessions and panes a burst of events named.
    pub(super) async fn refresh(&mut self, work: Work) {
        let mut sessions = work.sessions;
        let mut tasks = JoinSet::new();
        for (session, block) in work.panes {
            if self.view.map.pane_mut(&session, &block).is_none() {
                // A pane the map has not seen yet: its layout is new too.
                sessions.insert(session);
                continue;
            }
            let client = Arc::clone(&self.client);
            tasks.spawn(async move {
                let p = map::fetch_pane(client.as_ref(), &session, &block).await;
                (session, block, p)
            });
        }
        let mut changed = self.refresh_sessions(sessions).await;
        for (session, block, process) in tasks.join_all().await {
            let (Some(pane), Some(process)) = (self.view.map.pane_mut(&session, &block), process)
            else {
                continue;
            };
            if pane.process.as_ref() != Some(&process) {
                pane.process = Some(process);
                changed = true;
            }
        }
        if changed {
            self.publish();
        }
    }

    /// Returns whether the map changed. Rex becoming unreachable is
    /// published by `unreachable` itself.
    async fn refresh_sessions(&mut self, ids: impl IntoIterator<Item = String>) -> bool {
        let mut tasks = JoinSet::new();
        for id in ids {
            let client = Arc::clone(&self.client);
            tasks.spawn(async move {
                let r = map::fetch_session(&client, &id, &map::Known::new()).await;
                (id, r)
            });
        }
        let before = self.view.map.clone();
        for (id, result) in tasks.join_all().await {
            match result {
                Ok(info) => self.view.map.upsert(info),
                Err(RexError::TargetGone { .. }) => {
                    self.view.map.remove_session(&id);
                }
                Err(e @ (RexError::ServerNotRunning { .. } | RexError::NotFound { .. })) => {
                    self.unreachable(&e);
                    return false;
                }
                Err(error) => {
                    tracing::warn!(%error, session = id, "could not refresh a session; keeping what was known");
                }
            }
        }
        self.view.map != before
    }

    /// Drops the map and the event stream, says why, and retries later.
    pub(super) fn unreachable(&mut self, error: &RexError) {
        let problem = error.problem();
        if self.view.status.problem != problem || self.view.seq == 0 {
            tracing::warn!(%error, "Rex cannot be reached; retrying every {} s", RETRY_EVERY.as_secs());
        } else {
            tracing::debug!(%error, "Rex still cannot be reached");
        }
        let status = RexStatus {
            reachable: false,
            problem,
            version: String::new(),
        };
        let changed =
            self.view.seq == 0 || self.view.status != status || !self.view.map.sessions.is_empty();
        self.view.status = status;
        self.view.map = PaneMap::default();
        self.events = None;
        self.debounce = Debouncer::default();
        self.restart_at = None;
        self.restart_delay = EVENTS_RESTART_MIN;
        self.full_at = None;
        self.retry_at = Some(Instant::now() + RETRY_EVERY);
        if changed {
            self.publish();
        }
    }

    pub(super) fn publish(&mut self) {
        self.view.seq += 1;
        self.tx.send_replace(Some(Arc::new(self.view.clone())));
    }
}
