//! Mounted volumes a person would recognise, with their capacity.

use std::collections::HashMap;
use std::ffi::{CStr, CString};

use anyhow::bail;

use super::log_once::LogOnce;
use crate::pb::Volume;

/// Mount points under these prefixes are the system's own, never a person's.
const HIDDEN_PREFIXES: &[&str] = &[
    "/System/Volumes/",
    "/dev",
    "/Library/Developer/CoreSimulator/",
    "/private/var/",
    "/.",
];

/// File systems that are never storage a person would recognise.
const HIDDEN_FS_TYPES: &[&str] = &["devfs", "autofs", "nullfs", "fdesc"];

/// One entry from the mount table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mount {
    pub mount_point: String,
    pub fs_type: String,
    pub dont_browse: bool,
}

/// Whether `mount` belongs in the volume list. The startup volume `/` is
/// always kept; otherwise anything Finder would hide is skipped.
pub fn is_visible(mount: &Mount) -> bool {
    if mount.mount_point == "/" {
        return true;
    }
    !mount.dont_browse
        && !HIDDEN_FS_TYPES.contains(&mount.fs_type.as_str())
        && !HIDDEN_PREFIXES
            .iter()
            .any(|p| mount.mount_point.starts_with(p))
}

/// Total, used and available bytes from a `statfs` result. On APFS `/` is
/// the sealed system volume, but its available count is the whole
/// container's free space, so `used` covers every volume in the container.
pub fn capacity(blocks: u64, available_blocks: u64, block_size: u64) -> (u64, u64, u64) {
    let total = blocks.saturating_mul(block_size);
    let available = available_blocks.saturating_mul(block_size).min(total);
    (total, total - available, available)
}

fn c_chars(raw: &[libc::c_char]) -> String {
    let bytes: Vec<u8> = raw
        .iter()
        .take_while(|&&c| c != 0)
        .map(|&c| c as u8)
        .collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

/// The mount table, without waiting on any file system to answer.
fn mount_table() -> anyhow::Result<Vec<libc::statfs>> {
    // SAFETY: a null buffer asks only for the number of mounts.
    let count = unsafe { libc::getfsstat(std::ptr::null_mut(), 0, libc::MNT_NOWAIT) };
    if count < 0 {
        bail!("getfsstat: {}", std::io::Error::last_os_error());
    }
    let room = count as usize + 4;
    // SAFETY: statfs is plain data; all-zero is a valid value.
    let mut buf: Vec<libc::statfs> = vec![unsafe { std::mem::zeroed() }; room];
    let bytes = (room * size_of::<libc::statfs>()) as libc::c_int;
    // SAFETY: `buf` holds `room` entries and `bytes` says exactly that.
    let got = unsafe { libc::getfsstat(buf.as_mut_ptr(), bytes, libc::MNT_NOWAIT) };
    if got < 0 {
        bail!("getfsstat: {}", std::io::Error::last_os_error());
    }
    buf.truncate(got as usize);
    Ok(buf)
}

/// Fresh numbers for a local volume. `MNT_NOWAIT` may return cached counts.
fn refresh(mount_point: &str) -> anyhow::Result<libc::statfs> {
    let path = CString::new(mount_point)?;
    // SAFETY: statfs is plain data; all-zero is a valid value.
    let mut out: libc::statfs = unsafe { std::mem::zeroed() };
    // SAFETY: `path` is NUL-terminated and `out` is a valid out pointer.
    if unsafe { libc::statfs(path.as_ptr(), &mut out) } != 0 {
        bail!("statfs {mount_point}: {}", std::io::Error::last_os_error());
    }
    Ok(out)
}

/// Reads the volume list each tick and remembers volume names.
#[derive(Debug)]
pub struct VolumeSampler {
    names: HashMap<String, String>,
    table_log: LogOnce,
    refresh_log: LogOnce,
}

impl VolumeSampler {
    pub fn new() -> Self {
        Self {
            names: HashMap::new(),
            table_log: LogOnce::new("mount table"),
            refresh_log: LogOnce::new("volume capacity"),
        }
    }

    pub fn sample(&mut self) -> Vec<Volume> {
        let Some(table) = self.table_log.check(mount_table()) else {
            return Vec::new();
        };
        let mut volumes: Vec<Volume> = Vec::new();
        for entry in table {
            let mount = Mount {
                mount_point: c_chars(&entry.f_mntonname),
                fs_type: c_chars(&entry.f_fstypename),
                dont_browse: entry.f_flags & libc::MNT_DONTBROWSE as u32 != 0,
            };
            if !is_visible(&mount) || volumes.iter().any(|v| v.mount_point == mount.mount_point) {
                continue;
            }
            let local = entry.f_flags & libc::MNT_LOCAL as u32 != 0;
            let stats = if local {
                self.refresh_log
                    .check(refresh(&mount.mount_point))
                    .unwrap_or(entry)
            } else {
                entry
            };
            let (total, used, available) =
                capacity(stats.f_blocks, stats.f_bavail, u64::from(stats.f_bsize));
            volumes.push(Volume {
                name: self.name_of(&mount.mount_point),
                mount_point: mount.mount_point,
                total_bytes: total,
                used_bytes: used,
                available_bytes: available,
            });
        }
        volumes.sort_by_key(|v| v.mount_point != "/");
        self.names
            .retain(|k, _| volumes.iter().any(|v| &v.mount_point == k));
        volumes
    }

    fn name_of(&mut self, mount_point: &str) -> String {
        if let Some(name) = self.names.get(mount_point) {
            return name.clone();
        }
        let name = volume_name(mount_point).unwrap_or_else(|error| {
            tracing::warn!(
                mount_point,
                error = format!("{error:#}"),
                "could not read volume name; using the folder name"
            );
            fallback_name(mount_point)
        });
        self.names.insert(mount_point.to_owned(), name.clone());
        name
    }
}

/// The last part of the mount point, for when the volume has no label.
pub fn fallback_name(mount_point: &str) -> String {
    mount_point
        .rsplit('/')
        .find(|s| !s.is_empty())
        .unwrap_or(mount_point)
        .to_owned()
}

/// The volume's label, for example "Macintosh HD" for `/`.
fn volume_name(mount_point: &str) -> anyhow::Result<String> {
    let path = CString::new(mount_point)?;
    let mut request = libc::attrlist {
        bitmapcount: libc::ATTR_BIT_MAP_COUNT,
        reserved: 0,
        commonattr: 0,
        volattr: libc::ATTR_VOL_INFO | libc::ATTR_VOL_NAME,
        dirattr: 0,
        fileattr: 0,
        forkattr: 0,
    };
    // The reply is a u32 length, then an attrreference (i32 offset from the
    // reference itself, u32 length), then the name bytes.
    let mut buf = [0u8; 4 + 8 + 1024];
    // SAFETY: `path` is NUL-terminated, `request` is valid, and `buf` is
    // writable for `buf.len()` bytes.
    let rc = unsafe {
        libc::getattrlist(
            path.as_ptr(),
            (&raw mut request).cast(),
            buf.as_mut_ptr().cast(),
            buf.len(),
            0,
        )
    };
    if rc != 0 {
        bail!(
            "getattrlist {mount_point}: {}",
            std::io::Error::last_os_error()
        );
    }
    let offset = i32::from_ne_bytes([buf[4], buf[5], buf[6], buf[7]]);
    let len = u32::from_ne_bytes([buf[8], buf[9], buf[10], buf[11]]) as usize;
    let start = usize::try_from(4 + i64::from(offset)).unwrap_or(usize::MAX);
    let Some(raw) = buf.get(start..start.saturating_add(len)) else {
        bail!("getattrlist {mount_point}: name out of bounds");
    };
    let name = CStr::from_bytes_until_nul(raw).map_or_else(
        |_| String::from_utf8_lossy(raw).into_owned(),
        |c| c.to_string_lossy().into_owned(),
    );
    if name.is_empty() {
        bail!("getattrlist {mount_point}: empty name");
    }
    Ok(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(mount_point: &str, fs_type: &str, dont_browse: bool) -> Mount {
        Mount {
            mount_point: mount_point.into(),
            fs_type: fs_type.into(),
            dont_browse,
        }
    }

    #[test]
    fn keeps_startup_and_user_volumes_only() {
        assert!(is_visible(&m("/", "apfs", false)));
        assert!(is_visible(&m("/Volumes/Backup", "apfs", false)));
        assert!(is_visible(&m("/Volumes/share", "smbfs", false)));
        assert!(!is_visible(&m("/System/Volumes/Data", "apfs", true)));
        assert!(!is_visible(&m(
            "/System/Volumes/Update/mnt1",
            "apfs",
            false
        )));
        assert!(!is_visible(&m("/dev", "devfs", true)));
        assert!(!is_visible(&m("/Volumes/Recovery", "apfs", true)));
        assert!(!is_visible(&m(
            "/Library/Developer/CoreSimulator/Volumes/iOS",
            "apfs",
            false
        )));
    }

    #[test]
    fn used_is_total_minus_available() {
        let (total, used, available) = capacity(1000, 250, 4096);
        assert_eq!((total, used, available), (4_096_000, 3_072_000, 1_024_000));
        assert_eq!(capacity(10, 20, 1), (10, 0, 10));
    }

    #[test]
    fn fallback_name_is_last_component() {
        assert_eq!(fallback_name("/Volumes/My Disk"), "My Disk");
        assert_eq!(fallback_name("/"), "/");
    }
}
