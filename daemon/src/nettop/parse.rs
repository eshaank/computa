//! Parses what `nettop -P -x -L 0 -J bytes_in,bytes_out` prints: a header
//! line, then one line per process, once per sample:
//!
//! ```text
//! ,bytes_in,bytes_out,
//! apsd.381,462906,832250,
//! Google Chrome H.737,1115009250,195463,
//! ```
//!
//! The counters are bytes since `nettop` started watching (for a process
//! that already had connections, since those connections opened). They are
//! totals, not deltas: each sample repeats and grows them.

use std::collections::HashMap;
use std::time::Instant;

/// The header `nettop` prints before each sample, for the columns asked for.
pub const HEADER: &str = ",bytes_in,bytes_out,";

/// One process's counters in one sample.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Counter {
    /// `nettop`'s short name, which may be cut off ("Google Chrome H").
    pub name: Box<str>,
    pub rx: u64,
    pub tx: u64,
}

/// One whole sample.
#[derive(Debug, Clone, PartialEq)]
pub struct Reading {
    /// Which run of `nettop` it came from. Counters restart with each run.
    pub run: u64,
    /// Counts samples within the run, from 1.
    pub seq: u64,
    /// When its header line arrived.
    pub at: Instant,
    pub counters: HashMap<i32, Counter>,
}

/// One process line: `name.pid,bytes_in,bytes_out,`. The name may contain
/// dots and commas, so the numbers are split off from the right and the pid
/// at the last dot. `None` if the line is not in that form.
pub fn parse_row(line: &str) -> Option<(i32, Counter)> {
    let body = line.strip_suffix(',').unwrap_or(line);
    let mut fields = body.rsplitn(3, ',');
    let tx = fields.next()?.parse().ok()?;
    let rx = fields.next()?.parse().ok()?;
    let (name, pid) = fields.next()?.rsplit_once('.')?;
    let pid = pid.parse().ok()?;
    Some((
        pid,
        Counter {
            name: name.into(),
            rx,
            tx,
        },
    ))
}

/// Splits output into lines, keeping a partial last line for the next
/// chunk. A pty ends lines with `\r\n`; the `\r` is dropped.
#[derive(Debug, Default)]
pub struct LineBuffer {
    partial: Vec<u8>,
}

impl LineBuffer {
    pub fn push(&mut self, bytes: &[u8]) -> Vec<String> {
        self.partial.extend_from_slice(bytes);
        let Some(last) = self.partial.iter().rposition(|&b| b == b'\n') else {
            return Vec::new();
        };
        let rest = self.partial.split_off(last + 1);
        let done = std::mem::replace(&mut self.partial, rest);
        done.split(|&b| b == b'\n')
            .map(|l| String::from_utf8_lossy(l.strip_suffix(b"\r").unwrap_or(l)).into_owned())
            .filter(|l| !l.is_empty())
            .collect()
    }
}

/// Collects lines into samples. A sample is complete when the next header
/// arrives, so the newest one is always a second behind.
#[derive(Debug)]
pub struct Assembler {
    run: u64,
    seq: u64,
    current: Option<(Instant, HashMap<i32, Counter>)>,
}

impl Assembler {
    pub fn new(run: u64) -> Self {
        Self {
            run,
            seq: 0,
            current: None,
        }
    }

    /// Takes one line that arrived at `at`. Returns the sample it completed,
    /// if any.
    ///
    /// # Errors
    ///
    /// Returns the line itself if it is neither the header nor a process
    /// line, or a process line came before the first header.
    pub fn line(&mut self, line: &str, at: Instant) -> Result<Option<Reading>, String> {
        let line = line.trim();
        if line.is_empty() {
            return Ok(None);
        }
        if line == HEADER {
            let done = self.current.replace((at, HashMap::new()));
            return Ok(done.map(|(started, counters)| {
                self.seq += 1;
                Reading {
                    run: self.run,
                    seq: self.seq,
                    at: started,
                    counters,
                }
            }));
        }
        match (parse_row(line), self.current.as_mut()) {
            (Some((pid, counter)), Some((_, counters))) => {
                counters.insert(pid, counter);
                Ok(None)
            }
            _ => Err(line.to_owned()),
        }
    }
}

#[cfg(test)]
#[path = "parse_tests.rs"]
mod tests;
