//! Which CPU cores are performance cores and which are efficiency cores.

use std::collections::BTreeMap;

use anyhow::Context;
use core_foundation::data::CFData;

use super::iokit::{IoObject, as_i64};
use super::sysctl;
use crate::pb::{CoreGroup, CoreKind};

/// Maps a perflevel name such as "Performance" to a core kind.
pub fn kind_from_name(name: &str) -> CoreKind {
    match name {
        "Performance" => CoreKind::Performance,
        "Efficiency" => CoreKind::Efficiency,
        _ => CoreKind::Unspecified,
    }
}

/// The core groups from `hw.perflevelN`, fastest first.
pub fn core_groups() -> anyhow::Result<Vec<CoreGroup>> {
    let levels = match sysctl::int("hw.nperflevels") {
        Ok(levels) => levels,
        Err(error) => {
            // Machines without perflevels (Intel) have one kind of core.
            tracing::info!(
                error = format!("{error:#}"),
                "no hw.nperflevels; reporting a single core group"
            );
            return single_group();
        }
    };
    (0..levels)
        .map(|level| {
            let name = sysctl::string(&format!("hw.perflevel{level}.name"))?;
            let count = sysctl::int(&format!("hw.perflevel{level}.logicalcpu"))?;
            Ok(CoreGroup {
                kind: kind_from_name(&name) as i32,
                core_count: u32::try_from(count).unwrap_or(0),
                name,
            })
        })
        .collect()
}

/// One group holding every logical CPU, for machines with one kind of core.
fn single_group() -> anyhow::Result<Vec<CoreGroup>> {
    let count = sysctl::int("hw.logicalcpu").context("reading hw.logicalcpu")?;
    Ok(vec![CoreGroup {
        kind: CoreKind::Unspecified as i32,
        name: "CPU".to_owned(),
        core_count: u32::try_from(count).unwrap_or(0),
    }])
}

/// The kind of each logical CPU, by index, from the device tree's
/// `cluster-type` ("P" or "E") and `logical-cpu-id` properties.
fn device_tree_kinds() -> anyhow::Result<BTreeMap<i64, CoreKind>> {
    let cpus = IoObject::from_path(c"IODeviceTree:/cpus")?;
    let mut out = BTreeMap::new();
    for cpu in cpus.children(b"IODeviceTree\0")? {
        let id = cpu
            .property("logical-cpu-id")
            .and_then(|v| as_i64(&v).or_else(|| data_u32(&v)));
        let kind = cpu
            .property("cluster-type")
            .and_then(|v| v.downcast::<CFData>())
            .map(|d| match d.bytes().first() {
                Some(b'P') => CoreKind::Performance,
                Some(b'E') => CoreKind::Efficiency,
                _ => CoreKind::Unspecified,
            });
        if let (Some(id), Some(kind)) = (id, kind) {
            out.insert(id, kind);
        }
    }
    Ok(out)
}

fn data_u32(value: &core_foundation::base::CFType) -> Option<i64> {
    let data = value.downcast::<CFData>()?;
    let b: [u8; 4] = data.bytes().get(..4)?.try_into().ok()?;
    Some(i64::from(u32::from_le_bytes(b)))
}

/// Whether a per-index kind map agrees with the group counts.
pub fn matches_groups(kinds: &[CoreKind], groups: &[CoreGroup]) -> bool {
    let total: u32 = groups.iter().map(|g| g.core_count).sum();
    kinds.len() == total as usize
        && groups
            .iter()
            .all(|g| kinds.iter().filter(|&&k| k as i32 == g.kind).count() == g.core_count as usize)
}

/// The fallback when the device tree cannot be read: Apple Silicon numbers
/// the slowest cores first, so assign groups from slowest to fastest.
pub fn kinds_slowest_first(groups: &[CoreGroup]) -> Vec<CoreKind> {
    groups
        .iter()
        .rev()
        .flat_map(|g| {
            let kind = CoreKind::try_from(g.kind).unwrap_or(CoreKind::Unspecified);
            std::iter::repeat_n(kind, g.core_count as usize)
        })
        .collect()
}

/// The kind of each core by index, checked against the group counts.
pub fn core_kinds(groups: &[CoreGroup]) -> Vec<CoreKind> {
    if let [only] = groups {
        let kind = CoreKind::try_from(only.kind).unwrap_or(CoreKind::Unspecified);
        return vec![kind; only.core_count as usize];
    }
    match device_tree_kinds() {
        Ok(map) => {
            let kinds: Vec<CoreKind> = map.into_values().collect();
            if matches_groups(&kinds, groups) {
                return kinds;
            }
            tracing::warn!(
                ?kinds,
                "device tree core kinds disagree with hw.perflevel; assuming slowest cores come first"
            );
        }
        Err(error) => tracing::warn!(
            error = format!("{error:#}"),
            "could not read core kinds from the device tree; assuming slowest cores come first"
        ),
    }
    kinds_slowest_first(groups)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn g(kind: CoreKind, n: u32) -> CoreGroup {
        CoreGroup {
            kind: kind as i32,
            name: String::new(),
            core_count: n,
        }
    }

    #[test]
    fn fallback_puts_efficiency_cores_first() {
        let groups = [g(CoreKind::Performance, 2), g(CoreKind::Efficiency, 1)];
        let kinds = kinds_slowest_first(&groups);
        assert_eq!(
            kinds,
            vec![
                CoreKind::Efficiency,
                CoreKind::Performance,
                CoreKind::Performance
            ]
        );
        assert!(matches_groups(&kinds, &groups));
    }

    #[test]
    fn mismatched_counts_are_rejected() {
        let groups = [g(CoreKind::Performance, 2), g(CoreKind::Efficiency, 2)];
        assert!(!matches_groups(&[CoreKind::Performance; 4], &groups));
        assert!(!matches_groups(&[CoreKind::Performance; 3], &groups));
    }
}
