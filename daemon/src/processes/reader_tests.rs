use std::time::Duration;

use super::*;

/// A scripted machine: processes, their paths and usage.
#[derive(Default)]
struct Fake {
    procs: Vec<RawProc>,
    paths: HashMap<i32, String>,
    usage: HashMap<i32, io::Result<RawUsage>>,
    path_calls: usize,
}

impl Source for Fake {
    fn list(&mut self) -> anyhow::Result<Vec<RawProc>> {
        Ok(self.procs.clone())
    }
    fn path(&mut self, pid: i32) -> Option<String> {
        self.path_calls += 1;
        self.paths.get(&pid).cloned()
    }
    fn usage(&mut self, pid: i32) -> io::Result<RawUsage> {
        match self.usage.get(&pid) {
            Some(Ok(u)) => Ok(*u),
            Some(Err(e)) => Err(io::Error::from_raw_os_error(e.raw_os_error().unwrap_or(0))),
            None => Err(io::Error::from_raw_os_error(libc::ESRCH)),
        }
    }
}

fn raw(pid: i32, start_us: u64, comm: &str) -> RawProc {
    RawProc {
        pid,
        parent_pid: 1,
        uid: 501,
        start_us,
        comm: comm.to_owned(),
    }
}

fn used(cpu_ns: u64, mem: u64) -> io::Result<RawUsage> {
    Ok(RawUsage {
        cpu_ns,
        footprint_bytes: mem,
        resident_bytes: mem / 2,
    })
}

fn fake() -> Fake {
    let mut f = Fake {
        procs: vec![
            raw(10, 1, "busy"),
            raw(11, 1, "rootd"),
            raw(12, 1, "kernel"),
        ],
        ..Fake::default()
    };
    f.paths.insert(10, "/opt/busy/bin/busy-worker".to_owned());
    f.paths.insert(11, "/usr/sbin/rootd".to_owned());
    f.usage.insert(10, used(0, 4096));
    f.usage
        .insert(11, Err(io::Error::from_raw_os_error(libc::EPERM)));
    f
}

#[test]
fn reads_usage_where_allowed_and_names_from_paths() {
    let mut r = Reader::new(fake());
    let t = r.read(Instant::now());
    assert_eq!(t.len(), 3);
    let busy = t.get(10).expect("busy");
    assert_eq!(
        &*busy.name, "busy-worker",
        "full file name, not the short name"
    );
    assert_eq!(
        busy.usage.map(|u| (u.memory_bytes, u.resident_bytes)),
        Some((4096, 2048))
    );
    assert_eq!(busy.usage.map(|u| u.cpu_percent), Some(0.0), "first sight");
    assert!(t.get(11).expect("rootd").usage.is_none());
    let kernel = t.get(12).expect("kernel");
    assert_eq!((&*kernel.name, &*kernel.path), ("kernel", ""));
}

#[test]
fn second_pass_gives_cpu_percent_and_reuses_cached_paths() {
    let t0 = Instant::now();
    let mut r = Reader::new(fake());
    r.read(t0);
    assert_eq!(r.source.path_calls, 3);
    r.source.usage.insert(10, used(1_500_000_000, 4096));
    let t = r.read(t0 + Duration::from_secs(2));
    let cpu = t.get(10).and_then(|e| e.usage).map(|u| u.cpu_percent);
    assert_eq!(cpu, Some(75.0));
    assert_eq!(r.source.path_calls, 3, "paths come from the cache");
}

#[test]
fn reused_pid_or_exec_reads_the_path_again() {
    let t0 = Instant::now();
    let mut r = Reader::new(fake());
    r.read(t0);
    // pid 10 exits and the pid is reused by a new process.
    r.source.procs[0] = raw(10, 2, "other");
    r.source.paths.insert(10, "/opt/other".to_owned());
    r.source.usage.insert(10, used(9_000_000_000, 1));
    let t = r.read(t0 + Duration::from_secs(1));
    let e = t.get(10).expect("pid 10");
    assert_eq!(&*e.path, "/opt/other");
    assert_eq!(e.usage.map(|u| u.cpu_percent), Some(0.0), "new process");
    // Same pid and start time, but exec changed the short name.
    r.source.procs[0] = raw(10, 2, "execd");
    r.source.paths.insert(10, "/opt/execd".to_owned());
    let t = r.read(t0 + Duration::from_secs(2));
    assert_eq!(&*t.get(10).expect("pid 10").path, "/opt/execd");
}

#[test]
fn unexpected_errors_hide_the_process() {
    let mut f = fake();
    f.usage
        .insert(10, Err(io::Error::from_raw_os_error(libc::EINVAL)));
    let t = Reader::new(f).read(Instant::now());
    assert!(t.get(10).expect("listed").usage.is_none());
}
