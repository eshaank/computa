//! The `WatchSystem` stream: every Nth sample the sampler publishes.

use std::sync::Arc;

use tokio::sync::{mpsc, watch};
use tokio_stream::wrappers::ReceiverStream;
use tonic::Status;

use crate::pb::SystemSample;
use crate::sampler::Published;

/// The longest interval a client may ask for.
pub const MAX_INTERVAL_MS: u32 = 60_000;

/// Rounds a requested interval to the nearest multiple of the sample
/// interval (zero means one sample interval), between one sample interval
/// and `MAX_INTERVAL_MS`. Returns the interval and how many samples it spans.
pub fn round_interval(requested_ms: u32, sample_ms: u32) -> (u32, u32) {
    let sample_ms = sample_ms.max(1);
    let max_steps = (MAX_INTERVAL_MS / sample_ms).max(1);
    let steps = if requested_ms == 0 {
        1
    } else {
        (requested_ms.saturating_add(sample_ms / 2) / sample_ms).clamp(1, max_steps)
    };
    (steps * sample_ms, steps)
}

/// Starts a task that sends the newest sample at once, then one every
/// `steps` samples, until the client goes away or the sampler stops.
pub fn stream(
    mut latest: watch::Receiver<Arc<Published>>,
    steps: u32,
) -> ReceiverStream<Result<SystemSample, Status>> {
    let (tx, rx) = mpsc::channel(4);
    tokio::spawn(async move {
        let first = Arc::clone(&latest.borrow_and_update());
        let mut last_sent = first.seq;
        if tx.send(Ok(first.sample.clone())).await.is_err() {
            return;
        }
        loop {
            tokio::select! {
                () = tx.closed() => break,
                changed = latest.changed() => {
                    if changed.is_err() {
                        tracing::info!("the sampler stopped; ending a WatchSystem stream");
                        break;
                    }
                }
            }
            let published = Arc::clone(&latest.borrow_and_update());
            if published.seq < last_sent + u64::from(steps) {
                continue;
            }
            last_sent = published.seq;
            if tx.send(Ok(published.sample.clone())).await.is_err() {
                break;
            }
        }
        tracing::debug!("a WatchSystem stream ended");
    });
    ReceiverStream::new(rx)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_means_one_sample_interval() {
        assert_eq!(round_interval(0, 1000), (1000, 1));
    }

    #[test]
    fn rounds_to_nearest_multiple() {
        assert_eq!(round_interval(1, 1000), (1000, 1));
        assert_eq!(round_interval(1499, 1000), (1000, 1));
        assert_eq!(round_interval(1500, 1000), (2000, 2));
        assert_eq!(round_interval(2400, 1000), (2000, 2));
        assert_eq!(round_interval(5000, 1000), (5000, 5));
    }

    #[test]
    fn caps_at_sixty_seconds() {
        assert_eq!(round_interval(60_000, 1000), (60_000, 60));
        assert_eq!(round_interval(90_000, 1000), (60_000, 60));
        assert_eq!(round_interval(u32::MAX, 1000), (60_000, 60));
    }
}
