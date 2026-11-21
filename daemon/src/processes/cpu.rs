//! Per-process CPU percent from two readings of cumulative CPU time.

use std::collections::HashMap;
use std::time::Instant;

/// One reading of a process's cumulative CPU time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CpuReading {
    /// Identifies the process together with its pid (see `RawProc`).
    pub start_us: u64,
    pub cpu_ns: u64,
}

/// CPU percent between two readings `wall_ns` apart, where 100 means one
/// core fully busy. A process seen for the first time, a reused pid (a
/// different start time) or CPU time that went backwards reports zero.
pub fn cpu_percent(prev: Option<CpuReading>, cur: CpuReading, wall_ns: u64) -> f64 {
    match prev {
        Some(p) if p.start_us == cur.start_us && cur.cpu_ns >= p.cpu_ns && wall_ns > 0 => {
            (cur.cpu_ns - p.cpu_ns) as f64 / wall_ns as f64 * 100.0
        }
        _ => 0.0,
    }
}

/// Remembers the previous pass's readings. Each pass is `begin`, then
/// `percent` once per readable process, then `finish`, which forgets
/// processes that were not seen.
#[derive(Debug, Default)]
pub struct CpuTracker {
    prev: HashMap<i32, CpuReading>,
    next: HashMap<i32, CpuReading>,
    prev_at: Option<Instant>,
    wall_ns: u64,
}

impl CpuTracker {
    pub fn begin(&mut self, now: Instant) {
        self.wall_ns = self.prev_at.map_or(0, |at| {
            u64::try_from(now.saturating_duration_since(at).as_nanos()).unwrap_or(u64::MAX)
        });
        self.prev_at = Some(now);
        self.next.clear();
    }

    pub fn percent(&mut self, pid: i32, cur: CpuReading) -> f64 {
        self.next.insert(pid, cur);
        cpu_percent(self.prev.get(&pid).copied(), cur, self.wall_ns)
    }

    pub fn finish(&mut self) {
        std::mem::swap(&mut self.prev, &mut self.next);
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    const SEC: u64 = 1_000_000_000;

    fn r(start_us: u64, cpu_ns: u64) -> CpuReading {
        CpuReading { start_us, cpu_ns }
    }

    #[test]
    fn percent_is_cpu_time_over_wall_time() {
        assert_eq!(cpu_percent(Some(r(1, 0)), r(1, SEC), SEC), 100.0);
        assert_eq!(cpu_percent(Some(r(1, SEC)), r(1, 2 * SEC), 2 * SEC), 50.0);
        // Four busy cores.
        assert_eq!(cpu_percent(Some(r(1, 0)), r(1, 8 * SEC), 2 * SEC), 400.0);
    }

    #[test]
    fn first_sight_reused_pid_and_backwards_time_give_zero() {
        assert_eq!(cpu_percent(None, r(1, SEC), SEC), 0.0);
        assert_eq!(cpu_percent(Some(r(1, 0)), r(2, SEC), SEC), 0.0);
        assert_eq!(cpu_percent(Some(r(1, 5 * SEC)), r(1, SEC), SEC), 0.0);
        assert_eq!(cpu_percent(Some(r(1, 0)), r(1, SEC), 0), 0.0);
    }

    #[test]
    fn tracker_uses_wall_time_between_passes_and_forgets_gone_pids() {
        let t0 = Instant::now();
        let mut t = CpuTracker::default();
        t.begin(t0);
        assert_eq!(t.percent(10, r(1, 0)), 0.0);
        assert_eq!(t.percent(11, r(1, 0)), 0.0);
        t.finish();

        t.begin(t0 + Duration::from_secs(2));
        assert_eq!(t.percent(10, r(1, SEC)), 50.0);
        t.finish(); // pid 11 was not seen this pass

        t.begin(t0 + Duration::from_secs(3));
        assert_eq!(t.percent(11, r(1, SEC)), 0.0, "pid 11 starts afresh");
        // pid 10 reused by a new process with a later start time.
        assert_eq!(t.percent(10, r(9, 3 * SEC)), 0.0);
        t.finish();
    }
}
