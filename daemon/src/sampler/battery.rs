//! Battery charge and power source from IOKit power sources.

use std::time::{Duration, Instant};

use anyhow::bail;
use core_foundation::array::CFArray;
use core_foundation::base::{CFType, TCFType};
use core_foundation::boolean::CFBoolean;
use core_foundation::dictionary::CFDictionary;
use core_foundation::string::CFString;

use super::ffi;
use super::iokit::{as_i64, dict_get};
use super::log_once::LogOnce;
use crate::pb::{Battery, BatteryState};

/// Battery numbers change slowly; reading them every 10 s is enough.
const REFRESH: Duration = Duration::from_secs(10);

/// The fields of a power source description the daemon uses.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Reading {
    pub current_capacity: i64,
    pub max_capacity: i64,
    pub is_charging: bool,
    pub on_ac: bool,
    /// Minutes, or -1 while macOS is still working it out.
    pub time_to_empty: i64,
    pub time_to_full: i64,
}

/// Builds the `Battery` message from a power source reading.
pub fn battery_from(r: &Reading) -> Battery {
    let charge = if r.max_capacity > 0 {
        (r.current_capacity as f64 * 100.0 / r.max_capacity as f64).clamp(0.0, 100.0)
    } else {
        0.0
    };
    let state = match (r.is_charging, r.on_ac) {
        (true, _) => BatteryState::Charging,
        (false, true) => BatteryState::Full,
        (false, false) => BatteryState::Discharging,
    };
    let minutes = match state {
        BatteryState::Charging => r.time_to_full,
        BatteryState::Discharging => r.time_to_empty,
        _ => -1,
    };
    Battery {
        charge_percent: charge,
        state: state as i32,
        on_ac_power: r.on_ac,
        minutes_remaining: u32::try_from(minutes).ok(),
    }
}

/// Reads the internal battery, or `None` when the machine has none.
fn read() -> anyhow::Result<Option<Reading>> {
    // SAFETY: both calls follow the create rule; wrapping hands their
    // references to the CF wrappers, which release them on drop.
    let (blob, list) = unsafe {
        let blob = ffi::IOPSCopyPowerSourcesInfo();
        if blob.is_null() {
            bail!("IOPSCopyPowerSourcesInfo returned null");
        }
        let blob = CFType::wrap_under_create_rule(blob);
        let list = ffi::IOPSCopyPowerSourcesList(blob.as_CFTypeRef());
        if list.is_null() {
            bail!("IOPSCopyPowerSourcesList returned null");
        }
        (blob, CFArray::<CFType>::wrap_under_create_rule(list))
    };
    for source in list.iter() {
        // SAFETY: the description follows the get rule and lives as long as
        // `blob`; wrapping under the get rule retains it.
        let desc: CFDictionary<CFString, CFType> = unsafe {
            let raw =
                ffi::IOPSGetPowerSourceDescription(blob.as_CFTypeRef(), source.as_CFTypeRef());
            if raw.is_null() {
                continue;
            }
            CFDictionary::wrap_under_get_rule(raw)
        };
        if let Some(reading) = reading_from(&desc) {
            return Ok(Some(reading));
        }
    }
    Ok(None)
}

fn reading_from(desc: &CFDictionary<CFString, CFType>) -> Option<Reading> {
    let text = |key| {
        dict_get(desc, key)
            .and_then(|v| v.downcast::<CFString>())
            .map(|s| s.to_string())
    };
    if text("Type").as_deref() != Some("InternalBattery") {
        return None;
    }
    let int = |key| dict_get(desc, key).and_then(|v| as_i64(&v)).unwrap_or(-1);
    let flag = |key| {
        dict_get(desc, key)
            .and_then(|v| v.downcast::<CFBoolean>())
            .is_some_and(bool::from)
    };
    Some(Reading {
        current_capacity: int("Current Capacity"),
        max_capacity: int("Max Capacity"),
        is_charging: flag("Is Charging"),
        on_ac: text("Power Source State").as_deref() == Some("AC Power"),
        time_to_empty: int("Time to Empty"),
        time_to_full: int("Time to Full Charge"),
    })
}

/// Reads the battery at most every `REFRESH` and reuses the last value.
#[derive(Debug)]
pub struct BatterySampler {
    last: Option<Battery>,
    read_at: Option<Instant>,
    log: LogOnce,
}

impl BatterySampler {
    pub fn new() -> Self {
        Self {
            last: None,
            read_at: None,
            log: LogOnce::new("battery"),
        }
    }

    pub fn sample(&mut self, now: Instant) -> Option<Battery> {
        if self
            .read_at
            .is_none_or(|t| now.duration_since(t) >= REFRESH)
        {
            self.read_at = Some(now);
            self.last = self.log.check(read()).flatten().map(|r| battery_from(&r));
        }
        self.last
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(is_charging: bool, on_ac: bool, tte: i64, ttf: i64) -> Reading {
        Reading {
            current_capacity: 49,
            max_capacity: 100,
            is_charging,
            on_ac,
            time_to_empty: tte,
            time_to_full: ttf,
        }
    }

    #[test]
    fn discharging_reports_time_to_empty() {
        let b = battery_from(&r(false, false, 253, -1));
        assert_eq!(b.state, BatteryState::Discharging as i32);
        assert_eq!(b.minutes_remaining, Some(253));
        assert!((b.charge_percent - 49.0).abs() < 1e-9);
    }

    #[test]
    fn charging_reports_time_to_full_and_unknown_is_absent() {
        assert_eq!(
            battery_from(&r(true, true, -1, 40)).minutes_remaining,
            Some(40)
        );
        assert_eq!(battery_from(&r(true, true, -1, -1)).minutes_remaining, None);
    }

    #[test]
    fn plugged_in_and_not_charging_is_full() {
        let b = battery_from(&r(false, true, -1, 0));
        assert_eq!(b.state, BatteryState::Full as i32);
        assert!(b.on_ac_power);
        assert_eq!(b.minutes_remaining, None);
    }
}
