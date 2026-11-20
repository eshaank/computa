//! Reads interface byte counters and addresses from the kernel.

use std::collections::BTreeMap;
use std::ffi::CStr;
use std::net::{Ipv4Addr, Ipv6Addr};

use anyhow::bail;

/// Byte counters of one interface, from its 64-bit `if_data64`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Counters {
    pub rx: u64,
    pub tx: u64,
    /// Whether the interface's traffic belongs in the machine's totals.
    pub in_totals: bool,
}

const IFT_ETHER: u8 = 0x06;
const IFT_CELLULAR: u8 = 0xff;

/// Whether an interface's traffic belongs in the machine's totals.
///
/// Only Ethernet-type interfaces (wired, Wi-Fi) and cellular count. Loopback
/// never leaves the machine. Tunnels, such as a VPN's `utun`, and bridges
/// carry traffic that is also counted on the physical interface underneath,
/// so adding them would count it twice.
pub fn counts_toward_totals(flags: libc::c_int, if_type: u8) -> bool {
    flags & libc::IFF_LOOPBACK == 0 && matches!(if_type, IFT_ETHER | IFT_CELLULAR)
}

/// Counters for every interface, by name, from `sysctl NET_RT_IFLIST2`.
pub fn counters() -> anyhow::Result<BTreeMap<String, Counters>> {
    let buf = iflist2()?;
    let mut out = BTreeMap::new();
    let hdr = size_of::<libc::if_msghdr2>();
    let mut at = 0;
    while at + 4 <= buf.len() {
        let msg_len = usize::from(u16::from_ne_bytes([buf[at], buf[at + 1]]));
        if msg_len == 0 || at + msg_len > buf.len() {
            break;
        }
        let msg = &buf[at..at + msg_len];
        at += msg_len;
        if i32::from(msg[3]) != libc::RTM_IFINFO2 || msg.len() < hdr {
            continue;
        }
        // SAFETY: `msg` holds at least one if_msghdr2; read_unaligned copes
        // with the packed layout and any alignment.
        let info: libc::if_msghdr2 = unsafe { std::ptr::read_unaligned(msg.as_ptr().cast()) };
        let Some(name) = link_name(&msg[hdr..]) else {
            continue;
        };
        let data = info.ifm_data;
        out.insert(
            name,
            Counters {
                rx: data.ifi_ibytes,
                tx: data.ifi_obytes,
                in_totals: counts_toward_totals(info.ifm_flags, data.ifi_type),
            },
        );
    }
    Ok(out)
}

/// The interface name from the `sockaddr_dl` that follows the header:
/// sdl_nlen is at byte 5 and the name starts at byte 8.
fn link_name(sdl: &[u8]) -> Option<String> {
    let len = usize::from(*sdl.get(5)?);
    let raw = sdl.get(8..8 + len)?;
    (!raw.is_empty()).then(|| String::from_utf8_lossy(raw).into_owned())
}

fn iflist2() -> anyhow::Result<Vec<u8>> {
    let mut mib = [libc::CTL_NET, libc::PF_ROUTE, 0, 0, libc::NET_RT_IFLIST2, 0];
    let mut len: libc::size_t = 0;
    // SAFETY: a null buffer with a valid length pointer asks only for the size.
    let rc = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            6,
            std::ptr::null_mut(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        bail!(
            "sysctl NET_RT_IFLIST2 size: {}",
            std::io::Error::last_os_error()
        );
    }
    // Interfaces can appear between the two calls, so leave some room.
    len += len / 8 + 512;
    let mut buf = vec![0u8; len];
    // SAFETY: `buf` is `len` bytes long, and the kernel writes at most `len`.
    let rc = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            6,
            buf.as_mut_ptr().cast(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        bail!("sysctl NET_RT_IFLIST2: {}", std::io::Error::last_os_error());
    }
    buf.truncate(len);
    Ok(buf)
}

/// Whether an IPv6 address is link-local (fe80::/10).
pub fn is_link_local_v6(addr: &Ipv6Addr) -> bool {
    addr.segments()[0] & 0xffc0 == 0xfe80
}

/// Addresses of interfaces that are up and not loopback, by name. IPv6
/// link-local addresses are left out.
pub fn addresses() -> anyhow::Result<BTreeMap<String, Vec<String>>> {
    let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
    // SAFETY: `head` is a valid out pointer; the list is freed below.
    if unsafe { libc::getifaddrs(&mut head) } != 0 {
        bail!("getifaddrs: {}", std::io::Error::last_os_error());
    }
    let mut out: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut cur = head;
    while !cur.is_null() {
        // SAFETY: `cur` is a node of the list getifaddrs returned, still live.
        let ifa = unsafe { &*cur };
        cur = ifa.ifa_next;
        let flags = ifa.ifa_flags as libc::c_int;
        if flags & libc::IFF_UP == 0 || flags & libc::IFF_LOOPBACK != 0 || ifa.ifa_addr.is_null() {
            continue;
        }
        // SAFETY: `ifa_addr` is non-null and points at a sockaddr of its family.
        let Some(addr) = (unsafe { format_addr(ifa.ifa_addr) }) else {
            continue;
        };
        // SAFETY: `ifa_name` is a NUL-terminated string owned by the list.
        let name = unsafe { CStr::from_ptr(ifa.ifa_name) }
            .to_string_lossy()
            .into_owned();
        out.entry(name).or_default().push(addr);
    }
    // SAFETY: frees the list getifaddrs allocated; no references remain.
    unsafe { libc::freeifaddrs(head) };
    Ok(out)
}

/// Formats an IPv4 or non-link-local IPv6 address.
///
/// # Safety
///
/// `sa` must point at a valid sockaddr whose `sa_family` matches its layout.
unsafe fn format_addr(sa: *const libc::sockaddr) -> Option<String> {
    // SAFETY: the caller guarantees `sa` is valid and typed by its family.
    unsafe {
        match i32::from((*sa).sa_family) {
            libc::AF_INET => {
                let sin = &*sa.cast::<libc::sockaddr_in>();
                Some(Ipv4Addr::from(u32::from_be(sin.sin_addr.s_addr)).to_string())
            }
            libc::AF_INET6 => {
                let sin6 = &*sa.cast::<libc::sockaddr_in6>();
                let ip = Ipv6Addr::from(sin6.sin6_addr.s6_addr);
                (!is_link_local_v6(&ip)).then(|| ip.to_string())
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_physical_interfaces_count_toward_totals() {
        const IFT_OTHER: u8 = 0x01; // utun, the type VPN tunnels use
        const IFT_BRIDGE: u8 = 0xd1;
        assert!(counts_toward_totals(libc::IFF_UP, IFT_ETHER));
        assert!(counts_toward_totals(libc::IFF_UP, IFT_CELLULAR));
        assert!(!counts_toward_totals(libc::IFF_UP, IFT_OTHER));
        assert!(!counts_toward_totals(libc::IFF_UP, IFT_BRIDGE));
        assert!(!counts_toward_totals(
            libc::IFF_UP | libc::IFF_LOOPBACK,
            IFT_ETHER
        ));
    }

    #[test]
    fn link_local_v6_is_detected() {
        assert!(is_link_local_v6(&"fe80::1".parse().unwrap()));
        assert!(is_link_local_v6(&"febf::1".parse().unwrap()));
        assert!(!is_link_local_v6(&"2001:db8::1".parse().unwrap()));
        assert!(!is_link_local_v6(&"fd00::1".parse().unwrap()));
    }

    #[test]
    fn link_name_reads_sockaddr_dl() {
        let sdl = [20, 18, 4, 0, 6, 3, 6, 0, b'e', b'n', b'0', 1, 2, 3];
        assert_eq!(link_name(&sdl).as_deref(), Some("en0"));
        assert_eq!(link_name(&sdl[..9]), None);
    }
}
