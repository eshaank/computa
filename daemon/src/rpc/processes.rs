//! The `WatchProcesses` stream: frames from the shared process sampler, no
//! more often than the client asked for.

use std::time::{Duration, Instant};

use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::Status;

use crate::pb::{ProcessNetworkStatus, ProcessSnapshot};
use crate::processes::{Frame, Subscription};

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

/// The message for one client. With `network`, the frame's networked
/// snapshot, or (for a frame taken before measuring started) the plain one
/// marked as not available yet.
pub(super) fn message(frame: &Frame, network: bool) -> ProcessSnapshot {
    match (&frame.networked, network) {
        (Some(networked), true) => networked.clone(),
        (None, true) => ProcessSnapshot {
            network: Some(ProcessNetworkStatus::default()),
            ..frame.snapshot.clone()
        },
        (_, false) => frame.snapshot.clone(),
    }
}

/// Starts a task that sends the newest frame as soon as there is one, then
/// one per `interval`, until the client goes away. The subscription is
/// held by the task, so the sampler (and the network meter, if this client
/// asked for traffic) stops when the last client leaves.
pub fn stream(
    subscription: Subscription,
    interval: Duration,
    network: bool,
) -> ReceiverStream<Result<ProcessSnapshot, Status>> {
    let (tx, rx) = mpsc::channel(2);
    tokio::spawn(async move {
        let mut frames = subscription.receiver();
        let mut last_sent = None;
        loop {
            let frame = frames.borrow_and_update().clone();
            if let Some(frame) = frame.filter(|f| due(last_sent, f.at, interval)) {
                last_sent = Some(frame.at);
                if tx.send(Ok(message(&frame, network))).await.is_err() {
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
        // The last network subscriber leaving waits for nettop to be killed
        // and reaped, so that wait stays off the async workers.
        if network {
            if let Err(error) = tokio::task::spawn_blocking(move || drop(subscription)).await {
                tracing::error!(%error, "could not release the process subscription");
            }
        } else {
            drop(subscription);
        }
        tracing::debug!("a WatchProcesses stream ended");
    });
    ReceiverStream::new(rx)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::pb::ProcessGroup;
    use crate::processes::ProcessTable;

    fn frame(networked: Option<ProcessSnapshot>) -> Frame {
        Frame {
            seq: 1,
            at: Instant::now(),
            table: Arc::new(ProcessTable::default()),
            snapshot: ProcessSnapshot {
                unix_ms: 1,
                ..ProcessSnapshot::default()
            },
            networked,
        }
    }

    #[test]
    fn each_client_gets_the_snapshot_it_asked_for() {
        let networked = ProcessSnapshot {
            unix_ms: 1,
            groups: vec![ProcessGroup {
                rx_bytes_per_sec: 5.0,
                ..ProcessGroup::default()
            }],
            network: Some(ProcessNetworkStatus {
                available: true,
                problem: String::new(),
            }),
            ..ProcessSnapshot::default()
        };
        let f = frame(Some(networked.clone()));
        assert_eq!(message(&f, true), networked);
        assert_eq!(message(&f, false), f.snapshot, "no rates, no status");

        let before = frame(None);
        let early = message(&before, true);
        assert_eq!(early.network, Some(ProcessNetworkStatus::default()));
        assert_eq!(early.unix_ms, 1);
        assert_eq!(message(&before, false).network, None);
    }

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
