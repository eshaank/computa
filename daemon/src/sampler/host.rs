//! Facts about the machine that do not change while the daemon runs.

use super::log_once::LogOnce;
use super::{ffi, sysctl, topology};
use crate::pb::{CoreKind, Host};
use core_foundation::base::TCFType;
use core_foundation::string::CFString;

/// The host facts, plus the per-core kinds the CPU sampler needs.
#[derive(Debug, Clone)]
pub struct HostFacts {
    pub host: Host,
    pub core_kinds: Vec<CoreKind>,
}

/// Strips the Bonjour ".local" suffix `gethostname` usually adds.
pub fn display_hostname(raw: &str) -> String {
    raw.strip_suffix(".local").unwrap_or(raw).to_owned()
}

/// The machine's local name as set in Sharing settings, falling back to
/// `gethostname`, which on many networks is a name the DHCP server assigned.
fn hostname() -> anyhow::Result<String> {
    // SAFETY: a null store is allowed; the result follows the create rule,
    // so wrapping it hands its reference to `CFString`.
    let local = unsafe {
        let raw = ffi::SCDynamicStoreCopyLocalHostName(std::ptr::null());
        (!raw.is_null()).then(|| CFString::wrap_under_create_rule(raw).to_string())
    };
    match local.filter(|name| !name.is_empty()) {
        Some(name) => Ok(name),
        None => {
            tracing::warn!("no local host name is set; using gethostname");
            unix_hostname()
        }
    }
}

fn unix_hostname() -> anyhow::Result<String> {
    let mut buf = [0u8; 256];
    // SAFETY: `buf` is writable for `buf.len()` bytes.
    if unsafe { libc::gethostname(buf.as_mut_ptr().cast(), buf.len()) } != 0 {
        anyhow::bail!("gethostname: {}", std::io::Error::last_os_error());
    }
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    Ok(display_hostname(&String::from_utf8_lossy(&buf[..end])))
}

fn boot_unix_ms() -> anyhow::Result<i64> {
    let tv: libc::timeval = sysctl::value("kern.boottime")?;
    Ok(tv.tv_sec * 1000 + i64::from(tv.tv_usec) / 1000)
}

fn text(metric: &'static str, result: anyhow::Result<String>) -> String {
    LogOnce::new(metric).check(result).unwrap_or_default()
}

/// Reads every host fact once. A fact that cannot be read is logged and
/// left empty or zero.
pub fn read(sample_interval_ms: u32, history_capacity: u32) -> HostFacts {
    let core_groups = LogOnce::new("core groups")
        .check(topology::core_groups())
        .unwrap_or_default();
    let core_kinds = topology::core_kinds(&core_groups);
    let os = text("os version", sysctl::string("kern.osproductversion"));
    let memory = LogOnce::new("memory size")
        .check(sysctl::int("hw.memsize"))
        .unwrap_or(0);
    let host = Host {
        hostname: text("hostname", hostname()),
        model: text("model", sysctl::string("hw.model")),
        chip: text("chip", sysctl::string("machdep.cpu.brand_string")),
        os_version: if os.is_empty() {
            os
        } else {
            format!("macOS {os}")
        },
        daemon_version: env!("CARGO_PKG_VERSION").to_owned(),
        memory_total_bytes: u64::try_from(memory).unwrap_or(0),
        core_groups,
        boot_unix_ms: LogOnce::new("boot time").check(boot_unix_ms()).unwrap_or(0),
        sample_interval_ms,
        history_capacity,
    };
    HostFacts { host, core_kinds }
}

#[cfg(test)]
mod tests {
    use super::display_hostname;

    #[test]
    fn local_suffix_is_removed() {
        assert_eq!(
            display_hostname("Morgans-MacBook-Pro.local"),
            "Morgans-MacBook-Pro"
        );
        assert_eq!(display_hostname("build-box"), "build-box");
    }
}
