//! The sampling thread: one pass per interval while its generation lasts.

use std::sync::Arc;
use std::time::Instant;

use super::group;
use super::monitor::{Frame, Shared, lock};
use crate::nettop::NetTracker;
use crate::sampler::unix_ms_now;

/// Takes a priming pass, then one pass per interval until this generation
/// ends. If a pass runs late, the schedule restarts from it.
pub(super) fn run(shared: &Shared, generation: u64) {
    let mut pass = (shared.factory)();
    let mut last = Instant::now();
    pass(last);
    let mut first = true;
    let mut seq = 0;
    let mut traffic = NetTracker::default();
    while wait_for_turn(shared, generation, last, first) {
        let now = Instant::now();
        let table = Arc::new(pass(now));
        let unix_ms = unix_ms_now();
        let snapshot = group::snapshot(&table, unix_ms, None);
        let view = traffic.update(shared.network.status(Instant::now()).as_ref());
        let networked = view.map(|v| group::snapshot(&table, unix_ms, Some(&v)));
        seq += 1;
        let frame = Arc::new(Frame {
            seq,
            at: now,
            table,
            snapshot,
            networked,
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
