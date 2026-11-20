//! Disk read and write rates from IOKit block storage statistics.

use std::time::Instant;

use super::iokit::{IoObject, as_dict, as_i64, dict_get};
use super::log_once::LogOnce;
use super::rate::per_second;
use crate::pb::DiskActivity;

/// Bytes read and written since boot, summed over physical disks.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DiskTotals {
    pub read: u64,
    pub written: u64,
}

/// Disk images report "Virtual Interface". Their I/O also reaches the
/// physical disk that holds the image file, so counting them would count
/// those bytes twice.
const VIRTUAL_INTERCONNECT: &str = "Virtual Interface";

fn is_virtual(driver: &IoObject) -> bool {
    driver
        .parent()
        .and_then(|device| device.property("Protocol Characteristics"))
        .and_then(|v| as_dict(&v))
        .and_then(|d| dict_get(&d, "Physical Interconnect"))
        .and_then(|v| v.downcast::<core_foundation::string::CFString>())
        .is_some_and(|s| s == VIRTUAL_INTERCONNECT)
}

fn read_totals() -> anyhow::Result<DiskTotals> {
    let mut totals = DiskTotals::default();
    for driver in IoObject::matching(c"IOBlockStorageDriver")? {
        if is_virtual(&driver) {
            continue;
        }
        let Some(stats) = driver.property("Statistics").and_then(|v| as_dict(&v)) else {
            tracing::debug!("a block storage driver has no Statistics; skipping it");
            continue;
        };
        let get = |key| dict_get(&stats, key).and_then(|v| as_i64(&v)).unwrap_or(0);
        totals.read += u64::try_from(get("Bytes (Read)")).unwrap_or(0);
        totals.written += u64::try_from(get("Bytes (Write)")).unwrap_or(0);
    }
    Ok(totals)
}

/// Turns cumulative disk counters into rates.
#[derive(Debug)]
pub struct DiskSampler {
    prev: Option<(Instant, DiskTotals)>,
    log: LogOnce,
}

impl DiskSampler {
    pub fn new() -> Self {
        Self {
            prev: None,
            log: LogOnce::new("disk activity"),
        }
    }

    pub fn sample(&mut self, now: Instant) -> DiskActivity {
        let Some(cur) = self.log.check(read_totals()) else {
            self.prev = None;
            return DiskActivity::default();
        };
        let activity = match self.prev {
            Some((then, prev)) => {
                let secs = now.duration_since(then).as_secs_f64();
                DiskActivity {
                    read_bytes_per_sec: per_second(prev.read, cur.read, secs),
                    write_bytes_per_sec: per_second(prev.written, cur.written, secs),
                }
            }
            None => DiskActivity::default(),
        };
        self.prev = Some((now, cur));
        activity
    }
}
