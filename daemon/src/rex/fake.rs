//! A scripted [`RexClient`] for tests.

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};

use tokio::sync::mpsc;

use super::model::{BlockView, LayerView, PaneProcess, ProcInfo, TERMINAL_CREATOR, WindowView};
use super::{EventLines, RexClient, RexError, SessionRef, SessionView};

#[derive(Default)]
struct State {
    failure: Option<RexError>,
    sessions: Vec<SessionView>,
    processes: HashMap<String, PaneProcess>,
    senders: Vec<mpsc::UnboundedSender<String>>,
    calls: Vec<String>,
}

#[derive(Default)]
pub struct FakeRex {
    state: Mutex<State>,
    live: Arc<AtomicUsize>,
}

impl FakeRex {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().expect("fake lock")
    }

    /// Every call fails with `error` until cleared with `None`.
    pub fn set_failure(&self, error: Option<RexError>) {
        self.lock().failure = error;
    }

    pub fn set_sessions(&self, sessions: Vec<SessionView>) {
        self.lock().sessions = sessions;
    }

    pub fn set_process(&self, block: &str, process: PaneProcess) {
        self.lock().processes.insert(block.to_owned(), process);
    }

    /// Sends a line to every open event stream.
    pub fn push_event(&self, line: &str) {
        for tx in &self.lock().senders {
            // A stream dropped since is simply skipped.
            let _ = tx.send(line.to_owned());
        }
    }

    /// Ends every open event stream, as if `rex events` exited.
    pub fn end_event_streams(&self) {
        self.lock().senders.clear();
    }

    /// Event streams that have been opened and not dropped.
    pub fn live_event_streams(&self) -> usize {
        self.live.load(Ordering::SeqCst)
    }

    /// Calls made so far, for example "view session:a".
    pub fn calls(&self) -> Vec<String> {
        self.lock().calls.clone()
    }

    pub fn clear_calls(&self) {
        self.lock().calls.clear();
    }

    fn record(&self, call: String) -> Result<(), RexError> {
        let mut st = self.lock();
        st.calls.push(call);
        st.failure.clone().map_or(Ok(()), Err)
    }
}

#[tonic::async_trait]
impl RexClient for FakeRex {
    async fn version(&self) -> Result<String, RexError> {
        self.record("version".into())?;
        Ok("0.1.0-test".into())
    }

    async fn list_sessions(&self) -> Result<Vec<SessionRef>, RexError> {
        self.record("list".into())?;
        Ok(self
            .lock()
            .sessions
            .iter()
            .map(|s| SessionRef {
                session_id: s.session_id.clone(),
                label: s.label.clone(),
            })
            .collect())
    }

    async fn view_session(&self, session_id: &str) -> Result<SessionView, RexError> {
        self.record(format!("view {session_id}"))?;
        let st = self.lock();
        st.sessions
            .iter()
            .find(|s| s.session_id == session_id)
            .cloned()
            .ok_or_else(|| RexError::TargetGone {
                command: format!("view {session_id}"),
                stderr: "no such session".into(),
            })
    }

    async fn pane_process(&self, _session: &str, block: &str) -> Result<PaneProcess, RexError> {
        self.record(format!("process {block}"))?;
        Ok(self
            .lock()
            .processes
            .get(block)
            .cloned()
            .unwrap_or_default())
    }

    async fn events(&self) -> Result<Box<dyn EventLines>, RexError> {
        self.record("events".into())?;
        let (tx, rx) = mpsc::unbounded_channel();
        self.lock().senders.push(tx);
        self.live.fetch_add(1, Ordering::SeqCst);
        Ok(Box::new(FakeEvents {
            rx,
            live: Arc::clone(&self.live),
        }))
    }
}

struct FakeEvents {
    rx: mpsc::UnboundedReceiver<String>,
    live: Arc<AtomicUsize>,
}

#[tonic::async_trait]
impl EventLines for FakeEvents {
    async fn next_line(&mut self) -> Result<Option<String>, RexError> {
        Ok(self.rx.recv().await)
    }
}

impl Drop for FakeEvents {
    fn drop(&mut self) {
        self.live.fetch_sub(1, Ordering::SeqCst);
    }
}

/// A session with one tab per entry of `windows`, each holding terminal
/// panes with the given block ids.
pub fn session(id: &str, label: &str, windows: &[(&str, &[&str])]) -> SessionView {
    SessionView {
        session_id: id.to_owned(),
        label: label.to_owned(),
        windows: windows
            .iter()
            .map(|(wid, blocks)| WindowView {
                window_id: (*wid).to_owned(),
                label: format!("Tab {wid}"),
                layers: vec![LayerView {
                    blocks: blocks
                        .iter()
                        .map(|b| BlockView {
                            block_id: (*b).to_owned(),
                            label: "shell".to_owned(),
                            creator_name: TERMINAL_CREATOR.to_owned(),
                        })
                        .collect(),
                }],
            })
            .collect(),
    }
}

/// A pane whose root is `root` and whose foreground is `fg`.
pub fn process(root: i32, fg: Option<ProcInfo>, ancestors: Vec<ProcInfo>) -> PaneProcess {
    PaneProcess {
        child: Some(ProcInfo {
            pid: root,
            name: "login".into(),
            path: "/usr/bin/login".into(),
            ..ProcInfo::default()
        }),
        foreground: fg,
        ancestors,
    }
}
