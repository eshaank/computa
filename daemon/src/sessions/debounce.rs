//! Collects refresh work from bursts of Rex events. The first event of a
//! burst starts a short window; everything that arrives in it is done once
//! when the window ends. The window is not extended, so a steady stream of
//! events still gets handled on time.

use std::collections::BTreeSet;
use std::time::Duration;

use tokio::time::Instant;

/// How long a burst may gather before it is handled.
pub const WINDOW: Duration = Duration::from_millis(150);

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Work {
    /// Sessions to re-read in full.
    pub sessions: BTreeSet<String>,
    /// Panes whose processes to re-read, as (session, block), leaving out
    /// panes of sessions that are re-read in full.
    pub panes: BTreeSet<(String, String)>,
}

impl Work {
    pub fn is_empty(&self) -> bool {
        self.sessions.is_empty() && self.panes.is_empty()
    }
}

#[derive(Debug)]
pub struct Debouncer {
    window: Duration,
    deadline: Option<Instant>,
    work: Work,
}

impl Default for Debouncer {
    fn default() -> Self {
        Self::new(WINDOW)
    }
}

impl Debouncer {
    pub fn new(window: Duration) -> Self {
        Self {
            window,
            deadline: None,
            work: Work::default(),
        }
    }

    pub fn session(&mut self, id: String, now: Instant) {
        self.work.sessions.insert(id);
        self.arm(now);
    }

    pub fn pane(&mut self, session: String, block: String, now: Instant) {
        self.work.panes.insert((session, block));
        self.arm(now);
    }

    /// Forgets pending work for a session that is gone.
    pub fn forget_session(&mut self, id: &str) {
        self.work.sessions.remove(id);
        self.work.panes.retain(|(s, _)| s != id);
        if self.work.is_empty() {
            self.deadline = None;
        }
    }

    fn arm(&mut self, now: Instant) {
        self.deadline.get_or_insert(now + self.window);
    }

    /// When the pending work is due, if there is any.
    pub fn deadline(&self) -> Option<Instant> {
        self.deadline
    }

    /// Takes the pending work if it is due at `now`.
    pub fn take_due(&mut self, now: Instant) -> Option<Work> {
        if self.deadline.is_none_or(|d| now < d) {
            return None;
        }
        self.deadline = None;
        let mut work = std::mem::take(&mut self.work);
        let sessions = &work.sessions;
        work.panes.retain(|(s, _)| !sessions.contains(s));
        Some(work)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }

    #[test]
    fn a_burst_is_handled_once_after_the_window() {
        let t0 = Instant::now();
        let mut d = Debouncer::new(ms(150));
        assert_eq!(d.deadline(), None);
        d.session("s1".into(), t0);
        d.session("s1".into(), t0 + ms(10));
        d.pane("s2".into(), "b".into(), t0 + ms(100));
        assert_eq!(
            d.deadline(),
            Some(t0 + ms(150)),
            "not extended by later events"
        );
        assert_eq!(d.take_due(t0 + ms(149)), None);
        let work = d.take_due(t0 + ms(150)).expect("due");
        assert_eq!(work.sessions.into_iter().collect::<Vec<_>>(), vec!["s1"]);
        assert_eq!(work.panes.len(), 1);
        assert_eq!(d.deadline(), None);
        assert_eq!(d.take_due(t0 + ms(400)), None, "nothing left");
    }

    #[test]
    fn pane_work_is_folded_into_a_session_refresh() {
        let t0 = Instant::now();
        let mut d = Debouncer::new(ms(150));
        d.pane("s1".into(), "b1".into(), t0);
        d.session("s1".into(), t0);
        d.pane("s2".into(), "b2".into(), t0);
        let work = d.take_due(t0 + ms(150)).expect("due");
        assert_eq!(
            work.panes.into_iter().collect::<Vec<_>>(),
            vec![("s2".to_owned(), "b2".to_owned())]
        );
    }

    #[test]
    fn forgetting_the_only_session_disarms() {
        let t0 = Instant::now();
        let mut d = Debouncer::new(ms(150));
        d.pane("s1".into(), "b1".into(), t0);
        d.forget_session("s1");
        assert_eq!(d.deadline(), None);
    }
}
