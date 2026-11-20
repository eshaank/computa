//! Typed reads of `sysctl` values by name.

use std::ffi::CString;
use std::mem::{MaybeUninit, size_of};

use anyhow::{Context, bail};

/// Reads `name` into raw bytes.
pub fn bytes(name: &str) -> anyhow::Result<Vec<u8>> {
    let cname = CString::new(name).with_context(|| format!("sysctl name {name:?}"))?;
    let mut len: libc::size_t = 0;
    // SAFETY: a null buffer with a valid length pointer asks only for the size.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            std::ptr::null_mut(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        bail!("sysctl {name}: {}", std::io::Error::last_os_error());
    }
    let mut buf = vec![0u8; len];
    // SAFETY: `buf` is `len` bytes long, and the kernel writes at most `len`.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            buf.as_mut_ptr().cast(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        bail!("sysctl {name}: {}", std::io::Error::last_os_error());
    }
    buf.truncate(len);
    Ok(buf)
}

/// Reads a string value, without its trailing NUL.
pub fn string(name: &str) -> anyhow::Result<String> {
    let raw = bytes(name)?;
    let end = raw.iter().position(|&b| b == 0).unwrap_or(raw.len());
    Ok(String::from_utf8_lossy(&raw[..end]).into_owned())
}

/// Reads a fixed-size plain-data value such as an integer or a C struct.
///
/// `T` must be a type for which every bit pattern is valid (integers and
/// `#[repr(C)]` structs of integers).
pub fn value<T: Copy>(name: &str) -> anyhow::Result<T> {
    let cname = CString::new(name).with_context(|| format!("sysctl name {name:?}"))?;
    let mut out = MaybeUninit::<T>::zeroed();
    let mut len: libc::size_t = size_of::<T>();
    // SAFETY: `out` has room for `size_of::<T>()` bytes and `len` says so.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            out.as_mut_ptr().cast(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        bail!("sysctl {name}: {}", std::io::Error::last_os_error());
    }
    if len != size_of::<T>() {
        bail!(
            "sysctl {name}: expected {} bytes, got {len}",
            size_of::<T>()
        );
    }
    // SAFETY: the kernel filled all `size_of::<T>()` bytes (checked above),
    // and callers only use plain-data types valid for any bit pattern.
    Ok(unsafe { out.assume_init() })
}

/// Reads an integer that the kernel may store as 32 or 64 bits.
pub fn int(name: &str) -> anyhow::Result<i64> {
    let raw = bytes(name)?;
    match raw.len() {
        4 => Ok(i64::from(i32::from_ne_bytes([
            raw[0], raw[1], raw[2], raw[3],
        ]))),
        8 => {
            let mut b = [0u8; 8];
            b.copy_from_slice(&raw);
            Ok(i64::from_ne_bytes(b))
        }
        n => bail!("sysctl {name}: expected a 4- or 8-byte integer, got {n} bytes"),
    }
}
