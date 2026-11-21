//! App icons for `GetAppIcon`: finds a bundle's `.icns` file, renders it as
//! a PNG of at most 128 pixels on a side, and caches the result.
//!
//! Only `.icns` files are read. Apps that ship their icon only in an asset
//! catalog (`Assets.car`) get an empty icon, which is not an error.

mod bundle;
mod cache;
mod render;

#[cfg(test)]
pub(crate) mod fixture;

use std::sync::{Arc, Mutex, PoisonError};

pub use bundle::{InvalidPath, MAX_ICON_BYTES};
pub use cache::DEFAULT_CAPACITY;
pub use render::MAX_SIDE;

use bundle::Bundle;
use cache::IconCache;

/// Why an icon request failed. A bundle without an icon is not a failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IconError {
    /// The requested path is not an app bundle this daemon will read.
    InvalidPath(String),
    /// The work could not be done; the details are in the log.
    Internal,
}

/// Serves app icons, sharing one cache between all requests.
#[derive(Debug, Clone)]
pub struct IconService {
    cache: Arc<Mutex<IconCache>>,
}

impl Default for IconService {
    fn default() -> Self {
        Self::new(DEFAULT_CAPACITY)
    }
}

impl IconService {
    /// A service that remembers icons for up to `capacity` bundles.
    pub fn new(capacity: usize) -> Self {
        Self {
            cache: Arc::new(Mutex::new(IconCache::new(capacity))),
        }
    }

    /// The icon of the bundle at `bundle_path` as PNG bytes, empty when it
    /// has no readable icon. File reading and decoding run on the blocking
    /// thread pool.
    pub async fn png(&self, bundle_path: String) -> Result<Vec<u8>, IconError> {
        let cache = Arc::clone(&self.cache);
        let path = bundle_path.clone();
        match tokio::task::spawn_blocking(move || lookup(&cache, &path)).await {
            Ok(result) => result.map_err(|InvalidPath(message)| IconError::InvalidPath(message)),
            Err(error) => {
                tracing::error!(%error, bundle_path, "the icon task failed");
                Err(IconError::Internal)
            }
        }
    }
}

/// Checks the path, then answers from the cache or reads the icon.
fn lookup(cache: &Mutex<IconCache>, bundle_path: &str) -> Result<Vec<u8>, InvalidPath> {
    let bundle = bundle::validate(bundle_path)?;
    let modified = bundle::plist_modified(&bundle);
    let cached = lock(cache).get(bundle_path, modified);
    if let Some(png) = cached {
        return Ok(png);
    }
    let png = load(&bundle, bundle_path);
    lock(cache).insert(bundle_path, modified, png.clone());
    Ok(png)
}

/// The cache holds only finished entries, so one left by a panicking thread
/// is still consistent.
fn lock(cache: &Mutex<IconCache>) -> std::sync::MutexGuard<'_, IconCache> {
    cache.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Reads and renders the icon, or returns an empty PNG (logged once, as the
/// result is cached) when the bundle has none this daemon can read.
fn load(bundle: &Bundle, bundle_path: &str) -> Vec<u8> {
    let rendered = bundle::find_icon(bundle).and_then(|icon| {
        let bytes = bundle::read_icon(bundle, &icon)?;
        render::icns_to_png(&bytes)
    });
    rendered.unwrap_or_else(|error| {
        tracing::debug!(
            bundle_path,
            reason = format!("{error:#}"),
            "no readable icon; returning an empty one"
        );
        Vec::new()
    })
}

#[cfg(test)]
#[path = "service_tests.rs"]
mod tests;
