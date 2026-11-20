//! Reads one pass over every process: the kernel's table, each executable's
//! path (cached), and usage where the daemon is allowed to read it.

use std::collections::{HashMap, HashSet};
use std::io;
use std::sync::Arc;
use std::time::Instant;

use super::cpu::{CpuReading, CpuTracker};
use super::darwin::{self, RawUsage};
use super::kinfo::{self, RawProc};
use super::table::{ProcessEntry, ProcessTable, Usage};
use crate::sampler::log_once::LogOnce;

/// Where process facts come from: the real system, or a fake in tests.
pub trait Source: Send {
    fn list(&mut self) -> anyhow::Result<Vec<RawProc>>;
    fn path(&mut self, pid: i32) -> Option<String>;
    fn usage(&mut self, pid: i32) -> io::Result<RawUsage>;
}

/// The running machine.
#[derive(Debug, Default)]
pub struct Darwin;

impl Source for Darwin {
    fn list(&mut self) -> anyhow::Result<Vec<RawProc>> {
        kinfo::list()
    }
    fn path(&mut self, pid: i32) -> Option<String> {
        darwin::path(pid)
    }
    fn usage(&mut self, pid: i32) -> io::Result<RawUsage> {
        darwin::rusage(pid)
    }
}

/// A cached path, valid while the pid, start time and short name match.
/// The short name changes on `exec`, which also changes the path.
#[derive(Debug)]
struct Cached {
    start_us: u64,
    comm: String,
    name: Arc<str>,
    path: Arc<str>,
}

/// Keeps what must survive between passes: paths and CPU readings.
pub struct Reader<S> {
    source: S,
    paths: HashMap<i32, Cached>,
    cpu: CpuTracker,
    list_log: LogOnce,
    usage_log: LogOnce,
}

impl<S: Source> Reader<S> {
    pub fn new(source: S) -> Self {
        Self {
            source,
            paths: HashMap::new(),
            cpu: CpuTracker::default(),
            list_log: LogOnce::new("process list"),
            usage_log: LogOnce::new("process usage"),
        }
    }

    /// Reads every process. If the list itself cannot be read, the failure
    /// is logged and the table is empty.
    pub fn read(&mut self, now: Instant) -> ProcessTable {
        let Some(procs) = self.list_log.check(self.source.list()) else {
            return ProcessTable::default();
        };
        self.cpu.begin(now);
        let mut seen = HashSet::with_capacity(procs.len());
        let mut entries = Vec::with_capacity(procs.len());
        for p in procs {
            let (name, path) = self.path_of(&p);
            seen.insert(p.pid);
            let usage = self.usage_of(&p);
            entries.push(ProcessEntry {
                pid: p.pid,
                parent_pid: p.parent_pid,
                uid: p.uid,
                name,
                path,
                usage,
            });
        }
        self.cpu.finish();
        self.paths.retain(|pid, _| seen.contains(pid));
        ProcessTable::new(entries)
    }

    fn path_of(&mut self, p: &RawProc) -> (Arc<str>, Arc<str>) {
        if let Some(c) = self.paths.get(&p.pid)
            && c.start_us == p.start_us
            && c.comm == p.comm
        {
            return (Arc::clone(&c.name), Arc::clone(&c.path));
        }
        let path = self.source.path(p.pid).unwrap_or_default();
        let name = match path.rsplit('/').next() {
            Some(file) if !file.is_empty() => file.to_owned(),
            _ => p.comm.clone(),
        };
        let cached = Cached {
            start_us: p.start_us,
            comm: p.comm.clone(),
            name: name.into(),
            path: path.into(),
        };
        let out = (Arc::clone(&cached.name), Arc::clone(&cached.path));
        self.paths.insert(p.pid, cached);
        out
    }

    /// `None` when the process is not readable. Being refused (another
    /// user's process) or finding it gone is normal and not logged.
    fn usage_of(&mut self, p: &RawProc) -> Option<Usage> {
        let raw = match self.source.usage(p.pid) {
            Ok(raw) => {
                self.usage_log.check(Ok(()));
                raw
            }
            Err(e) if matches!(e.raw_os_error(), Some(libc::EPERM | libc::ESRCH)) => return None,
            Err(e) => {
                let context = format!("proc_pid_rusage for pid {}", p.pid);
                self.usage_log
                    .check::<()>(Err(anyhow::Error::new(e).context(context)));
                return None;
            }
        };
        let reading = CpuReading {
            start_us: p.start_us,
            cpu_ns: raw.cpu_ns,
        };
        Some(Usage {
            cpu_percent: self.cpu.percent(p.pid, reading),
            memory_bytes: raw.footprint_bytes,
            resident_bytes: raw.resident_bytes,
        })
    }
}

#[cfg(test)]
#[path = "reader_tests.rs"]
mod tests;
