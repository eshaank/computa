//! The `WatchProcesses` stream: frames from the shared process sampler, no
//! more often than the client asked for.

use std::time::{Duration, Instant};

use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::Status;

use crate::pb::ProcessSnapshot;
use crate::processes::Subscription;

/// What zero means.
const DEFAULT_INTERVAL_MS: u32 = 2000;
const MIN_INTERVAL_MS: u32 = 1000;
const MAX_INTERVAL_MS: u32 = 60_000;
/// Frames arrive on the sampler's schedule, which can run a little early
/// relative to this client's last frame. Within this margin a frame counts
/// as due.
const EARLY_MARGIN: Duration = Duration::from_millis(250);

/// Rounds a requested interval to whole seconds between 1 s and 60 s; zero
/// means 2 s.
pub fn round_interval(requested_ms: u32) -> u32 {
    if requested_ms == 0 {
        return DEFAULT_INTERVAL_MS;
    }
    let seconds = requested_ms.saturating_add(500) / 1000;
    (seconds * 1000).clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS)
}

/// Whether a frame taken at `at` is due for a client whose last frame was
/// taken at `last_sent`.
pub(super) fn due(last_sent: Option<Instant>, at: Instant, interval: Duration) -> bool {
    last_sent.is_none_or(|last| at.saturating_duration_since(last) + EARLY_MARGIN >= interval)
}

/// Starts a task that sends the newest frame as soon as there is one, then
/// one per `interval`, until the client goes away. The subscription is
/// held by the task, so the sampler stops when the last client leaves.
pub fn stream(
    subscription: Subscription,
    interval: Duration,
) -> ReceiverStream<Result<ProcessSnapshot, Status>> {
    let (tx, rx) = mpsc::channel(2);
    tokio::spawn(async move {
        let mut frames = subscription.receiver();
        let mut last_sent = None;
        loop {
            let frame = frames.borrow_and_update().clone();
            if let Some(frame) = frame.filter(|f| due(last_sent, f.at, interval)) {
                last_sent = Some(frame.at);
                if tx.send(Ok(frame.snapshot.clone())).await.is_err() {
                    break;
                }
            }
            tokio::select! {
                () = tx.closed() => break,
                changed = frames.changed() => {
                    if changed.is_err() {
                        tracing::info!("the process sampler went away; ending a WatchProcesses stream");
                        break;
                    }
                }
            }
        }
        drop(subscription);
        tracing::debug!("a WatchProcesses stream ended");
    });
    ReceiverStream::new(rx)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_means_two_seconds() {
        assert_eq!(round_interval(0), 2000);
    }

    #[test]
    fn rounds_to_whole_seconds_within_limits() {
        assert_eq!(round_interval(1), 1000);
        assert_eq!(round_interval(1499), 1000);
        assert_eq!(round_interval(1500), 2000);
        assert_eq!(round_interval(2400), 2000);
        assert_eq!(round_interval(59_000), 59_000);
        assert_eq!(round_interval(90_000), 60_000);
        assert_eq!(round_interval(u32::MAX), 60_000);
    }

    #[test]
    fn a_frame_is_due_after_the_interval_less_a_small_margin() {
        let t0 = Instant::now();
        let two = Duration::from_secs(2);
        assert!(due(None, t0, two), "the first frame is always due");
        assert!(!due(Some(t0), t0 + Duration::from_secs(1), two));
        assert!(due(Some(t0), t0 + Duration::from_millis(1800), two));
        assert!(due(Some(t0), t0 + Duration::from_secs(3), two));
    }
}
