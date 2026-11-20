//! The process table from `sysctl kern.proc.all`: pid, parent, owner, start
//! time and short name of every process, including those owned by root.
//!
//! `libc` does not declare `struct kinfo_proc`, so the records are read as
//! bytes at the field offsets of the macOS 64-bit layout (checked with
//! `offsetof` against the SDK headers).

use anyhow::{Context, bail};

use crate::sampler::sysctl;

/// `sizeof(struct kinfo_proc)`.
pub const RECORD_LEN: usize = 648;
/// `kp_proc.p_un.__p_starttime`, a `struct timeval`.
const START_SEC: usize = 0;
const START_USEC: usize = 8;
/// `kp_proc.p_pid`.
const PID: usize = 40;
/// `kp_proc.p_comm`, `MAXCOMLEN + 1` bytes.
const COMM: usize = 243;
const COMM_LEN: usize = 17;
/// `kp_eproc.e_ucred.cr_uid`, the effective owner.
const UID: usize = 420;
/// `kp_eproc.e_ppid`.
const PPID: usize = 560;

/// How often to retry when the table grows between sizing and reading it.
const LIST_ATTEMPTS: usize = 3;

/// One process as the kernel lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawProc {
    pub pid: i32,
    pub parent_pid: i32,
    pub uid: u32,
    /// Microseconds since the Unix epoch. With the pid it identifies a
    /// process: a reused pid has a later start time.
    pub start_us: u64,
    /// The first 16 bytes of the executable's name.
    pub comm: String,
}

/// Lists every process on the machine.
pub fn list() -> anyhow::Result<Vec<RawProc>> {
    let mut last_error = None;
    for _ in 0..LIST_ATTEMPTS {
        match sysctl::bytes("kern.proc.all") {
            Ok(raw) => return parse(&raw),
            // ENOMEM: processes started between sizing and reading.
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| anyhow::anyhow!("no attempt made")))
        .context("could not list processes")
}

/// Reads the records in a `kern.proc.all` buffer.
pub fn parse(raw: &[u8]) -> anyhow::Result<Vec<RawProc>> {
    if !raw.len().is_multiple_of(RECORD_LEN) {
        bail!(
            "kern.proc.all returned {} bytes, not a multiple of {RECORD_LEN}",
            raw.len()
        );
    }
    Ok(raw.chunks_exact(RECORD_LEN).map(record).collect())
}

fn record(r: &[u8]) -> RawProc {
    let sec = u64::try_from(i64_at(r, START_SEC)).unwrap_or(0);
    let usec = u64::try_from(i32_at(r, START_USEC)).unwrap_or(0);
    let comm = &r[COMM..COMM + COMM_LEN];
    let end = comm.iter().position(|&b| b == 0).unwrap_or(COMM_LEN);
    RawProc {
        pid: i32_at(r, PID),
        parent_pid: i32_at(r, PPID),
        uid: u32::from_ne_bytes(array(r, UID)),
        start_us: sec.saturating_mul(1_000_000).saturating_add(usec),
        comm: String::from_utf8_lossy(&comm[..end]).into_owned(),
    }
}

fn array<const N: usize>(r: &[u8], at: usize) -> [u8; N] {
    let mut out = [0u8; N];
    out.copy_from_slice(&r[at..at + N]);
    out
}

fn i32_at(r: &[u8], at: usize) -> i32 {
    i32::from_ne_bytes(array(r, at))
}

fn i64_at(r: &[u8], at: usize) -> i64 {
    i64::from_ne_bytes(array(r, at))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake(pid: i32, ppid: i32, uid: u32, sec: i64, usec: i32, name: &str) -> Vec<u8> {
        let mut r = vec![0u8; RECORD_LEN];
        r[START_SEC..START_SEC + 8].copy_from_slice(&sec.to_ne_bytes());
        r[START_USEC..START_USEC + 4].copy_from_slice(&usec.to_ne_bytes());
        r[PID..PID + 4].copy_from_slice(&pid.to_ne_bytes());
        r[PPID..PPID + 4].copy_from_slice(&ppid.to_ne_bytes());
        r[UID..UID + 4].copy_from_slice(&uid.to_ne_bytes());
        r[COMM..COMM + name.len()].copy_from_slice(name.as_bytes());
        r
    }

    #[test]
    fn parses_fields_at_their_offsets() {
        let mut raw = fake(42, 7, 501, 1_700_000_000, 250, "zsh");
        raw.extend(fake(1, 0, 0, 5, 0, "launchd"));
        let procs = parse(&raw).expect("parses");
        assert_eq!(
            procs[0],
            RawProc {
                pid: 42,
                parent_pid: 7,
                uid: 501,
                start_us: 1_700_000_000_000_250,
                comm: "zsh".to_owned(),
            }
        );
        assert_eq!((procs[1].pid, procs[1].uid), (1, 0));
        assert_eq!(procs[1].comm, "launchd");
    }

    #[test]
    fn full_length_name_without_nul_is_kept() {
        let procs = parse(&fake(3, 1, 0, 0, 0, "abcdefghijklmnopq")).expect("parses");
        assert_eq!(procs[0].comm, "abcdefghijklmnopq");
    }

    #[test]
    fn rejects_partial_records() {
        assert!(parse(&[0u8; RECORD_LEN + 1]).is_err());
        assert!(parse(&[]).expect("empty is fine").is_empty());
    }

    /// Reads the real table; works in the sandbox, which still shows this
    /// process itself.
    #[test]
    fn real_table_contains_this_process() {
        let procs = list().expect("lists");
        let me = i32::try_from(std::process::id()).expect("pid fits");
        let entry = procs.iter().find(|p| p.pid == me).expect("own pid listed");
        // SAFETY: `getppid` and `geteuid` have no preconditions.
        let (ppid, uid) = unsafe { (libc::getppid(), libc::geteuid()) };
        assert_eq!((entry.parent_pid, entry.uid), (ppid, uid));
        assert!(entry.start_us > 1_600_000_000_000_000);
    }
}
