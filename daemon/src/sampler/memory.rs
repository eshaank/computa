//! Physical memory, swap and memory pressure.

use std::mem::size_of;

use anyhow::bail;

use super::log_once::LogOnce;
use super::{ffi, sysctl};
use crate::pb::{Memory, MemoryPressure};

/// The page counts from `host_statistics64(HOST_VM_INFO64)` the formula uses.
#[derive(Debug, Clone, Copy, Default)]
pub struct PageCounts {
    /// `internal_page_count`: anonymous memory ("Anonymous pages" in vm_stat).
    pub internal: u64,
    /// `purgeable_count`: anonymous memory apps marked as discardable.
    pub purgeable: u64,
    /// `wire_count`: memory the kernel cannot page out.
    pub wired: u64,
    /// `compressor_page_count`: pages the compressor itself occupies
    /// ("Pages occupied by compressor"), not the pages stored in it.
    pub compressor: u64,
    /// `external_page_count`: file-backed pages ("File-backed pages").
    pub external: u64,
    /// `free_count`, which includes speculative pages.
    pub free: u64,
}

/// Memory in bytes, split the way Activity Monitor splits it.
///
/// The formula, in pages:
/// - app = internal - purgeable
/// - wired = wire_count
/// - compressed = compressor_page_count
/// - used = app + wired + compressed (Activity Monitor's "Memory Used")
/// - cached = external + purgeable (file cache plus discardable memory)
/// - free = free_count
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Breakdown {
    pub used: u64,
    pub app: u64,
    pub wired: u64,
    pub compressed: u64,
    pub cached: u64,
    pub free: u64,
}

pub fn breakdown(pages: &PageCounts, page_size: u64) -> Breakdown {
    let app = pages.internal.saturating_sub(pages.purgeable) * page_size;
    let wired = pages.wired * page_size;
    let compressed = pages.compressor * page_size;
    Breakdown {
        used: app + wired + compressed,
        app,
        wired,
        compressed,
        cached: (pages.external + pages.purgeable) * page_size,
        free: pages.free * page_size,
    }
}

/// Maps `kern.memorystatus_vm_pressure_level`, which uses the dispatch
/// levels: 1 normal, 2 warning, 4 critical.
pub fn pressure_from_level(level: i64) -> MemoryPressure {
    match level {
        1 => MemoryPressure::Normal,
        2 => MemoryPressure::Warning,
        4 => MemoryPressure::Critical,
        _ => MemoryPressure::Unspecified,
    }
}

fn read_pages() -> anyhow::Result<PageCounts> {
    // SAFETY: vm_statistics64 is plain integers; all-zero is a valid value.
    let mut stats: libc::vm_statistics64 = unsafe { std::mem::zeroed() };
    let mut count = (size_of::<libc::vm_statistics64>() / size_of::<libc::integer_t>())
        as libc::mach_msg_type_number_t;
    // SAFETY: `stats` has room for `count` integers, as the call requires.
    let rc = unsafe {
        libc::host_statistics64(
            ffi::host_port(),
            libc::HOST_VM_INFO64,
            (&raw mut stats).cast(),
            &mut count,
        )
    };
    if rc != libc::KERN_SUCCESS {
        bail!("host_statistics64(HOST_VM_INFO64) failed with {rc}");
    }
    Ok(PageCounts {
        internal: u64::from(stats.internal_page_count),
        purgeable: u64::from(stats.purgeable_count),
        wired: u64::from(stats.wire_count),
        compressor: u64::from(stats.compressor_page_count),
        external: u64::from(stats.external_page_count),
        free: u64::from(stats.free_count),
    })
}

/// Reads memory each tick. Total memory and the page size are fixed.
#[derive(Debug)]
pub struct MemorySampler {
    total: u64,
    page_size: u64,
    pages_log: LogOnce,
    swap_log: LogOnce,
    pressure_log: LogOnce,
}

impl MemorySampler {
    pub fn new(total: u64) -> Self {
        let mut page_log = LogOnce::new("page size");
        let page_size = page_log
            .check(sysctl::int("hw.pagesize"))
            .and_then(|v| u64::try_from(v).ok())
            .unwrap_or(16_384);
        Self {
            total,
            page_size,
            pages_log: LogOnce::new("memory pages"),
            swap_log: LogOnce::new("swap usage"),
            pressure_log: LogOnce::new("memory pressure"),
        }
    }

    pub fn sample(&mut self) -> Memory {
        let pages = self.pages_log.check(read_pages()).unwrap_or_default();
        let b = breakdown(&pages, self.page_size);
        let swap = self
            .swap_log
            .check(sysctl::value::<libc::xsw_usage>("vm.swapusage"));
        let level = self
            .pressure_log
            .check(sysctl::int("kern.memorystatus_vm_pressure_level"));
        Memory {
            total_bytes: self.total,
            used_bytes: b.used,
            app_bytes: b.app,
            wired_bytes: b.wired,
            compressed_bytes: b.compressed,
            cached_bytes: b.cached,
            free_bytes: b.free,
            swap_used_bytes: swap.map_or(0, |s| s.xsu_used),
            swap_total_bytes: swap.map_or(0, |s| s.xsu_total),
            pressure: level.map_or(MemoryPressure::Unspecified, pressure_from_level) as i32,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formula_matches_activity_monitor() {
        // Page counts taken from a real `vm_stat` on a 16 KiB-page machine.
        let pages = PageCounts {
            internal: 428_801,
            purgeable: 4,
            wired: 253_011,
            compressor: 612_408,
            external: 217_311,
            free: 7_947,
        };
        let b = breakdown(&pages, 16_384);
        assert_eq!(b.app, 428_797 * 16_384);
        assert_eq!(b.wired, 253_011 * 16_384);
        assert_eq!(b.compressed, 612_408 * 16_384);
        assert_eq!(b.used, b.app + b.wired + b.compressed);
        assert_eq!(b.used, 1_294_216 * 16_384);
        assert_eq!(b.cached, 217_315 * 16_384);
    }

    #[test]
    fn purgeable_larger_than_internal_does_not_underflow() {
        let pages = PageCounts {
            internal: 1,
            purgeable: 5,
            ..PageCounts::default()
        };
        assert_eq!(breakdown(&pages, 4096).app, 0);
    }

    #[test]
    fn pressure_levels_map_to_the_enum() {
        assert_eq!(pressure_from_level(1), MemoryPressure::Normal);
        assert_eq!(pressure_from_level(2), MemoryPressure::Warning);
        assert_eq!(pressure_from_level(4), MemoryPressure::Critical);
        assert_eq!(pressure_from_level(3), MemoryPressure::Unspecified);
    }
}
