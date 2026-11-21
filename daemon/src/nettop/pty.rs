//! Runs `nettop` with its output on a pseudo-terminal.
//!
//! On a pipe, `nettop` holds its output in a buffer and the daemon would
//! see a sample many seconds late; on a terminal it writes each sample as it
//! takes it. The pty is also the child's controlling terminal, so if the
//! daemon dies without stopping it (SIGKILL, a crash), the kernel closes the
//! pty and the child gets SIGHUP instead of running on as an orphan.

use std::fs::File;
use std::io::{self, Read};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

use anyhow::Context;

use super::{Chunk, Feed, Launcher};

pub const NETTOP: &str = "/usr/bin/nettop";

/// One summary line per process (`-P`), exact numbers (`-x`), no name
/// lookups (`-n`), CSV forever (`-L 0`), once a second, only the two byte
/// counters. `-t` keeps sockets on Wi-Fi, wired Ethernet and AWDL, the
/// interfaces the Net chart counts: loopback (the app's own gRPC traffic)
/// and VPN tunnels are left out.
pub const NETTOP_ARGS: [&str; 15] = [
    "-P",
    "-x",
    "-n",
    "-L",
    "0",
    "-s",
    "1",
    "-t",
    "wifi",
    "-t",
    "wired",
    "-t",
    "awdl",
    "-J",
    "bytes_in,bytes_out",
];

/// Starts a program on a pty. [`PtyLauncher::nettop`] is the real one;
/// tests start a shell script that prints the same format.
#[derive(Debug, Clone)]
pub struct PtyLauncher {
    program: PathBuf,
    args: Vec<String>,
}

impl PtyLauncher {
    pub fn nettop() -> Self {
        Self::new(NETTOP, &NETTOP_ARGS)
    }

    pub fn new(program: impl Into<PathBuf>, args: &[&str]) -> Self {
        Self {
            program: program.into(),
            args: args.iter().map(|&a| a.to_owned()).collect(),
        }
    }

    fn shown(&self) -> String {
        self.program.display().to_string()
    }
}

impl Launcher for PtyLauncher {
    fn launch(&self) -> anyhow::Result<Box<dyn Feed>> {
        let (master, slave) = open_pty().context("could not open a pseudo-terminal")?;
        let mut cmd = Command::new(&self.program);
        cmd.args(&self.args)
            .stdin(Stdio::null())
            .stdout(Stdio::from(slave.try_clone()?))
            .stderr(Stdio::from(slave));
        // SAFETY: setsid and ioctl are async-signal-safe and touch only the
        // child, which at this point has the pty as its stdout.
        unsafe {
            cmd.pre_exec(|| {
                if libc::setsid() < 0 || libc::ioctl(1, libc::TIOCSCTTY.into(), 0) < 0 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let child = cmd.spawn().map_err(|e| {
            let hint = if e.kind() == io::ErrorKind::NotFound {
                " (it ships with macOS; is this a Mac?)"
            } else {
                ""
            };
            anyhow::Error::new(e).context(format!("could not start {}{hint}", self.shown()))
        })?;
        // The child holds the only copies of the slave now; dropping the
        // command closes ours, so the master sees the end when it exits.
        drop(cmd);
        tracing::info!(pid = child.id(), "started {}", self.shown());
        Ok(Box::new(PtyFeed {
            child,
            master: File::from(master),
            shown: self.shown(),
            reaped: false,
        }))
    }
}

/// A pty pair, both ends closed on exec so other children never inherit
/// them (which would stop the hangup from reaching the child).
fn open_pty() -> io::Result<(OwnedFd, OwnedFd)> {
    let (mut master, mut slave) = (-1, -1);
    // SAFETY: valid out pointers; null name, termios and winsize are allowed.
    let rc = unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    };
    if rc != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: openpty succeeded, so both are open descriptors we now own.
    let fds = unsafe { (OwnedFd::from_raw_fd(master), OwnedFd::from_raw_fd(slave)) };
    for fd in [&fds.0, &fds.1] {
        // SAFETY: F_SETFD on a descriptor we own.
        if unsafe { libc::fcntl(fd.as_raw_fd(), libc::F_SETFD, libc::FD_CLOEXEC) } < 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(fds)
}

struct PtyFeed {
    child: Child,
    master: File,
    shown: String,
    reaped: bool,
}

impl PtyFeed {
    /// Waits for the exited child and says how it ended.
    fn ended(&mut self) -> io::Result<Chunk> {
        let status = self.child.wait()?;
        self.reaped = true;
        Ok(Chunk::Ended(status.to_string()))
    }
}

impl Feed for PtyFeed {
    fn pid(&self) -> u32 {
        self.child.id()
    }

    fn read(&mut self, timeout: Duration) -> io::Result<Chunk> {
        if self.reaped {
            return Ok(Chunk::Ended("already stopped".to_owned()));
        }
        let mut poll = libc::pollfd {
            fd: self.master.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let ms = libc::c_int::try_from(timeout.as_millis()).unwrap_or(libc::c_int::MAX);
        // SAFETY: one valid pollfd.
        match unsafe { libc::poll(&mut poll, 1, ms) } {
            0 => return Ok(Chunk::Idle),
            n if n < 0 => {
                let e = io::Error::last_os_error();
                return if e.kind() == io::ErrorKind::Interrupted {
                    Ok(Chunk::Idle)
                } else {
                    Err(e)
                };
            }
            _ => {}
        }
        let mut buf = vec![0u8; 16 * 1024];
        match self.master.read(&mut buf) {
            Ok(0) => self.ended(),
            Ok(n) => {
                buf.truncate(n);
                Ok(Chunk::Data(buf))
            }
            // A pty master reads EIO once the child has closed the slave.
            Err(e) if e.raw_os_error() == Some(libc::EIO) => self.ended(),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => Ok(Chunk::Idle),
            Err(e) => Err(e),
        }
    }

    fn stop(&mut self) -> io::Result<()> {
        if self.reaped {
            return Ok(());
        }
        match self.child.kill() {
            Ok(()) => {}
            // It already exited; the wait below reaps it.
            Err(e) if e.kind() == io::ErrorKind::InvalidInput => {}
            Err(e) => return Err(e),
        }
        let status = self.child.wait()?;
        self.reaped = true;
        tracing::info!(pid = self.child.id(), %status, "stopped {}", self.shown);
        Ok(())
    }
}

impl Drop for PtyFeed {
    fn drop(&mut self) {
        if let Err(error) = self.stop() {
            tracing::error!(%error, pid = self.child.id(), "could not stop {}", self.shown);
        }
    }
}
