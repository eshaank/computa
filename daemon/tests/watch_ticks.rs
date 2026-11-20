//! Starts the real server on a free port and reads the tick stream over gRPC.

use std::time::Duration;

use tokio::net::TcpListener;
use tokio::sync::oneshot;

use computad::pb::WatchTicksRequest;
use computad::pb::monitor_client::MonitorClient;
use computad::rpc;

const TICKS_TO_READ: u64 = 5;

#[tokio::test]
async fn ticks_arrive_in_order_at_the_requested_interval() {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind a free port");
    let addr = listener.local_addr().expect("read the bound address");
    let (stop, stopped) = oneshot::channel::<()>();
    let server = tokio::spawn(rpc::serve(listener, async {
        // Either a send or a dropped sender means the test is over.
        let _ = stopped.await;
    }));

    let mut client = MonitorClient::connect(format!("http://{addr}"))
        .await
        .expect("connect to the daemon");
    let mut ticks = client
        .watch_ticks(WatchTicksRequest { interval_ms: 100 })
        .await
        .expect("start the tick stream")
        .into_inner();

    let started = tokio::time::Instant::now();
    for expected in 1..=TICKS_TO_READ {
        let tick = tokio::time::timeout(Duration::from_secs(2), ticks.message())
            .await
            .expect("a tick within 2 seconds")
            .expect("no stream error")
            .expect("the stream stays open");
        assert_eq!(tick.sequence, expected);
        assert!(
            (0.0..=100.0).contains(&tick.value),
            "value was {}",
            tick.value
        );
    }
    // The first tick is immediate, so five ticks span four 100 ms intervals.
    let elapsed = started.elapsed();
    assert!(
        elapsed >= Duration::from_millis(350),
        "ticks came too fast: {elapsed:?}"
    );
    assert!(
        elapsed < Duration::from_millis(1_500),
        "ticks came too slowly: {elapsed:?}"
    );

    drop(ticks);
    stop.send(()).expect("the server is still running");
    server
        .await
        .expect("the server task did not panic")
        .expect("the server shut down cleanly");
}
