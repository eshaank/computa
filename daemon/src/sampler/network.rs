//! Network rates per interface and in total.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use super::log_once::LogOnce;
use super::netif::{self, Counters};
use super::rate::per_second;
use crate::pb::{Network, NetworkInterface};

/// Addresses change rarely; reading them every few seconds is enough.
const ADDRESS_REFRESH: Duration = Duration::from_secs(5);

/// Per-interface and total rates between two counter readings.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Rates {
    pub per_interface: BTreeMap<String, (f64, f64)>,
    pub rx_total: f64,
    pub tx_total: f64,
}

/// Rates for each interface in `cur`. An interface missing from `prev` is
/// new and gets zero. Totals cover the interfaces marked `in_totals`.
pub fn rates(
    prev: &BTreeMap<String, Counters>,
    cur: &BTreeMap<String, Counters>,
    secs: f64,
) -> Rates {
    let mut out = Rates::default();
    for (name, c) in cur {
        let (rx, tx) = prev.get(name).map_or((0.0, 0.0), |p| {
            (per_second(p.rx, c.rx, secs), per_second(p.tx, c.tx, secs))
        });
        if c.in_totals {
            out.rx_total += rx;
            out.tx_total += tx;
        }
        out.per_interface.insert(name.clone(), (rx, tx));
    }
    out
}

/// Reads counters each tick and turns them into a `Network` message.
#[derive(Debug)]
pub struct NetworkSampler {
    prev: Option<(Instant, BTreeMap<String, Counters>)>,
    addresses: BTreeMap<String, Vec<String>>,
    addresses_read: Option<Instant>,
    counters_log: LogOnce,
    addresses_log: LogOnce,
}

impl NetworkSampler {
    pub fn new() -> Self {
        Self {
            prev: None,
            addresses: BTreeMap::new(),
            addresses_read: None,
            counters_log: LogOnce::new("network counters"),
            addresses_log: LogOnce::new("network addresses"),
        }
    }

    pub fn sample(&mut self, now: Instant) -> Network {
        self.refresh_addresses(now);
        let Some(cur) = self.counters_log.check(netif::counters()) else {
            self.prev = None;
            return Network::default();
        };
        let rates = match &self.prev {
            Some((then, prev)) => rates(prev, &cur, now.duration_since(*then).as_secs_f64()),
            None => rates(&cur, &cur, 1.0),
        };
        let interfaces = self
            .addresses
            .iter()
            .filter(|(_, addrs)| !addrs.is_empty())
            .filter_map(|(name, addrs)| {
                let c = cur.get(name)?;
                let (rx, tx) = rates.per_interface.get(name).copied().unwrap_or_default();
                Some(NetworkInterface {
                    name: name.clone(),
                    addresses: addrs.clone(),
                    rx_bytes_per_sec: rx,
                    tx_bytes_per_sec: tx,
                    rx_bytes_total: c.rx,
                    tx_bytes_total: c.tx,
                })
            })
            .collect();
        self.prev = Some((now, cur));
        Network {
            rx_bytes_per_sec: rates.rx_total,
            tx_bytes_per_sec: rates.tx_total,
            interfaces,
        }
    }

    fn refresh_addresses(&mut self, now: Instant) {
        if self
            .addresses_read
            .is_some_and(|t| now.duration_since(t) < ADDRESS_REFRESH)
        {
            return;
        }
        self.addresses_read = Some(now);
        self.addresses = self
            .addresses_log
            .check(netif::addresses())
            .unwrap_or_default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(rx: u64, tx: u64, in_totals: bool) -> Counters {
        Counters { rx, tx, in_totals }
    }

    #[test]
    fn totals_cover_only_marked_interfaces_and_new_ones_start_at_zero() {
        let prev = BTreeMap::from([
            ("en0".into(), c(1000, 500, true)),
            ("lo0".into(), c(0, 0, false)),
            ("utun4".into(), c(100, 100, false)),
        ]);
        let cur = BTreeMap::from([
            ("en0".into(), c(3000, 1500, true)),
            ("lo0".into(), c(9000, 9000, false)),
            ("utun4".into(), c(1900, 500, false)),
            ("en7".into(), c(777, 777, true)),
        ]);
        let r = rates(&prev, &cur, 2.0);
        assert_eq!(r.per_interface["en0"], (1000.0, 500.0));
        assert_eq!(r.per_interface["lo0"], (4500.0, 4500.0));
        // A VPN tunnel keeps its own rate but stays out of the totals.
        assert_eq!(r.per_interface["utun4"], (900.0, 200.0));
        assert_eq!(r.per_interface["en7"], (0.0, 0.0));
        assert_eq!((r.rx_total, r.tx_total), (1000.0, 500.0));
    }

    #[test]
    fn reset_counter_gives_zero_rate() {
        let prev = BTreeMap::from([("en0".into(), c(5000, 5000, true))]);
        let cur = BTreeMap::from([("en0".into(), c(10, 10, true))]);
        assert_eq!(rates(&prev, &cur, 1.0).rx_total, 0.0);
    }
}
