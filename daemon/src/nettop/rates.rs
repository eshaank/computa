//! Turns two readings of `nettop`'s byte counters into rates. Pure: no
//! clock, no child process.

use std::collections::HashMap;
use std::sync::Arc;

use super::meter::MeterStatus;
use super::parse::Reading;
use crate::pb::ProcessNetworkStatus;

/// Bytes per second in each direction.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Rate {
    pub rx: f64,
    pub tx: f64,
}

/// Each process's rate between `prev` and `cur`, for every process in
/// `cur`. `None` if `cur` is not later than `prev`.
///
/// A process missing from `prev`, or listed there under another name (its
/// pid was reused), starts from zero: everything `nettop` counted for it
/// came after `prev`, because `nettop` was already watching. A counter that
/// went down (connections closed) gives zero, never a negative rate.
pub fn rates(prev: &Reading, cur: &Reading) -> Option<HashMap<i32, Rate>> {
    let seconds = cur.at.checked_duration_since(prev.at)?.as_secs_f64();
    if seconds <= 0.0 {
        return None;
    }
    let out = cur
        .counters
        .iter()
        .map(|(&pid, c)| {
            let (rx0, tx0) = prev
                .counters
                .get(&pid)
                .filter(|p| p.name == c.name)
                .map_or((0, 0), |p| (p.rx, p.tx));
            let rate = Rate {
                rx: c.rx.saturating_sub(rx0) as f64 / seconds,
                tx: c.tx.saturating_sub(tx0) as f64 / seconds,
            };
            (pid, rate)
        })
        .collect();
    Some(out)
}

/// What one process pass knows about network traffic.
#[derive(Debug, Clone, PartialEq)]
pub struct NetView {
    pub status: ProcessNetworkStatus,
    /// Every process `nettop` reports. All zero when not available.
    pub rates: HashMap<i32, Rate>,
}

impl NetView {
    fn unavailable(problem: String, reading: Option<&Reading>) -> Self {
        let rates = reading.map_or_else(HashMap::new, |r| {
            r.counters
                .keys()
                .map(|&pid| (pid, Rate::default()))
                .collect()
        });
        Self {
            status: ProcessNetworkStatus {
                available: false,
                problem,
            },
            rates,
        }
    }
}

/// Remembers the reading the previous pass used, so each pass reports the
/// rates since the one before.
#[derive(Debug, Default)]
pub struct NetTracker {
    base: Option<Arc<Reading>>,
    /// The last rates worked out, and the reading they end at.
    last: Option<(Arc<Reading>, HashMap<i32, Rate>)>,
}

impl NetTracker {
    /// The view for this pass. `None` while nobody asked for network
    /// numbers, which also forgets the old readings.
    pub fn update(&mut self, status: Option<&MeterStatus>) -> Option<NetView> {
        let Some(status) = status else {
            *self = Self::default();
            return None;
        };
        let latest = status.latest.as_ref();
        if let Some(problem) = &status.problem {
            return Some(NetView::unavailable(problem.clone(), latest.map(|r| &**r)));
        }
        let Some(latest) = latest else {
            return Some(NetView::unavailable(String::new(), None));
        };
        if let Some((end, rates)) = &self.last
            && Arc::ptr_eq(end, latest)
        {
            // No new reading since the last pass: the same rates still hold.
            return Some(available(rates.clone()));
        }
        let base = self.base.replace(Arc::clone(latest));
        let fresh = base
            .filter(|b| b.run == latest.run)
            .and_then(|b| rates(&b, latest));
        match fresh {
            Some(rates) => {
                self.last = Some((Arc::clone(latest), rates.clone()));
                Some(available(rates))
            }
            // The first reading of a run: nothing to compare it with yet.
            None => {
                self.last = None;
                Some(NetView::unavailable(String::new(), Some(latest)))
            }
        }
    }
}

fn available(rates: HashMap<i32, Rate>) -> NetView {
    NetView {
        status: ProcessNetworkStatus {
            available: true,
            problem: String::new(),
        },
        rates,
    }
}

#[cfg(test)]
#[path = "rates_tests.rs"]
mod tests;
