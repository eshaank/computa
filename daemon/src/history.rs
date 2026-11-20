//! The ring buffer of past samples and the downsampling `GetHistory` uses.
//!
//! Everything here is pure: no clocks, no system calls. The caller passes in
//! the current time and the sample interval.

use std::collections::VecDeque;

use crate::pb::HistoryPoint;

/// Keeps the newest `capacity` history points, oldest first.
#[derive(Debug)]
pub struct HistoryRing {
    points: VecDeque<HistoryPoint>,
    capacity: usize,
}

impl HistoryRing {
    /// A ring that holds at most `capacity` points. A capacity of zero is
    /// raised to one so the newest point is always kept.
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.max(1);
        Self {
            points: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    /// Adds `point`, dropping the oldest point when the ring is full.
    pub fn push(&mut self, point: HistoryPoint) {
        if self.points.len() == self.capacity {
            self.points.pop_front();
        }
        self.points.push_back(point);
    }

    pub fn len(&self) -> usize {
        self.points.len()
    }

    pub fn is_empty(&self) -> bool {
        self.points.is_empty()
    }

    /// The points newer than `window_ms` before `now_ms`, oldest first.
    /// A `window_ms` of zero returns every point.
    pub fn window(&self, now_ms: i64, window_ms: u64) -> Vec<HistoryPoint> {
        if window_ms == 0 {
            return self.points.iter().copied().collect();
        }
        let since = now_ms.saturating_sub(i64::try_from(window_ms).unwrap_or(i64::MAX));
        self.points
            .iter()
            .filter(|point| point.unix_ms > since)
            .copied()
            .collect()
    }
}

/// Points ready for a `History` reply.
#[derive(Debug, PartialEq)]
pub struct Downsampled {
    pub points: Vec<HistoryPoint>,
    pub step_ms: u32,
}

/// Reduces `points` (oldest first) to at most `max_points` by averaging
/// runs of neighbouring samples. Zero means no limit.
///
/// Buckets are aligned to the newest sample, so the newest point always
/// averages a full bucket; when the count does not divide evenly, the oldest
/// bucket is the short one. Each averaged point carries the time of its
/// newest sample.
pub fn downsample(
    points: &[HistoryPoint],
    max_points: usize,
    sample_interval_ms: u32,
) -> Downsampled {
    if max_points == 0 || points.len() <= max_points {
        return Downsampled {
            points: points.to_vec(),
            step_ms: sample_interval_ms,
        };
    }
    let per_bucket = points.len().div_ceil(max_points);
    let short_bucket = points.len() % per_bucket;
    let (head, tail) = points.split_at(short_bucket);
    let mut out = Vec::with_capacity(max_points);
    if !head.is_empty() {
        out.push(average(head));
    }
    out.extend(tail.chunks(per_bucket).map(average));
    let factor = u32::try_from(per_bucket).unwrap_or(u32::MAX);
    Downsampled {
        points: out,
        step_ms: sample_interval_ms.saturating_mul(factor),
    }
}

/// The mean of a non-empty run of points, timed at its newest sample.
fn average(run: &[HistoryPoint]) -> HistoryPoint {
    let n = run.len() as f64;
    let mean_f = |get: fn(&HistoryPoint) -> f64| run.iter().map(get).sum::<f64>() / n;
    let mean_u = |get: fn(&HistoryPoint) -> u64| {
        let sum: u128 = run.iter().map(|p| u128::from(get(p))).sum();
        let len = run.len() as u128;
        u64::try_from((sum + len / 2) / len).unwrap_or(u64::MAX)
    };
    HistoryPoint {
        unix_ms: run.last().map_or(0, |p| p.unix_ms),
        cpu_usage_percent: mean_f(|p| p.cpu_usage_percent),
        cpu_user_percent: mean_f(|p| p.cpu_user_percent),
        cpu_system_percent: mean_f(|p| p.cpu_system_percent),
        memory_used_bytes: mean_u(|p| p.memory_used_bytes),
        memory_app_bytes: mean_u(|p| p.memory_app_bytes),
        memory_wired_bytes: mean_u(|p| p.memory_wired_bytes),
        memory_compressed_bytes: mean_u(|p| p.memory_compressed_bytes),
        swap_used_bytes: mean_u(|p| p.swap_used_bytes),
        net_rx_bytes_per_sec: mean_f(|p| p.net_rx_bytes_per_sec),
        net_tx_bytes_per_sec: mean_f(|p| p.net_tx_bytes_per_sec),
        disk_read_bytes_per_sec: mean_f(|p| p.disk_read_bytes_per_sec),
        disk_write_bytes_per_sec: mean_f(|p| p.disk_write_bytes_per_sec),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(unix_ms: i64, cpu: f64, mem: u64) -> HistoryPoint {
        HistoryPoint {
            unix_ms,
            cpu_usage_percent: cpu,
            memory_used_bytes: mem,
            ..HistoryPoint::default()
        }
    }

    fn ring_of(times: impl IntoIterator<Item = i64>, capacity: usize) -> HistoryRing {
        let mut ring = HistoryRing::new(capacity);
        for t in times {
            ring.push(point(t, t as f64, 0));
        }
        ring
    }

    #[test]
    fn ring_wraps_and_keeps_newest_oldest_first() {
        let ring = ring_of(1..=7, 5);
        let times: Vec<i64> = ring.window(0, 0).iter().map(|p| p.unix_ms).collect();
        assert_eq!(times, vec![3, 4, 5, 6, 7]);
        assert_eq!(ring.len(), 5);
    }

    #[test]
    fn window_keeps_only_recent_points() {
        let ring = ring_of((1..=10).map(|s| s * 1000), 100);
        let times: Vec<i64> = ring
            .window(10_000, 3_000)
            .iter()
            .map(|p| p.unix_ms)
            .collect();
        assert_eq!(times, vec![8_000, 9_000, 10_000]);
        assert_eq!(ring.window(10_000, 0).len(), 10);
    }

    #[test]
    fn no_downsampling_when_under_the_limit_or_unlimited() {
        let pts: Vec<_> = (1..=4).map(|t| point(t, 1.0, 1)).collect();
        assert_eq!(downsample(&pts, 0, 1000).points.len(), 4);
        let same = downsample(&pts, 4, 1000);
        assert_eq!(same.points, pts);
        assert_eq!(same.step_ms, 1000);
    }

    #[test]
    fn downsampling_averages_neighbours_newest_aligned() {
        // 7 points into at most 3: buckets of 3, the oldest bucket has 1.
        let pts: Vec<_> = (1..=7)
            .map(|t| point(t * 1000, t as f64 * 10.0, t as u64))
            .collect();
        let out = downsample(&pts, 3, 1000);
        assert_eq!(out.step_ms, 3000);
        let times: Vec<i64> = out.points.iter().map(|p| p.unix_ms).collect();
        assert_eq!(times, vec![1000, 4000, 7000]);
        let cpu: Vec<f64> = out.points.iter().map(|p| p.cpu_usage_percent).collect();
        assert_eq!(cpu, vec![10.0, 30.0, 60.0]);
        let mem: Vec<u64> = out.points.iter().map(|p| p.memory_used_bytes).collect();
        assert_eq!(mem, vec![1, 3, 6]);
    }

    #[test]
    fn downsampling_never_exceeds_max_points() {
        let pts: Vec<_> = (0..3600).map(|t| point(t, 0.0, 0)).collect();
        for max in [1, 2, 7, 100, 599, 1799, 3599] {
            let out = downsample(&pts, max, 1000);
            assert!(
                out.points.len() <= max,
                "max {max} gave {}",
                out.points.len()
            );
            assert_eq!(out.points.last().map(|p| p.unix_ms), Some(3599));
        }
    }

    #[test]
    fn unsigned_average_rounds_and_does_not_overflow() {
        let pts = vec![point(1, 0.0, u64::MAX), point(2, 0.0, u64::MAX)];
        assert_eq!(
            downsample(&pts, 1, 1000).points[0].memory_used_bytes,
            u64::MAX
        );
    }
}
