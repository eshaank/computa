//! CPU usage from per-core tick counters, and load averages.

use anyhow::bail;

use super::ffi;
use super::log_once::LogOnce;
use crate::pb::{Core, CoreKind, Cpu};

/// Cumulative ticks one core has spent in each state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CoreTicks {
    pub user: u32,
    pub system: u32,
    pub idle: u32,
    pub nice: u32,
}

/// Busy shares over an interval, each 0..=100.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Usage {
    pub total: f64,
    pub user: f64,
    pub system: f64,
}

/// Ticks spent between two readings, counting nice time as user time.
#[derive(Debug, Clone, Copy, Default)]
struct Delta {
    user: u64,
    system: u64,
    idle: u64,
}

impl Delta {
    /// The counters are 32-bit and wrap, so the difference is taken modulo 2^32.
    fn between(prev: &CoreTicks, cur: &CoreTicks) -> Self {
        Self {
            user: u64::from(cur.user.wrapping_sub(prev.user))
                + u64::from(cur.nice.wrapping_sub(prev.nice)),
            system: u64::from(cur.system.wrapping_sub(prev.system)),
            idle: u64::from(cur.idle.wrapping_sub(prev.idle)),
        }
    }

    fn add(self, other: Self) -> Self {
        Self {
            user: self.user + other.user,
            system: self.system + other.system,
            idle: self.idle + other.idle,
        }
    }

    /// `total` is exactly `user + system`, so the parts add up.
    fn usage(self) -> Usage {
        let all = self.user + self.system + self.idle;
        if all == 0 {
            return Usage::default();
        }
        let pct = |ticks: u64| ticks as f64 * 100.0 / all as f64;
        let (user, system) = (pct(self.user), pct(self.system));
        Usage {
            total: user + system,
            user,
            system,
        }
    }
}

/// The usage of one core between two readings.
pub fn core_usage(prev: &CoreTicks, cur: &CoreTicks) -> Usage {
    Delta::between(prev, cur).usage()
}

/// The usage of all cores together between two readings. Cores missing
/// from `prev` are compared against zero.
pub fn total_usage(prev: &[CoreTicks], cur: &[CoreTicks]) -> Usage {
    cur.iter()
        .enumerate()
        .map(|(i, c)| Delta::between(prev.get(i).unwrap_or(&CoreTicks::default()), c))
        .fold(Delta::default(), Delta::add)
        .usage()
}

/// Reads the tick counters of every core.
fn read_ticks() -> anyhow::Result<Vec<CoreTicks>> {
    let mut count: libc::natural_t = 0;
    let mut info: libc::processor_info_array_t = std::ptr::null_mut();
    let mut info_len: libc::mach_msg_type_number_t = 0;
    // SAFETY: all out pointers are valid. On success the kernel hands us a
    // VM allocation of `info_len` integers, which we free below.
    let rc = unsafe {
        libc::host_processor_info(
            ffi::host_port(),
            libc::PROCESSOR_CPU_LOAD_INFO,
            &mut count,
            &mut info,
            &mut info_len,
        )
    };
    if rc != libc::KERN_SUCCESS {
        bail!("host_processor_info failed with {rc}");
    }
    let states = libc::CPU_STATE_MAX as usize;
    let len = (info_len as usize).min(count as usize * states);
    // SAFETY: `info` points at `info_len` integers (len <= info_len).
    let raw = unsafe { std::slice::from_raw_parts(info, len) };
    let at = |i: usize, s: libc::c_int| raw[i * states + s as usize] as u32;
    let ticks = (0..len / states)
        .map(|i| CoreTicks {
            user: at(i, libc::CPU_STATE_USER),
            system: at(i, libc::CPU_STATE_SYSTEM),
            idle: at(i, libc::CPU_STATE_IDLE),
            nice: at(i, libc::CPU_STATE_NICE),
        })
        .collect();
    let bytes = info_len as usize * size_of::<libc::integer_t>();
    // SAFETY: frees exactly the allocation the kernel gave us; `raw` is no
    // longer used. `mach_task_self_` is set before any Rust code runs.
    let rc =
        unsafe { libc::vm_deallocate(ffi::mach_task_self_, info as libc::vm_address_t, bytes) };
    if rc != libc::KERN_SUCCESS {
        tracing::error!(
            rc,
            "vm_deallocate of the CPU tick array failed; memory may leak"
        );
    }
    Ok(ticks)
}

/// Load averages over 1, 5 and 15 minutes.
fn load_averages() -> anyhow::Result<[f64; 3]> {
    let mut out = [0f64; 3];
    // SAFETY: `out` has room for the 3 values requested.
    let n = unsafe { libc::getloadavg(out.as_mut_ptr(), 3) };
    if n != 3 {
        bail!("getloadavg returned {n}");
    }
    Ok(out)
}

/// Turns tick counters into `Cpu` messages, remembering the last reading.
#[derive(Debug)]
pub struct CpuSampler {
    /// The kind of each core, by index.
    kinds: Vec<CoreKind>,
    /// The previous reading. It starts at zero, so the first sample shows
    /// the average since boot rather than nothing.
    prev: Vec<CoreTicks>,
    ticks_log: LogOnce,
    load_log: LogOnce,
}

impl CpuSampler {
    pub fn new(kinds: Vec<CoreKind>) -> Self {
        Self {
            kinds,
            prev: Vec::new(),
            ticks_log: LogOnce::new("cpu ticks"),
            load_log: LogOnce::new("load average"),
        }
    }

    pub fn sample(&mut self) -> Cpu {
        let load = self.load_log.check(load_averages()).unwrap_or_default();
        let mut cpu = Cpu {
            load_average_1m: load[0],
            load_average_5m: load[1],
            load_average_15m: load[2],
            ..Cpu::default()
        };
        let Some(cur) = self.ticks_log.check(read_ticks()) else {
            return cpu;
        };
        let total = total_usage(&self.prev, &cur);
        (cpu.usage_percent, cpu.user_percent, cpu.system_percent) =
            (total.total, total.user, total.system);
        cpu.cores = cur
            .iter()
            .enumerate()
            .map(|(i, c)| Core {
                index: i as u32,
                kind: self.kinds.get(i).copied().unwrap_or(CoreKind::Unspecified) as i32,
                usage_percent: core_usage(self.prev.get(i).unwrap_or(&CoreTicks::default()), c)
                    .total,
            })
            .collect();
        self.prev = cur;
        cpu
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(user: u32, system: u32, idle: u32, nice: u32) -> CoreTicks {
        CoreTicks {
            user,
            system,
            idle,
            nice,
        }
    }

    #[test]
    fn usage_from_tick_deltas() {
        let u = core_usage(&t(100, 50, 1000, 0), &t(130, 60, 1060, 0));
        assert!((u.user - 30.0).abs() < 1e-9);
        assert!((u.system - 10.0).abs() < 1e-9);
        assert!((u.total - 40.0).abs() < 1e-9);
    }

    #[test]
    fn nice_counts_as_user_and_parts_add_up() {
        let u = core_usage(&t(0, 0, 0, 0), &t(10, 20, 60, 10));
        assert!((u.user - 20.0).abs() < 1e-9);
        assert!((u.total - (u.user + u.system)).abs() < 1e-9);
    }

    #[test]
    fn no_elapsed_ticks_gives_zero_not_nan() {
        assert_eq!(core_usage(&t(5, 5, 5, 5), &t(5, 5, 5, 5)), Usage::default());
    }

    #[test]
    fn wrapped_counters_give_the_true_delta() {
        let u = core_usage(&t(u32::MAX - 9, 0, u32::MAX - 9, 0), &t(10, 0, 10, 0));
        assert!((u.total - 50.0).abs() < 1e-9, "{u:?}");
    }

    #[test]
    fn total_weights_cores_by_ticks() {
        let prev = [t(0, 0, 0, 0), t(0, 0, 0, 0)];
        let cur = [t(100, 0, 0, 0), t(0, 0, 100, 0)];
        let u = total_usage(&prev, &cur);
        assert!((u.total - 50.0).abs() < 1e-9);
        assert!(u.total >= 0.0 && u.total <= 100.0);
    }
}
