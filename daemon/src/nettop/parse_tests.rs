use std::time::Duration;

use super::*;

/// Two samples as this machine's `nettop` printed them on a pty, with the
/// second one split across two reads in the middle of a line.
const FIRST: &[u8] = b",bytes_in,bytes_out,\r\napsd.381,462906,832250,\r\n\
Google Chrome H.737,1115009250,195463,\r\n2.1.330.62154,1694289,129500610,\r\n";
const SECOND_A: &[u8] = b",bytes_in,bytes_out,\r\napsd.381,463341,838";
const SECOND_B: &[u8] = b"798,\r\nmDNSResponder.499,371336655,105337463,\r\n";
const THIRD: &[u8] = b",bytes_in,bytes_out,\r\n";

fn counter(name: &str, rx: u64, tx: u64) -> Counter {
    Counter {
        name: name.into(),
        rx,
        tx,
    }
}

#[test]
fn rows_split_the_pid_at_the_last_dot() {
    assert_eq!(
        parse_row("apsd.381,462906,832250,"),
        Some((381, counter("apsd", 462_906, 832_250)))
    );
    // Claude Code's executable is named after its version.
    assert_eq!(
        parse_row("2.1.330.62154,1694289,129500610,"),
        Some((62154, counter("2.1.330", 1_694_289, 129_500_610)))
    );
    assert_eq!(
        parse_row("Google Chrome H.737,10,20,"),
        Some((737, counter("Google Chrome H", 10, 20)))
    );
    assert_eq!(
        parse_row("odd, name.9,1,2,"),
        Some((9, counter("odd, name", 1, 2)))
    );
    assert_eq!(
        parse_row("launchd.1,0,0"),
        Some((1, counter("launchd", 0, 0)))
    );
}

#[test]
fn malformed_rows_are_refused() {
    for line in [
        "nettop: NStatManagerCreate failed",
        "noprefix,1,2,",
        "name.x,1,2,",
        "name.5,1,",
        "name.5,-1,2,",
        "name.5,1,2.5,",
        "",
    ] {
        assert_eq!(parse_row(line), None, "{line:?}");
    }
}

#[test]
fn lines_keep_a_partial_tail_and_drop_carriage_returns() {
    let mut buf = LineBuffer::default();
    assert_eq!(buf.push(b"ab"), Vec::<String>::new());
    assert_eq!(buf.push(b"c\r\nde\r"), vec!["abc"]);
    assert_eq!(buf.push(b"\n\r\nf\n"), vec!["de", "f"]);
}

#[test]
fn a_sample_completes_when_the_next_header_arrives() {
    let t0 = Instant::now();
    let t1 = t0 + Duration::from_secs(1);
    let mut lines = LineBuffer::default();
    let mut asm = Assembler::new(7);
    let mut done = Vec::new();
    for (chunk, at) in [(FIRST, t0), (SECOND_A, t1), (SECOND_B, t1), (THIRD, t1)] {
        for line in lines.push(chunk) {
            done.extend(asm.line(&line, at).expect("parses"));
        }
    }
    assert_eq!(done.len(), 2, "the third sample is not complete yet");
    let (a, b) = (&done[0], &done[1]);
    assert_eq!((a.run, a.seq, a.at), (7, 1, t0));
    assert_eq!(a.counters.len(), 3);
    assert_eq!(
        a.counters[&737],
        counter("Google Chrome H", 1_115_009_250, 195_463)
    );
    assert_eq!((b.seq, b.at), (2, t1));
    assert_eq!(b.counters[&381], counter("apsd", 463_341, 838_798));
    assert_eq!(b.counters[&499].rx, 371_336_655);
}

#[test]
fn an_error_message_or_a_row_before_any_header_is_an_error() {
    let now = Instant::now();
    let mut asm = Assembler::new(1);
    assert_eq!(
        asm.line("apsd.381,1,2,", now),
        Err("apsd.381,1,2,".to_owned())
    );
    let msg = "nettop: NStatManagerCreate failed";
    assert_eq!(asm.line(msg, now), Err(msg.to_owned()));
    assert_eq!(asm.line(HEADER, now), Ok(None));
    assert_eq!(asm.line("   ", now), Ok(None));
    assert_eq!(asm.line(",bytes_out,bytes_in,", now).ok(), None);
}
