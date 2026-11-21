//! Builds small app bundles in a temporary directory for tests.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use icns::{IconFamily, IconType, Image, PixelFormat};

/// A temporary directory removed when dropped.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("computad-icons-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("create temp dir");
        Self(dir)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        if let Err(error) = std::fs::remove_dir_all(&self.0) {
            eprintln!("could not remove {}: {error}", self.0.display());
        }
    }
}

/// Creates `<dir>/<name>.app` with an Info.plist holding `entries` as
/// string keys, and an empty Resources folder.
pub fn bundle(dir: &Path, name: &str, entries: &[(&str, &str)]) -> PathBuf {
    let root = dir.join(format!("{name}.app"));
    std::fs::create_dir_all(root.join("Contents/Resources")).expect("create bundle");
    write_plist(&root, entries);
    root
}

/// Rewrites the bundle's Info.plist as XML.
pub fn write_plist(root: &Path, entries: &[(&str, &str)]) {
    let body: String = entries
        .iter()
        .map(|(k, v)| format!("<key>{k}</key><string>{v}</string>"))
        .collect();
    let xml = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>{body}</dict></plist>\n"
    );
    std::fs::write(root.join("Contents/Info.plist"), xml).expect("write plist");
}

/// An RGBA image of `size` × `size` with a left/right colour split.
pub fn image(size: u32) -> Image {
    let mut image = Image::new(PixelFormat::RGBA, size, size);
    for (i, px) in image.data_mut().chunks_exact_mut(4).enumerate() {
        let left = (i as u32 % size) < size / 2;
        px.copy_from_slice(if left {
            &[255, 0, 0, 255]
        } else {
            &[0, 0, 255, 255]
        });
    }
    image
}

/// Writes an `.icns` file holding one image per type.
pub fn write_icns(path: &Path, types: &[IconType]) {
    let mut family = IconFamily::new();
    for &t in types {
        family
            .add_icon_with_type(&image(t.pixel_width()), t)
            .expect("encode icon");
    }
    let file = std::fs::File::create(path).expect("create icns");
    family.write(file).expect("write icns");
}
