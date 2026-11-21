//! The libproc and Mach calls that read one process, each wrapped in a
//! small safe function.

use std::io;
use std::mem::MaybeUninit;
use std::sync::OnceLock;

use crate::sampler::ffi;

/// What `proc_pid_rusage` reports for one process, CPU time in nanoseconds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RawUsage {
    pub cpu_ns: u64,
    pub footprint_bytes: u64,
    pub resident_bytes: u64,
}

/// Reads a process's usage. Fails with `EPERM` for processes owned by
/// another user and `ESRCH` for one that has exited.
pub fn rusage(pid: i32) -> io::Result<RawUsage> {
    let info = rusage_v4(pid)?;
    let (numer, denom) = timebase();
    let ticks = info.ri_user_time.saturating_add(info.ri_system_time);
    Ok(RawUsage {
        cpu_ns: mach_to_ns(ticks, numer, denom),
        footprint_bytes: info.ri_phys_footprint,
        resident_bytes: info.ri_resident_size,
    })
}

fn rusage_v4(pid: i32) -> io::Result<libc::rusage_info_v4> {
    let mut info = MaybeUninit::<libc::rusage_info_v4>::zeroed();
    // SAFETY: with flavor `RUSAGE_INFO_V4` the kernel writes one
    // `rusage_info_v4` into the buffer, which has exactly that size.
    let rc = unsafe { libc::proc_pid_rusage(pid, libc::RUSAGE_INFO_V4, info.as_mut_ptr().cast()) };
    if rc != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: the call succeeded and filled the struct, which holds only
    // integers; it was zeroed beforehand in any case.
    Ok(unsafe { info.assume_init() })
}

/// Where macOS keeps per-user temporary files. Chromium browsers run their
/// main process from a code-signing clone in there, so the kernel's path for
/// it is outside the installed app.
const TEMP_FOLDERS: &str = "/private/var/folders/";
/// Used if `kern.argmax` cannot be read; it is 1 MiB on current macOS.
const FALLBACK_ARGMAX: usize = 1 << 20;

/// The executable's full path, or `None` if it cannot be read (the kernel,
/// or a process that has exited). For an executable running from a
/// temporary copy, the path it was started with, when that is known.
pub fn path(pid: i32) -> Option<String> {
    let kernel = kernel_path(pid)?;
    if kernel.starts_with(TEMP_FOLDERS) {
        // Falls back to the kernel's path if the arguments cannot be read.
        if let Some(launched) = procargs(pid).as_deref().and_then(launch_path) {
            return Some(launched);
        }
    }
    Some(kernel)
}

fn kernel_path(pid: i32) -> Option<String> {
    let mut buf = vec![0u8; libc::PROC_PIDPATHINFO_MAXSIZE as usize];
    let len = u32::try_from(buf.len()).unwrap_or(u32::MAX);
    // SAFETY: `buf` is writable for `len` bytes and the kernel writes at most
    // that many, returning the count.
    let n = unsafe { libc::proc_pidpath(pid, buf.as_mut_ptr().cast(), len) };
    let n = usize::try_from(n).ok().filter(|&n| n > 0)?;
    buf.truncate(n);
    Some(String::from_utf8_lossy(&buf).into_owned())
}

/// The raw `KERN_PROCARGS2` block. Readable only for the user's own
/// processes; `None` otherwise or if the process has exited.
fn procargs(pid: i32) -> Option<Vec<u8>> {
    let mut buf = vec![0u8; argmax()];
    let mut len = buf.len();
    let mut mib = [libc::CTL_KERN, libc::KERN_PROCARGS2, pid];
    // SAFETY: `mib` holds 3 valid entries, `buf` is writable for `len` bytes
    // and the kernel writes at most that many, updating `len`.
    let rc = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            3,
            buf.as_mut_ptr().cast(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        return None;
    }
    buf.truncate(len);
    Some(buf)
}

fn argmax() -> usize {
    static ARGMAX: OnceLock<usize> = OnceLock::new();
    *ARGMAX.get_or_init(|| match crate::sampler::sysctl::int("kern.argmax") {
        Ok(n) => usize::try_from(n).unwrap_or(FALLBACK_ARGMAX),
        Err(error) => {
            tracing::warn!(
                error = format!("{error:#}"),
                "using a default argument size"
            );
            FALLBACK_ARGMAX
        }
    })
}

/// The path a program was started with, from a `KERN_PROCARGS2` block: a
/// 4-byte argument count, then that path, NUL-terminated. Only an absolute
/// path is useful.
pub fn launch_path(raw: &[u8]) -> Option<String> {
    let rest = raw.get(4..)?;
    let end = rest.iter().position(|&b| b == 0)?;
    let path = String::from_utf8_lossy(&rest[..end]);
    path.starts_with('/').then(|| path.into_owned())
}

/// The Mach timebase as (numer, denom): nanoseconds = ticks * numer / denom.
/// It is 1/1 on Intel and 125/3 on Apple Silicon.
pub fn timebase() -> (u32, u32) {
    static TIMEBASE: OnceLock<(u32, u32)> = OnceLock::new();
    *TIMEBASE.get_or_init(read_timebase)
}

fn read_timebase() -> (u32, u32) {
    let mut info = ffi::mach_timebase_info_data_t::default();
    // SAFETY: `info` is a valid, writable `mach_timebase_info_data_t`.
    let rc = unsafe { ffi::mach_timebase_info(&mut info) };
    if rc != 0 || info.numer == 0 || info.denom == 0 {
        tracing::error!(
            rc,
            numer = info.numer,
            denom = info.denom,
            "could not read the Mach timebase; process CPU figures assume nanoseconds"
        );
        return (1, 1);
    }
    (info.numer, info.denom)
}

/// Converts Mach absolute time units to nanoseconds without overflow.
pub fn mach_to_ns(ticks: u64, numer: u32, denom: u32) -> u64 {
    if denom == 0 {
        return ticks;
    }
    let ns = u128::from(ticks) * u128::from(numer) / u128::from(denom);
    u64::try_from(ns).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_silicon_ticks_are_41_and_two_thirds_ns() {
        assert_eq!(mach_to_ns(3, 125, 3), 125);
        assert_eq!(mach_to_ns(24_000_000, 125, 3), 1_000_000_000);
    }

    #[test]
    fn intel_timebase_is_identity() {
        assert_eq!(mach_to_ns(123_456_789, 1, 1), 123_456_789);
    }

    #[test]
    fn large_values_do_not_overflow() {
        let ns = mach_to_ns(u64::MAX / 2, 125, 3);
        assert_eq!(ns, u64::MAX);
        let year_ticks = 365 * 24 * 3600 * 24_000_000_u64;
        assert_eq!(
            mach_to_ns(year_ticks, 125, 3),
            365 * 24 * 3600 * 1_000_000_000
        );
    }

    #[test]
    fn own_usage_is_readable_and_converted() {
        let me = i32::try_from(std::process::id()).expect("pid fits");
        // Burn a little CPU so the reading is clearly above zero.
        let mut x = 0u64;
        for i in 0..5_000_000u64 {
            x = x.wrapping_add(i * i);
        }
        assert_ne!(x, 1);
        let u = rusage(me).expect("own usage readable");
        let reference = own_cpu_ns_from_getrusage();
        assert!(u.footprint_bytes > 0 && u.resident_bytes > 0);
        // `getrusage` reports in real time units. Read just after it, the
        // converted figure must be close; unconverted ticks on Apple Silicon
        // would be about 41x smaller.
        let ratio = u.cpu_ns as f64 / reference as f64;
        assert!(
            (0.8..1.5).contains(&ratio),
            "rusage {} ns vs getrusage {reference} ns",
            u.cpu_ns
        );
        assert!(path(me).is_some_and(|p| p.starts_with('/')));
    }

    #[test]
    fn launch_path_is_read_from_the_argument_block() {
        let mut raw = 2i32.to_ne_bytes().to_vec();
        raw.extend(b"/Applications/A.app/Contents/MacOS/A\0\0\0A\0-x\0");
        assert_eq!(
            launch_path(&raw).as_deref(),
            Some("/Applications/A.app/Contents/MacOS/A")
        );
        let mut relative = 1i32.to_ne_bytes().to_vec();
        relative.extend(b"./a\0");
        assert_eq!(launch_path(&relative), None);
        assert_eq!(launch_path(&[1, 0]), None);
        assert_eq!(launch_path(&[1, 0, 0, 0, b'/', b'x']), None, "no NUL");
    }

    #[test]
    fn own_launch_path_is_absolute() {
        let me = i32::try_from(std::process::id()).expect("pid fits");
        let raw = procargs(me).expect("own arguments readable");
        assert!(launch_path(&raw).is_some_and(|p| p.starts_with('/')));
    }

    fn own_cpu_ns_from_getrusage() -> u64 {
        let mut ru = MaybeUninit::<libc::rusage>::zeroed();
        // SAFETY: `ru` is a writable `rusage`.
        let rc = unsafe { libc::getrusage(libc::RUSAGE_SELF, ru.as_mut_ptr()) };
        assert_eq!(rc, 0);
        // SAFETY: the call succeeded and filled the struct.
        let ru = unsafe { ru.assume_init() };
        let ns = |t: libc::timeval| t.tv_sec as u64 * 1_000_000_000 + t.tv_usec as u64 * 1000;
        ns(ru.ru_utime) + ns(ru.ru_stime)
    }
}
