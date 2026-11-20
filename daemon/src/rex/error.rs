//! Why a call to Rex failed: detail for the log, and a sentence for a person.

use std::fmt;

/// The CLI's exit status for "target not found or ambiguous".
pub const EXIT_TARGET_NOT_FOUND: i32 = 3;
/// The CLI's exit status for "server unreachable".
pub const EXIT_SERVER_UNREACHABLE: i32 = 4;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RexError {
    /// No `rex` executable was found. `detail` says where the daemon looked.
    NotFound { detail: String },
    /// `rex` ran but no Rex server is running.
    ServerNotRunning { command: String, stderr: String },
    /// The session or block asked about no longer exists.
    TargetGone { command: String, stderr: String },
    /// `rex` could not be started.
    Spawn { command: String, error: String },
    /// `rex` did not finish in time.
    Timeout { command: String, seconds: u64 },
    /// `rex` exited unsuccessfully for another reason.
    Failed {
        command: String,
        status: String,
        stderr: String,
    },
    /// `rex` printed something the daemon could not read.
    Parse { command: String, error: String },
}

impl RexError {
    /// Builds the error for a finished command that did not succeed.
    pub fn from_exit(command: String, code: Option<i32>, status: String, stderr: String) -> Self {
        match code {
            Some(EXIT_SERVER_UNREACHABLE) => Self::ServerNotRunning { command, stderr },
            Some(EXIT_TARGET_NOT_FOUND) => Self::TargetGone { command, stderr },
            _ => Self::Failed {
                command,
                status,
                stderr,
            },
        }
    }

    /// A sentence a person can act on, for `RexStatus.problem`.
    pub fn problem(&self) -> String {
        match self {
            Self::NotFound { detail } => format!(
                "The rex command was not found ({detail}). Install Rex, or set COMPUTAD_REX \
                 to the full path of rex and restart the daemon."
            ),
            Self::ServerNotRunning { .. } => {
                "The Rex server is not running. Open Rex to start it.".to_owned()
            }
            Self::Spawn { error, .. } => format!("The rex command could not be run: {error}."),
            Self::Timeout { seconds, .. } => {
                format!("Rex did not answer within {seconds} seconds.")
            }
            Self::TargetGone { command, stderr }
            | Self::Failed {
                command, stderr, ..
            } => format!("`{command}` failed: {}", one_line(stderr)),
            Self::Parse { command, .. } => format!(
                "The daemon could not read what `{command}` printed. This Rex version may \
                 not be supported."
            ),
        }
    }
}

impl fmt::Display for RexError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound { detail } => write!(f, "rex was not found: {detail}"),
            Self::ServerNotRunning { command, stderr } => write!(
                f,
                "`{command}`: no Rex server is running (exit status {EXIT_SERVER_UNREACHABLE}): {}",
                one_line(stderr)
            ),
            Self::TargetGone { command, stderr } => write!(
                f,
                "`{command}`: target not found (exit status {EXIT_TARGET_NOT_FOUND}): {}",
                one_line(stderr)
            ),
            Self::Spawn { command, error } => write!(f, "could not run `{command}`: {error}"),
            Self::Timeout { command, seconds } => {
                write!(f, "`{command}` did not finish within {seconds} s")
            }
            Self::Failed {
                command,
                status,
                stderr,
            } => write!(f, "`{command}` failed ({status}): {}", one_line(stderr)),
            Self::Parse { command, error } => {
                write!(f, "could not parse the output of `{command}`: {error}")
            }
        }
    }
}

impl std::error::Error for RexError {}

/// Stderr trimmed onto one line, or a note that it was empty.
fn one_line(stderr: &str) -> String {
    let joined = stderr.split_whitespace().collect::<Vec<_>>().join(" ");
    if joined.is_empty() {
        "no error message".to_owned()
    } else {
        joined
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exit_codes_map_to_kinds() {
        let e = |code| RexError::from_exit("rex x".into(), Some(code), "s".into(), "e".into());
        assert!(matches!(e(4), RexError::ServerNotRunning { .. }));
        assert!(matches!(e(3), RexError::TargetGone { .. }));
        assert!(matches!(e(1), RexError::Failed { .. }));
    }

    #[test]
    fn problems_are_actionable_and_logs_carry_context() {
        let e = RexError::ServerNotRunning {
            command: "rex api call session.list".into(),
            stderr: "Error: no Rex server is running\n".into(),
        };
        assert!(e.problem().contains("Open Rex"));
        let log = e.to_string();
        assert!(log.contains("rex api call session.list") && log.contains("exit status 4"));
        assert!(log.contains("no Rex server is running"));
        let nf = RexError::NotFound {
            detail: "COMPUTAD_REX is /x/rex, which does not exist".into(),
        };
        assert!(nf.problem().starts_with("The rex command was not found"));
        assert!(nf.problem().contains("COMPUTAD_REX"));
    }
}
