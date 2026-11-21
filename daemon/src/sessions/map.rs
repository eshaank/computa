//! The pane map: Rex's sessions, tabs and terminal panes, with each pane's
//! processes as Rex reported them. It is read from Rex only on events and on
//! a slow timer, never once per snapshot.

use std::collections::HashMap;
use std::sync::Arc;

use tokio::task::JoinSet;

use crate::rex::{PaneProcess, RexClient, RexError};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PaneMap {
    /// In Rex's order.
    pub sessions: Vec<SessionInfo>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SessionInfo {
    pub id: String,
    pub label: String,
    pub windows: Vec<WindowInfo>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct WindowInfo {
    pub id: String,
    pub label: String,
    pub panes: Vec<PaneInfo>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PaneInfo {
    pub id: String,
    pub label: String,
    /// `None` when Rex could not say (the failure was logged).
    pub process: Option<PaneProcess>,
}

impl PaneMap {
    /// Replaces the session with the same id, or adds it at the end.
    pub fn upsert(&mut self, session: SessionInfo) {
        match self.sessions.iter_mut().find(|s| s.id == session.id) {
            Some(slot) => *slot = session,
            None => self.sessions.push(session),
        }
    }

    pub fn remove_session(&mut self, id: &str) -> bool {
        let before = self.sessions.len();
        self.sessions.retain(|s| s.id != id);
        self.sessions.len() != before
    }

    pub fn remove_pane(&mut self, session: &str, block: &str) -> bool {
        let Some(s) = self.sessions.iter_mut().find(|s| s.id == session) else {
            return false;
        };
        let mut removed = false;
        for w in &mut s.windows {
            let before = w.panes.len();
            w.panes.retain(|p| p.id != block);
            removed |= w.panes.len() != before;
        }
        removed
    }

    pub fn pane_mut(&mut self, session: &str, block: &str) -> Option<&mut PaneInfo> {
        self.sessions
            .iter_mut()
            .filter(|s| s.id == session)
            .flat_map(|s| s.windows.iter_mut())
            .flat_map(|w| w.panes.iter_mut())
            .find(|p| p.id == block)
    }

    pub fn pane_count(&self) -> usize {
        self.sessions
            .iter()
            .flat_map(|s| &s.windows)
            .map(|w| w.panes.len())
            .sum()
    }
}

/// Reads one pane's processes. A failure is logged and gives `None`.
pub async fn fetch_pane(client: &dyn RexClient, session: &str, block: &str) -> Option<PaneProcess> {
    match client.pane_process(session, block).await {
        Ok(p) => Some(p),
        Err(error) => {
            tracing::warn!(%error, session, block, "could not read a pane's processes");
            None
        }
    }
}

/// Process info already known for some panes, by block id. A pane's root
/// process never changes, and `process_changed` events keep its foreground
/// current, so the periodic refresh reuses this instead of asking again.
pub type Known = HashMap<String, PaneProcess>;

impl PaneMap {
    /// The process info of every pane that has some.
    pub fn known_processes(&self) -> Known {
        self.sessions
            .iter()
            .flat_map(|s| &s.windows)
            .flat_map(|w| &w.panes)
            .filter_map(|p| p.process.clone().map(|pr| (p.id.clone(), pr)))
            .collect()
    }
}

/// Reads one session's layout, then the processes of its panes (those not
/// in `known`) all at once.
///
/// # Errors
///
/// Returns the error from reading the layout.
pub async fn fetch_session(
    client: &Arc<dyn RexClient>,
    session_id: &str,
    known: &Known,
) -> Result<SessionInfo, RexError> {
    let view = client.view_session(session_id).await?;
    let mut tasks = JoinSet::new();
    let mut processes: HashMap<String, Option<PaneProcess>> = HashMap::new();
    for block in view.windows.iter().flat_map(|w| w.terminal_blocks()) {
        if let Some(p) = known.get(&block.block_id) {
            processes.insert(block.block_id.clone(), Some(p.clone()));
            continue;
        }
        let (client, sid, bid) = (
            Arc::clone(client),
            session_id.to_owned(),
            block.block_id.clone(),
        );
        tasks.spawn(async move {
            let p = fetch_pane(client.as_ref(), &sid, &bid).await;
            (bid, p)
        });
    }
    for (bid, p) in tasks.join_all().await {
        processes.insert(bid, p);
    }
    let windows = view
        .windows
        .iter()
        .map(|w| WindowInfo {
            id: w.window_id.clone(),
            label: w.label.clone(),
            panes: w
                .terminal_blocks()
                .map(|b| PaneInfo {
                    id: b.block_id.clone(),
                    label: b.label.clone(),
                    process: processes.remove(&b.block_id).flatten(),
                })
                .collect(),
        })
        .collect();
    Ok(SessionInfo {
        id: view.session_id,
        label: view.label,
        windows,
    })
}

/// Reads every session, reusing `known` process info. A session that vanished meanwhile is left out; any
/// other failure to read one is logged and it is left out too.
///
/// # Errors
///
/// Returns the error if the list of sessions cannot be read, or if the
/// server stopped answering partway.
pub async fn fetch_all(client: &Arc<dyn RexClient>, known: Known) -> Result<PaneMap, RexError> {
    let list = client.list_sessions().await?;
    let known = Arc::new(known);
    let mut tasks = JoinSet::new();
    for s in &list {
        let (client, id, known) = (Arc::clone(client), s.session_id.clone(), Arc::clone(&known));
        tasks.spawn(async move {
            let r = fetch_session(&client, &id, &known).await;
            (id, r)
        });
    }
    let mut found: HashMap<String, SessionInfo> = HashMap::new();
    for (id, result) in tasks.join_all().await {
        match result {
            Ok(info) => {
                found.insert(id, info);
            }
            Err(RexError::TargetGone { .. }) => {
                tracing::debug!(session = id, "a session closed while being read");
            }
            Err(e @ (RexError::ServerNotRunning { .. } | RexError::NotFound { .. })) => {
                return Err(e);
            }
            Err(error) => tracing::warn!(%error, session = id, "could not read a session"),
        }
    }
    let sessions = list
        .iter()
        .filter_map(|s| found.remove(&s.session_id))
        .collect();
    Ok(PaneMap { sessions })
}
