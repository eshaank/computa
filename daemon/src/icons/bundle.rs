//! Checks a requested bundle path and finds the icon file inside it.
//!
//! Every file read here must lie inside the bundle: names taken from the
//! Info.plist are reduced to plain file names, and each file is resolved
//! (following symlinks) and checked against the bundle's resolved root.

use std::fs::{self, File};
use std::io::{ErrorKind, Read};
use std::path::{Component, Path, PathBuf};
use std::time::SystemTime;

use anyhow::{Context, bail};

/// Icon files larger than this are refused.
pub const MAX_ICON_BYTES: u64 = 20 * 1024 * 1024;
/// An Info.plist larger than this is refused. Real ones are a few KB.
const MAX_PLIST_BYTES: u64 = 4 * 1024 * 1024;

/// Why a requested bundle path was refused. The text is sent to the client.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvalidPath(pub String);

/// A bundle path that passed [`validate`].
#[derive(Debug, Clone)]
pub struct Bundle {
    /// The bundle with symlinks resolved. Nothing outside it is read.
    pub root: PathBuf,
}

impl Bundle {
    fn info_plist(&self) -> PathBuf {
        self.root.join("Contents/Info.plist")
    }

    fn resources(&self) -> PathBuf {
        self.root.join("Contents/Resources")
    }
}

/// Accepts `raw` only if it is an absolute path ending in `.app`, with no
/// `..` component, naming an existing directory.
pub fn validate(raw: &str) -> Result<Bundle, InvalidPath> {
    let path = Path::new(raw);
    if !path.is_absolute() {
        return Err(InvalidPath(format!(
            "bundle_path must be absolute: {raw:?}"
        )));
    }
    if path.extension().is_none_or(|ext| ext != "app") {
        return Err(InvalidPath(format!(
            "bundle_path must end in .app: {raw:?}"
        )));
    }
    if path.components().any(|c| c == Component::ParentDir) {
        return Err(InvalidPath(format!(
            "bundle_path must not contain '..': {raw:?}"
        )));
    }
    let metadata = fs::metadata(path).map_err(|error| match error.kind() {
        ErrorKind::NotFound => InvalidPath(format!("no such bundle: {raw:?}")),
        _ => InvalidPath(format!("cannot read bundle {raw:?}: {error}")),
    })?;
    if !metadata.is_dir() {
        return Err(InvalidPath(format!(
            "bundle_path is not a directory: {raw:?}"
        )));
    }
    let root = fs::canonicalize(path)
        .map_err(|error| InvalidPath(format!("cannot resolve bundle {raw:?}: {error}")))?;
    Ok(Bundle { root })
}

/// When the bundle's Info.plist last changed, or `None` if it has none.
/// Used as part of the cache key.
pub fn plist_modified(bundle: &Bundle) -> Option<SystemTime> {
    let path = bundle.info_plist();
    match fs::metadata(&path).and_then(|m| m.modified()) {
        Ok(time) => Some(time),
        Err(error) => {
            if error.kind() != ErrorKind::NotFound {
                tracing::debug!(path = %path.display(), %error, "cannot read the Info.plist's modification time");
            }
            None
        }
    }
}

/// Turns an icon name from the Info.plist into a file name in Resources:
/// adds `.icns` when it has no extension, and refuses anything that is not
/// a plain file name.
pub fn icon_file_name(name: &str) -> anyhow::Result<String> {
    if name.is_empty() || name == "." || name == ".." {
        bail!("icon name {name:?} is not a file name");
    }
    if name.contains('/') || name.contains('\0') {
        bail!("icon name {name:?} must be a plain file name");
    }
    if Path::new(name).extension().is_some() {
        Ok(name.to_owned())
    } else {
        Ok(format!("{name}.icns"))
    }
}

/// Finds the bundle's `.icns` file: `CFBundleIconFile`, else
/// `CFBundleIconName` with `.icns` added, when that file is in Resources.
pub fn find_icon(bundle: &Bundle) -> anyhow::Result<PathBuf> {
    let plist_path = bundle.info_plist();
    let bytes = read_confined(bundle, &plist_path, MAX_PLIST_BYTES)?;
    let value = plist::Value::from_reader(std::io::Cursor::new(bytes))
        .with_context(|| format!("cannot parse {}", plist_path.display()))?;
    let dict = value
        .as_dictionary()
        .with_context(|| format!("{} is not a dictionary", plist_path.display()))?;
    for key in ["CFBundleIconFile", "CFBundleIconName"] {
        let Some(name) = dict.get(key).and_then(plist::Value::as_string) else {
            continue;
        };
        let candidate = bundle.resources().join(icon_file_name(name)?);
        if candidate.is_file() {
            return Ok(candidate);
        }
        tracing::debug!(key, path = %candidate.display(), "the named icon file is missing");
    }
    bail!("no CFBundleIconFile or CFBundleIconName names an icon file in Resources")
}

/// Reads the icon file, refusing one larger than [`MAX_ICON_BYTES`].
pub fn read_icon(bundle: &Bundle, path: &Path) -> anyhow::Result<Vec<u8>> {
    read_confined(bundle, path, MAX_ICON_BYTES)
}

/// Reads a regular file of at most `limit` bytes that resolves to a path
/// inside the bundle.
fn read_confined(bundle: &Bundle, path: &Path, limit: u64) -> anyhow::Result<Vec<u8>> {
    let resolved =
        fs::canonicalize(path).with_context(|| format!("cannot resolve {}", path.display()))?;
    if !resolved.starts_with(&bundle.root) {
        bail!("{} resolves outside the bundle", path.display());
    }
    let metadata =
        fs::metadata(&resolved).with_context(|| format!("cannot stat {}", resolved.display()))?;
    if !metadata.is_file() {
        bail!("{} is not a regular file", resolved.display());
    }
    if metadata.len() > limit {
        bail!(
            "{} is {} bytes; the limit is {limit}",
            resolved.display(),
            metadata.len()
        );
    }
    let mut bytes = Vec::with_capacity(usize::try_from(metadata.len()).unwrap_or(0));
    File::open(&resolved)
        .and_then(|file| file.take(limit + 1).read_to_end(&mut bytes))
        .with_context(|| format!("cannot read {}", resolved.display()))?;
    if bytes.len() as u64 > limit {
        bail!("{} grew past the {limit} byte limit", resolved.display());
    }
    Ok(bytes)
}

#[cfg(test)]
#[path = "bundle_tests.rs"]
mod tests;
