//! Safe wrappers over the IOKit registry calls the sampler needs.

use std::ffi::CStr;

use anyhow::{Context, bail};
use core_foundation::base::{CFType, TCFType, kCFAllocatorDefault};
use core_foundation::dictionary::CFDictionary;
use core_foundation::number::CFNumber;
use core_foundation::string::CFString;

use super::ffi;

/// An IOKit object that is released when dropped.
#[derive(Debug)]
pub struct IoObject(ffi::io_object_t);

impl Drop for IoObject {
    fn drop(&mut self) {
        // SAFETY: we own one reference to a non-null object (see `from_raw`).
        unsafe { ffi::IOObjectRelease(self.0) };
    }
}

impl IoObject {
    fn from_raw(raw: ffi::io_object_t) -> Option<Self> {
        (raw != 0).then_some(Self(raw))
    }

    /// The registry entry at `path`, for example `IODeviceTree:/cpus`.
    pub fn from_path(path: &CStr) -> anyhow::Result<Self> {
        // SAFETY: `path` is a valid NUL-terminated string.
        let raw = unsafe { ffi::IORegistryEntryFromPath(ffi::kIOMainPortDefault, path.as_ptr()) };
        Self::from_raw(raw).with_context(|| format!("no IOKit registry entry at {path:?}"))
    }

    /// Every service of class `class`.
    pub fn matching(class: &CStr) -> anyhow::Result<Vec<Self>> {
        // SAFETY: `class` is NUL-terminated. The matching dictionary is
        // consumed by IOServiceGetMatchingServices, so we do not release it.
        let mut iter: ffi::io_iterator_t = 0;
        let rc = unsafe {
            let matching = ffi::IOServiceMatching(class.as_ptr());
            if matching.is_null() {
                bail!("IOServiceMatching({class:?}) returned null");
            }
            ffi::IOServiceGetMatchingServices(ffi::kIOMainPortDefault, matching, &mut iter)
        };
        if rc != 0 {
            bail!("IOServiceGetMatchingServices({class:?}) failed with {rc:#x}");
        }
        Ok(Self(iter).drain())
    }

    /// The children of this entry in `plane` (a NUL-terminated name).
    pub fn children(&self, plane: &[u8]) -> anyhow::Result<Vec<Self>> {
        let mut iter: ffi::io_iterator_t = 0;
        // SAFETY: `plane` is a NUL-terminated byte string from `ffi`.
        let rc = unsafe {
            ffi::IORegistryEntryGetChildIterator(self.0, plane.as_ptr().cast(), &mut iter)
        };
        if rc != 0 {
            bail!("IORegistryEntryGetChildIterator failed with {rc:#x}");
        }
        Ok(Self(iter).drain())
    }

    /// The provider of this entry in the service plane.
    pub fn parent(&self) -> Option<Self> {
        let mut parent: ffi::io_registry_entry_t = 0;
        // SAFETY: `self.0` is a valid entry and `parent` is a valid out pointer.
        let rc = unsafe {
            ffi::IORegistryEntryGetParentEntry(
                self.0,
                ffi::kIOServicePlane.as_ptr().cast(),
                &mut parent,
            )
        };
        if rc == 0 {
            Self::from_raw(parent)
        } else {
            None
        }
    }

    /// The property `key`, if the entry has it.
    pub fn property(&self, key: &str) -> Option<CFType> {
        let key = CFString::new(key);
        // SAFETY: `self.0` is a valid entry; the result follows the create
        // rule, so wrapping it hands its reference to `CFType`.
        unsafe {
            let raw = ffi::IORegistryEntryCreateCFProperty(
                self.0,
                key.as_concrete_TypeRef(),
                kCFAllocatorDefault,
                0,
            );
            (!raw.is_null()).then(|| CFType::wrap_under_create_rule(raw))
        }
    }

    /// Takes every object from an iterator, then releases the iterator.
    fn drain(self) -> Vec<Self> {
        let mut out = Vec::new();
        // SAFETY: `self.0` is a valid iterator; each object returned is owned.
        while let Some(obj) = Self::from_raw(unsafe { ffi::IOIteratorNext(self.0) }) {
            out.push(obj);
        }
        out
    }
}

/// Looks up `key` in a CF dictionary that IOKit or IOPS returned.
pub fn dict_get(dict: &CFDictionary<CFString, CFType>, key: &str) -> Option<CFType> {
    dict.find(CFString::new(key)).map(|v| v.clone())
}

/// Reads a CF number as a 64-bit integer.
pub fn as_i64(value: &CFType) -> Option<i64> {
    value.downcast::<CFNumber>().and_then(|n| n.to_i64())
}

/// Reads a CF value as a dictionary with string keys.
pub fn as_dict(value: &CFType) -> Option<CFDictionary<CFString, CFType>> {
    value
        .downcast::<CFDictionary>()
        // SAFETY: IOKit property dictionaries have CFString keys.
        .map(|d| unsafe { CFDictionary::wrap_under_get_rule(d.as_concrete_TypeRef()) })
}
