//! Finds the `rex` executable. Under launchd `PATH` is minimal, so the
//! install script passes the full path in `COMPUTAD_REX`.

use std::ffi::OsStr;
use std::path::{Path, PathBuf};

use super::RexError;

/// Names the `rex` executable to use. When set, nothing else is tried.
pub const REX_ENV: &str = "COMPUTAD_REX";

/// Where the Rex app installs the CLI, relative to the user's home.
pub const KNOWN_LOCATION: &str = "Library/Application Support/com.superlogical.rex/RexServer/\
     Versions/Current/Rex Server.app/Contents/MacOS/rex";

/// Finds `rex` from this process's environment.
///
/// # Errors
///
/// Returns [`RexError::NotFound`] saying where it looked.
pub fn locate_from_env() -> Result<PathBuf, RexError> {
    let over = std::env::var_os(REX_ENV);
    let path = std::env::var_os("PATH");
    let home = std::env::var_os("HOME");
    locate(
        over.as_deref(),
        path.as_deref(),
        home.as_deref(),
        is_executable,
    )
}

/// Finds `rex`: `override_path` if given (and only it), otherwise the first
/// `rex` on `path`, otherwise [`KNOWN_LOCATION`] under `home`.
///
/// # Errors
///
/// Returns [`RexError::NotFound`] saying where it looked.
pub fn locate(
    override_path: Option<&OsStr>,
    path: Option<&OsStr>,
    home: Option<&OsStr>,
    usable: impl Fn(&Path) -> bool,
) -> Result<PathBuf, RexError> {
    if let Some(over) = override_path.filter(|o| !o.is_empty()) {
        let candidate = PathBuf::from(over);
        return if usable(&candidate) {
            Ok(candidate)
        } else {
            Err(RexError::NotFound {
                detail: format!(
                    "{REX_ENV} is {}, which is not an executable file",
                    candidate.display()
                ),
            })
        };
    }
    if let Some(found) = path
        .into_iter()
        .flat_map(std::env::split_paths)
        .map(|dir| dir.join("rex"))
        .find(|c| usable(c))
    {
        return Ok(found);
    }
    let known = home.map(|h| Path::new(h).join(KNOWN_LOCATION));
    match known {
        Some(k) if usable(&k) => Ok(k),
        Some(k) => Err(RexError::NotFound {
            detail: format!("not on PATH and not at {}", k.display()),
        }),
        None => Err(RexError::NotFound {
            detail: "not on PATH, and HOME is not set".to_owned(),
        }),
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn os(s: &str) -> Option<&OsStr> {
        Some(OsStr::new(s))
    }

    #[test]
    fn the_override_wins_and_is_never_bypassed() {
        let all = |_: &Path| true;
        let found = locate(os("/opt/rex"), os("/usr/bin"), os("/Users/me"), all);
        assert_eq!(found, Ok(PathBuf::from("/opt/rex")));
        let none = |p: &Path| p != Path::new("/nonexistent/rex");
        let err = locate(
            os("/nonexistent/rex"),
            os("/usr/bin"),
            os("/Users/me"),
            none,
        )
        .expect_err("an unusable override is an error, not a fallback");
        assert!(err.to_string().contains("COMPUTAD_REX is /nonexistent/rex"));
    }

    #[test]
    fn searches_path_then_the_known_location() {
        let on_path = |p: &Path| p == Path::new("/b/rex");
        assert_eq!(
            locate(None, os("/a:/b"), os("/Users/me"), on_path),
            Ok(PathBuf::from("/b/rex"))
        );
        let known = Path::new("/Users/me").join(KNOWN_LOCATION);
        let only_known = |p: &Path| p == known;
        assert_eq!(
            locate(None, os("/a"), os("/Users/me"), only_known),
            Ok(known)
        );
    }

    #[test]
    fn says_where_it_looked_when_missing() {
        let err = locate(None, os("/a"), os("/Users/me"), |_| false).expect_err("missing");
        assert!(err.to_string().contains("Rex Server.app"), "{err}");
        assert!(err.problem().contains("Install Rex"));
    }
}
