use std::time::{Duration, SystemTime};

use icns::IconType;

use super::*;
use crate::icons::fixture::{self, TempDir};

fn as_str(path: &std::path::Path) -> &str {
    path.to_str().expect("utf8")
}

#[test]
fn lookup_renders_and_caches_including_no_icon() {
    let dir = TempDir::new();
    let with = fixture::bundle(dir.path(), "With", &[("CFBundleIconFile", "AppIcon")]);
    fixture::write_icns(
        &with.join("Contents/Resources/AppIcon.icns"),
        &[IconType::RGBA32_256x256],
    );
    let without = fixture::bundle(dir.path(), "Without", &[("CFBundleIconName", "AppIcon")]);
    let cache = Mutex::new(IconCache::new(8));

    let png = lookup(&cache, as_str(&with)).expect("valid");
    assert!(png.starts_with(b"\x89PNG"));
    assert!(lookup(&cache, as_str(&without)).expect("valid").is_empty());
    assert_eq!(lock(&cache).len(), 2, "no-icon results are cached too");

    // Delete the icon: a cached answer is still served while the plist is unchanged.
    std::fs::remove_file(with.join("Contents/Resources/AppIcon.icns")).expect("remove");
    assert_eq!(lookup(&cache, as_str(&with)).expect("valid"), png);
}

#[test]
fn lookup_rereads_when_the_plist_changes() {
    let dir = TempDir::new();
    let root = fixture::bundle(dir.path(), "Changing", &[]);
    let cache = Mutex::new(IconCache::new(8));
    assert!(lookup(&cache, as_str(&root)).expect("valid").is_empty());

    fixture::write_icns(
        &root.join("Contents/Resources/New.icns"),
        &[IconType::RGBA32_128x128],
    );
    fixture::write_plist(&root, &[("CFBundleIconFile", "New.icns")]);
    // Make sure the modification time differs even on coarse clocks.
    let later = SystemTime::now() + Duration::from_secs(10);
    std::fs::File::options()
        .write(true)
        .open(root.join("Contents/Info.plist"))
        .and_then(|f| f.set_modified(later))
        .expect("set mtime");

    let png = lookup(&cache, as_str(&root)).expect("valid");
    assert!(png.starts_with(b"\x89PNG"), "the new icon is read");
}

#[test]
fn lookup_rejects_invalid_paths_without_caching() {
    let cache = Mutex::new(IconCache::new(8));
    assert!(lookup(&cache, "relative.app").is_err());
    assert!(lock(&cache).is_empty());
}

#[tokio::test]
async fn service_maps_invalid_paths() {
    let service = IconService::default();
    let error = service.png("/nope/../x.app".into()).await.expect_err("bad");
    assert!(matches!(error, IconError::InvalidPath(m) if m.contains("..")));
}
