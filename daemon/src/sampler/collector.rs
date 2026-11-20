//! Takes one complete system sample from every metric source.

use std::time::{Instant, SystemTime, UNIX_EPOCH};

use super::battery::BatterySampler;
use super::cpu::CpuSampler;
use super::disk::DiskSampler;
use super::host::HostFacts;
use super::memory::MemorySampler;
use super::network::NetworkSampler;
use super::volumes::VolumeSampler;
use crate::pb::{HistoryPoint, SystemSample};

/// Holds each metric's previous reading, so rates can be computed.
#[derive(Debug)]
pub struct Collector {
    cpu: CpuSampler,
    memory: MemorySampler,
    volumes: VolumeSampler,
    disk: DiskSampler,
    network: NetworkSampler,
    battery: BatterySampler,
}

impl Collector {
    pub fn new(facts: &HostFacts) -> Self {
        Self {
            cpu: CpuSampler::new(facts.core_kinds.clone()),
            memory: MemorySampler::new(facts.host.memory_total_bytes),
            volumes: VolumeSampler::new(),
            disk: DiskSampler::new(),
            network: NetworkSampler::new(),
            battery: BatterySampler::new(),
        }
    }

    /// Reads every metric once. Never fails: a metric that cannot be read
    /// has been logged and is reported as zero or absent.
    pub fn sample(&mut self) -> SystemSample {
        let now = Instant::now();
        SystemSample {
            unix_ms: unix_ms_now(),
            cpu: Some(self.cpu.sample()),
            memory: Some(self.memory.sample()),
            volumes: self.volumes.sample(),
            disk_activity: Some(self.disk.sample(now)),
            network: Some(self.network.sample(now)),
            battery: self.battery.sample(now),
        }
    }
}

/// The current wall-clock time in milliseconds since the Unix epoch.
pub fn unix_ms_now() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => i64::try_from(d.as_millis()).unwrap_or(i64::MAX),
        Err(error) => {
            tracing::warn!(%error, "the system clock is before 1970; using time zero");
            0
        }
    }
}

/// The values of a sample that history keeps.
pub fn history_point(s: &SystemSample) -> HistoryPoint {
    let cpu = s.cpu.clone().unwrap_or_default();
    let mem = s.memory.unwrap_or_default();
    let net = s
        .network
        .as_ref()
        .map_or((0.0, 0.0), |n| (n.rx_bytes_per_sec, n.tx_bytes_per_sec));
    let disk = s.disk_activity.unwrap_or_default();
    HistoryPoint {
        unix_ms: s.unix_ms,
        cpu_usage_percent: cpu.usage_percent,
        cpu_user_percent: cpu.user_percent,
        cpu_system_percent: cpu.system_percent,
        memory_used_bytes: mem.used_bytes,
        memory_app_bytes: mem.app_bytes,
        memory_wired_bytes: mem.wired_bytes,
        memory_compressed_bytes: mem.compressed_bytes,
        swap_used_bytes: mem.swap_used_bytes,
        net_rx_bytes_per_sec: net.0,
        net_tx_bytes_per_sec: net.1,
        disk_read_bytes_per_sec: disk.read_bytes_per_sec,
        disk_write_bytes_per_sec: disk.write_bytes_per_sec,
    }
}
