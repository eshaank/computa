//! A bounded in-memory cache of rendered icons.

use std::collections::{HashMap, VecDeque};
use std::time::SystemTime;

/// How many bundles the daemon remembers icons for.
pub const DEFAULT_CAPACITY: usize = 256;

#[derive(Debug)]
struct Entry {
    plist_modified: Option<SystemTime>,
    png: Vec<u8>,
}

/// Icons by bundle path, each valid for one Info.plist modification time.
/// An empty PNG records "this bundle has no readable icon". When full, the
/// entry stored longest ago is dropped.
#[derive(Debug)]
pub struct IconCache {
    capacity: usize,
    order: VecDeque<String>,
    entries: HashMap<String, Entry>,
}

impl IconCache {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity: capacity.max(1),
            order: VecDeque::new(),
            entries: HashMap::new(),
        }
    }

    /// The stored PNG for `path`, if it was stored for the same Info.plist
    /// modification time.
    pub fn get(&self, path: &str, plist_modified: Option<SystemTime>) -> Option<Vec<u8>> {
        self.entries
            .get(path)
            .filter(|entry| entry.plist_modified == plist_modified)
            .map(|entry| entry.png.clone())
    }

    /// Stores `png` for `path`, replacing any older entry for it.
    pub fn insert(&mut self, path: &str, plist_modified: Option<SystemTime>, png: Vec<u8>) {
        if self.entries.contains_key(path) {
            self.order.retain(|p| p != path);
        }
        self.order.push_back(path.to_owned());
        self.entries.insert(
            path.to_owned(),
            Entry {
                plist_modified,
                png,
            },
        );
        while self.order.len() > self.capacity {
            if let Some(oldest) = self.order.pop_front() {
                self.entries.remove(&oldest);
            }
        }
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    #[cfg(test)]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    fn at(secs: u64) -> Option<SystemTime> {
        Some(SystemTime::UNIX_EPOCH + Duration::from_secs(secs))
    }

    #[test]
    fn returns_the_stored_value_including_no_icon() {
        let mut cache = IconCache::new(4);
        cache.insert("/A.app", at(1), vec![1, 2, 3]);
        cache.insert("/B.app", None, Vec::new());
        assert_eq!(cache.get("/A.app", at(1)), Some(vec![1, 2, 3]));
        assert_eq!(cache.get("/B.app", None), Some(Vec::new()));
        assert_eq!(cache.get("/C.app", None), None);
    }

    #[test]
    fn misses_when_the_plist_time_changes() {
        let mut cache = IconCache::new(4);
        cache.insert("/A.app", at(1), vec![1]);
        assert_eq!(cache.get("/A.app", at(2)), None);
        assert_eq!(cache.get("/A.app", None), None);
        cache.insert("/A.app", at(2), vec![2]);
        assert_eq!(cache.get("/A.app", at(2)), Some(vec![2]));
        assert_eq!(cache.len(), 1, "replacing must not duplicate the entry");
    }

    #[test]
    fn stays_within_its_bound_dropping_the_oldest() {
        let mut cache = IconCache::new(3);
        for i in 0..10 {
            cache.insert(&format!("/{i}.app"), None, vec![i]);
            assert!(cache.len() <= 3);
        }
        assert_eq!(cache.len(), 3);
        assert_eq!(cache.get("/6.app", None), None);
        for i in 7..10 {
            assert_eq!(cache.get(&format!("/{i}.app"), None), Some(vec![i]));
        }
    }

    #[test]
    fn reinserting_moves_an_entry_to_the_newest_position() {
        let mut cache = IconCache::new(2);
        cache.insert("/A.app", None, vec![1]);
        cache.insert("/B.app", None, vec![2]);
        cache.insert("/A.app", at(5), vec![3]);
        cache.insert("/C.app", None, vec![4]);
        assert_eq!(cache.get("/B.app", None), None, "B was the oldest");
        assert_eq!(cache.get("/A.app", at(5)), Some(vec![3]));
    }
}
