//! Rates from two readings of a cumulative counter.

/// Bytes per second between two readings `elapsed_secs` apart.
///
/// A counter that went backwards was reset (an interface went down, a disk
/// was removed, or a 64-bit counter wrapped, which takes centuries), so the
/// rate for that interval is reported as zero rather than as a huge number.
pub fn per_second(prev: u64, cur: u64, elapsed_secs: f64) -> f64 {
    if cur < prev || elapsed_secs <= 0.0 || !elapsed_secs.is_finite() {
        return 0.0;
    }
    (cur - prev) as f64 / elapsed_secs
}

#[cfg(test)]
mod tests {
    use super::per_second;

    #[test]
    fn rate_is_difference_over_time() {
        assert_eq!(per_second(1_000, 3_000, 2.0), 1_000.0);
        assert_eq!(per_second(5, 5, 1.0), 0.0);
    }

    #[test]
    fn reset_or_wrapped_counter_gives_zero() {
        assert_eq!(per_second(10_000, 200, 1.0), 0.0);
        assert_eq!(per_second(u64::MAX - 5, 3, 1.0), 0.0);
    }

    #[test]
    fn zero_or_bad_elapsed_time_gives_zero() {
        assert_eq!(per_second(0, 100, 0.0), 0.0);
        assert_eq!(per_second(0, 100, -1.0), 0.0);
        assert_eq!(per_second(0, 100, f64::NAN), 0.0);
    }
}
