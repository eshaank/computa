//! Declarations for the few system functions that the `libc` and
//! `core-foundation` crates do not provide (or mark deprecated).

#![allow(non_camel_case_types, non_upper_case_globals)]

use core_foundation::array::CFArrayRef;
use core_foundation::base::{CFAllocatorRef, CFTypeRef};
use core_foundation::dictionary::{CFDictionaryRef, CFMutableDictionaryRef};
use core_foundation::string::CFStringRef;

pub type mach_port_t = libc::mach_port_t;
pub type io_object_t = mach_port_t;
pub type io_iterator_t = io_object_t;
pub type io_registry_entry_t = io_object_t;
pub type IOOptionBits = u32;

/// `kIOMainPortDefault`: the default main port is the null port.
pub const kIOMainPortDefault: mach_port_t = 0;

/// The registry plane that holds drivers and their providers.
pub const kIOServicePlane: &[u8] = b"IOService\0";

/// `mach_timebase_info_data_t`: nanoseconds = Mach ticks * numer / denom.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct mach_timebase_info_data_t {
    pub numer: u32,
    pub denom: u32,
}

unsafe extern "C" {
    /// `libc` marks this deprecated in favour of `mach2`; it is stable API.
    pub fn mach_timebase_info(info: *mut mach_timebase_info_data_t) -> libc::kern_return_t;
    /// `libc` marks this deprecated in favour of `mach2`; it is stable API.
    pub fn mach_host_self() -> mach_port_t;
    /// The task's own port; `mach_task_self()` in C is a macro reading this.
    pub static mach_task_self_: mach_port_t;
}

#[link(name = "IOKit", kind = "framework")]
unsafe extern "C" {
    pub fn IOServiceMatching(name: *const libc::c_char) -> CFMutableDictionaryRef;
    pub fn IOServiceGetMatchingServices(
        main_port: mach_port_t,
        matching: CFDictionaryRef,
        existing: *mut io_iterator_t,
    ) -> libc::kern_return_t;
    pub fn IOIteratorNext(iterator: io_iterator_t) -> io_object_t;
    pub fn IOObjectRelease(object: io_object_t) -> libc::kern_return_t;
    pub fn IORegistryEntryCreateCFProperty(
        entry: io_registry_entry_t,
        key: CFStringRef,
        allocator: CFAllocatorRef,
        options: IOOptionBits,
    ) -> CFTypeRef;
    pub fn IORegistryEntryGetParentEntry(
        entry: io_registry_entry_t,
        plane: *const libc::c_char,
        parent: *mut io_registry_entry_t,
    ) -> libc::kern_return_t;
    pub fn IORegistryEntryFromPath(
        main_port: mach_port_t,
        path: *const libc::c_char,
    ) -> io_registry_entry_t;
    pub fn IORegistryEntryGetChildIterator(
        entry: io_registry_entry_t,
        plane: *const libc::c_char,
        iterator: *mut io_iterator_t,
    ) -> libc::kern_return_t;

    pub fn IOPSCopyPowerSourcesInfo() -> CFTypeRef;
    pub fn IOPSCopyPowerSourcesList(blob: CFTypeRef) -> CFArrayRef;
    pub fn IOPSGetPowerSourceDescription(blob: CFTypeRef, source: CFTypeRef) -> CFDictionaryRef;
}

#[link(name = "SystemConfiguration", kind = "framework")]
unsafe extern "C" {
    /// The Bonjour name, for example "Eshaans-MacBook-Pro". A null store
    /// opens a temporary session. Follows the create rule.
    pub fn SCDynamicStoreCopyLocalHostName(store: CFTypeRef) -> CFStringRef;
}

/// The host port, fetched once: every `mach_host_self` call adds a port
/// reference, so calling it each tick would leak.
pub fn host_port() -> mach_port_t {
    static PORT: std::sync::OnceLock<mach_port_t> = std::sync::OnceLock::new();
    // SAFETY: `mach_host_self` has no preconditions.
    *PORT.get_or_init(|| unsafe { mach_host_self() })
}
