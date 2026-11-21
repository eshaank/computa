//! [`RexClient`] over the `rex` command-line program.

use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use serde::de::DeserializeOwned;
use tokio::io::{AsyncBufReadExt, BufReader, Lines};
use tokio::process::{Child, ChildStdout, Command};

use super::model::{PaneProcess, ServerVersion, SessionList, SessionView};
use super::{EventLines, RexClient, RexError, SessionRef, locate_from_env};

/// How long one `rex` call may take before it is killed.
const CALL_TIMEOUT: Duration = Duration::from_secs(8);
/// Passed to `rex --timeout`: limits connecting to the server.
const CONNECT_TIMEOUT: &str = "5s";

/// Runs `rex`. It is looked up on every call, so installing Rex while the
/// daemon runs is picked up at the next retry.
#[derive(Debug, Default, Clone)]
pub struct CliRex {
    /// Use this executable instead of looking it up (for tests).
    fixed: Option<PathBuf>,
}

impl CliRex {
    /// Finds `rex` from `COMPUTAD_REX`, `PATH`, or Rex's install location.
    pub fn from_env() -> Self {
        Self { fixed: None }
    }

    pub fn at(path: PathBuf) -> Self {
        Self { fixed: Some(path) }
    }

    fn program(&self) -> Result<PathBuf, RexError> {
        match &self.fixed {
            Some(p) => Ok(p.clone()),
            None => locate_from_env(),
        }
    }

    /// A `rex` command that never starts a server, never waits on stdin, and
    /// does not inherit the pane targeting of a Rex terminal it was started
    /// from.
    fn command(&self, args: &[&str]) -> Result<(Command, String), RexError> {
        let program = self.program()?;
        let mut cmd = Command::new(&program);
        cmd.arg("--autostart=false")
            .arg("--timeout")
            .arg(CONNECT_TIMEOUT)
            .args(args)
            .env_remove("REX_SESSION")
            .env_remove("REX_BLOCK")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        Ok((cmd, format!("rex {}", args.join(" "))))
    }

    /// Runs `rex ARGS` to completion and parses its JSON output.
    async fn call<T: DeserializeOwned>(&self, args: &[&str]) -> Result<T, RexError> {
        let (mut cmd, shown) = self.command(args)?;
        let child = cmd.spawn().map_err(|e| RexError::Spawn {
            command: shown.clone(),
            error: e.to_string(),
        })?;
        let output = tokio::time::timeout(CALL_TIMEOUT, child.wait_with_output())
            .await
            .map_err(|_| RexError::Timeout {
                command: shown.clone(),
                seconds: CALL_TIMEOUT.as_secs(),
            })?
            .map_err(|e| RexError::Spawn {
                command: shown.clone(),
                error: e.to_string(),
            })?;
        if !output.status.success() {
            return Err(RexError::from_exit(
                shown,
                output.status.code(),
                output.status.to_string(),
                String::from_utf8_lossy(&output.stderr).into_owned(),
            ));
        }
        serde_json::from_slice(&output.stdout).map_err(|e| RexError::Parse {
            command: shown,
            error: e.to_string(),
        })
    }
}

#[tonic::async_trait]
impl RexClient for CliRex {
    async fn version(&self) -> Result<String, RexError> {
        let v: ServerVersion = self.call(&["api", "call", "server.version"]).await?;
        Ok(v.rex_version)
    }

    async fn list_sessions(&self) -> Result<Vec<SessionRef>, RexError> {
        let list: SessionList = self.call(&["api", "call", "session.list"]).await?;
        Ok(list.sessions)
    }

    async fn view_session(&self, session_id: &str) -> Result<SessionView, RexError> {
        let args = serde_json::json!({ "session_id": session_id }).to_string();
        self.call(&["api", "call", "session.view", &args]).await
    }

    async fn pane_process(
        &self,
        session_id: &str,
        block_id: &str,
    ) -> Result<PaneProcess, RexError> {
        self.call(&["block", "call", "-s", session_id, "-b", block_id, "process"])
            .await
    }

    async fn events(&self) -> Result<Box<dyn EventLines>, RexError> {
        let (mut cmd, shown) = self.command(&["events", "--all", "--json"])?;
        let mut child = cmd.spawn().map_err(|e| RexError::Spawn {
            command: shown.clone(),
            error: e.to_string(),
        })?;
        let (Some(stdout), Some(stderr)) = (child.stdout.take(), child.stderr.take()) else {
            return Err(RexError::Spawn {
                command: shown,
                error: "its output pipes were not opened".to_owned(),
            });
        };
        let pid = child.id();
        tracing::info!(?pid, "started `{shown}`");
        tokio::spawn(log_stderr(BufReader::new(stderr), shown.clone()));
        Ok(Box::new(CliEvents {
            child,
            lines: BufReader::new(stdout).lines(),
            shown,
        }))
    }
}

/// Logs what `rex events` writes to stderr, line by line.
async fn log_stderr(stderr: BufReader<tokio::process::ChildStderr>, shown: String) {
    let mut lines = stderr.lines();
    loop {
        match lines.next_line().await {
            Ok(Some(line)) => tracing::warn!(stderr = %line, "`{shown}` wrote an error"),
            Ok(None) => break,
            Err(error) => {
                tracing::warn!(%error, "could not read the stderr of `{shown}`");
                break;
            }
        }
    }
}

/// A running `rex events` process. Dropping it kills the process.
struct CliEvents {
    child: Child,
    lines: Lines<BufReader<ChildStdout>>,
    shown: String,
}

#[tonic::async_trait]
impl EventLines for CliEvents {
    async fn next_line(&mut self) -> Result<Option<String>, RexError> {
        match self.lines.next_line().await {
            Ok(Some(line)) => Ok(Some(line)),
            Ok(None) => {
                let status = self.child.wait().await.map_err(|e| RexError::Spawn {
                    command: self.shown.clone(),
                    error: format!("could not wait for it to exit: {e}"),
                })?;
                if status.success() {
                    Ok(None)
                } else {
                    Err(RexError::from_exit(
                        self.shown.clone(),
                        status.code(),
                        status.to_string(),
                        "see the stderr lines logged above".to_owned(),
                    ))
                }
            }
            Err(e) => Err(RexError::Parse {
                command: self.shown.clone(),
                error: format!("could not read its output: {e}"),
            }),
        }
    }
}

impl Drop for CliEvents {
    fn drop(&mut self) {
        // kill_on_drop would do this too; doing it here makes it explicit
        // and lets a failure be logged.
        if let Err(error) = self.child.start_kill() {
            // InvalidInput means it already exited and was reaped.
            if error.kind() != std::io::ErrorKind::InvalidInput {
                tracing::error!(%error, "could not stop `{}`", self.shown);
            }
        } else {
            tracing::info!(pid = ?self.child.id(), "stopped `{}`", self.shown);
        }
    }
}
