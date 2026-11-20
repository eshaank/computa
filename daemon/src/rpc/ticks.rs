//! Phase 0 trial data: a made-up value per tick. Replaced by real samples
//! in phase 1.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::pb::Tick;

const DEFAULT_INTERVAL_MS: u32 = 1_000;
const MIN_INTERVAL_MS: u32 = 100;
const MAX_INTERVAL_MS: u32 = 60_000;

/// Turns the interval a client asked for into one the daemon will honour.
/// Zero means "use the default".
pub fn clamp_interval(requested_ms: u32) -> Duration {
    let ms = if requested_ms == 0 {
        DEFAULT_INTERVAL_MS
    } else {
        requested_ms.clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS)
    };
    Duration::from_millis(u64::from(ms))
}

/// A smooth wave between 0 and 100, so a client can see values change.
pub fn tick_value(sequence: u64) -> f64 {
    // Precision loss only starts beyond 2^52 ticks, which is never reached.
    #[allow(clippy::cast_precision_loss)]
    let phase = sequence as f64 / 10.0;
    50.0 + 50.0 * phase.sin()
}

pub(super) fn make_tick(sequence: u64) -> Tick {
    Tick {
        sequence,
        value: tick_value(sequence),
        unix_ms: unix_ms_now(),
    }
}

fn unix_ms_now() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(since_epoch) => i64::try_from(since_epoch.as_millis()).unwrap_or(i64::MAX),
        Err(error) => {
            tracing::warn!(%error, "system clock is before the Unix epoch; reporting 0");
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_interval_means_the_default() {
        assert_eq!(clamp_interval(0), Duration::from_millis(1_000));
    }

    #[test]
    fn interval_is_clamped_at_both_ends() {
        assert_eq!(clamp_interval(1), Duration::from_millis(100));
        assert_eq!(clamp_interval(250), Duration::from_millis(250));
        assert_eq!(clamp_interval(u32::MAX), Duration::from_millis(60_000));
    }

    #[test]
    fn tick_value_stays_between_0_and_100() {
        for sequence in 0..10_000 {
            let value = tick_value(sequence);
            assert!(
                (0.0..=100.0).contains(&value),
                "sequence {sequence} gave {value}"
            );
        }
    }

    #[test]
    fn tick_carries_its_sequence_and_a_recent_time() {
        let tick = make_tick(7);
        assert_eq!(tick.sequence, 7);
        // 2026-01-01 in milliseconds; anything earlier means the clock read failed.
        assert!(
            tick.unix_ms > 1_767_225_600_000,
            "unix_ms was {}",
            tick.unix_ms
        );
    }
}
