//! The `WatchSessions` stream: the pane map combined with the newest
//! process frame, sent once per interval and also as soon as the map changes
//! (so a closed pane disappears without waiting for the next interval).

use std::time::Duration;

use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::Status;

use super::processes::due;
use crate::pb::SessionsSnapshot;
use crate::sampler::unix_ms_now;
use crate::sessions::{SessionSubscription, snapshot};

/// Starts a task that sends snapshots until the client goes away. The task
/// holds the subscription, so tracking stops when the last client leaves.
pub fn stream(
    subscription: SessionSubscription,
    interval: Duration,
) -> ReceiverStream<Result<SessionsSnapshot, Status>> {
    let (tx, rx) = mpsc::channel(2);
    tokio::spawn(async move {
        let mut frames = subscription.processes().receiver();
        let mut views = subscription.views();
        let mut last_sent = None;
        let mut last_seq = None;
        loop {
            let frame = frames.borrow_and_update().clone();
            let view = views.borrow_and_update().clone();
            if let (Some(frame), Some(view)) = (frame, view) {
                let map_changed = last_seq != Some(view.seq);
                if map_changed || due(last_sent, frame.at, interval) {
                    let s = snapshot::build(
                        &view.map,
                        &frame.table,
                        view.status.clone(),
                        unix_ms_now(),
                    );
                    (last_sent, last_seq) = (Some(frame.at), Some(view.seq));
                    if tx.send(Ok(s)).await.is_err() {
                        break;
                    }
                }
            }
            tokio::select! {
                () = tx.closed() => break,
                changed = frames.changed() => if changed.is_err() {
                    tracing::info!("the process sampler went away; ending a WatchSessions stream");
                    break;
                },
                changed = views.changed() => if changed.is_err() {
                    tracing::info!("session tracking stopped; ending a WatchSessions stream");
                    break;
                },
            }
        }
        drop(subscription);
        tracing::debug!("a WatchSessions stream ended");
    });
    ReceiverStream::new(rx)
}
