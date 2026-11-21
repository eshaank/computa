//! Reads lines from `rex events --all --json` and decides what each one
//! means for the pane map. Only events on an allow-list cause work, so
//! events the daemon causes itself (a CLI client joining and leaving) never
//! trigger another refresh.

use serde::Deserialize;
use serde_json::Value;

use super::model::TERMINAL_CREATOR;

/// What an event asks of the pane map.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Trigger {
    /// Nothing the map shows changed.
    Ignore,
    /// Re-read this session's layout and panes.
    Session(String),
    /// Re-read one pane's processes; the layout did not change.
    Pane { session: String, block: String },
    /// A pane closed: drop it at once, then re-read the session.
    PaneClosed { session: String, block: String },
    /// The session is gone: drop it. There is nothing left to read.
    SessionGone(String),
}

#[derive(Deserialize)]
struct Envelope {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Deserialize)]
struct SessionEvent {
    session_id: String,
    event: Envelope,
}

#[derive(Deserialize)]
struct BlockEvent {
    #[serde(default)]
    block_id: String,
    #[serde(default)]
    creator_name: String,
    #[serde(default)]
    name: String,
}

/// Session events that change what the map shows.
const LAYOUT_EVENTS: [&str; 7] = [
    "block_created",
    "window_created",
    "window_closed",
    "window_label_changed",
    "session_label_changed",
    "session_view_changed",
    "creator_changed",
];

/// Classifies one line.
///
/// # Errors
///
/// Returns the parse error if the line is not an event object.
pub fn classify(line: &str) -> Result<Trigger, serde_json::Error> {
    let top: Envelope = serde_json::from_str(line)?;
    match top.kind.as_str() {
        "session_event" => {
            let ev: SessionEvent = serde_json::from_value(top.payload)?;
            session_event(ev)
        }
        "session_created" => {
            let id = top
                .payload
                .pointer("/session/session_id")
                .and_then(Value::as_str);
            Ok(id.map_or(Trigger::Ignore, |id| Trigger::Session(id.to_owned())))
        }
        "session_destroyed" => {
            let id = top.payload.get("session_id").and_then(Value::as_str);
            Ok(id.map_or(Trigger::Ignore, |id| Trigger::SessionGone(id.to_owned())))
        }
        _ => Ok(Trigger::Ignore),
    }
}

fn session_event(ev: SessionEvent) -> Result<Trigger, serde_json::Error> {
    let session = ev.session_id;
    let kind = ev.event.kind.as_str();
    if kind == "block_closed" {
        let block = ev.event.payload.get("block_id").and_then(Value::as_str);
        return Ok(match block {
            Some(b) => Trigger::PaneClosed {
                session,
                block: b.to_owned(),
            },
            None => Trigger::Session(session),
        });
    }
    if LAYOUT_EVENTS.contains(&kind) {
        return Ok(Trigger::Session(session));
    }
    if kind != "block_event" {
        return Ok(Trigger::Ignore);
    }
    let block: BlockEvent = serde_json::from_value(ev.event.payload)?;
    if block.creator_name != TERMINAL_CREATOR {
        return Ok(Trigger::Ignore);
    }
    Ok(match block.name.as_str() {
        // A builtin `cd` changes the cwd without a new process.
        "process_changed" | "pwd_changed" if !block.block_id.is_empty() => Trigger::Pane {
            session,
            block: block.block_id,
        },
        // The pane's own program ended; the pane may close or stay open.
        "child_exited" | "process_changed" => Trigger::Session(session),
        _ => Trigger::Ignore,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../tests/fixtures/rex-events.jsonl");
    const S: &str = "session:01a1f5ee-a390-7aa6-9f7e-f337eed6d193";
    const B: &str = "block:01a1f7c8-aa28-755f-b366-5c76c59850f0";
    const T: &str = "session:01a1fae8-d190-7c0a-9691-4a219a3bbaa4";
    const TB: &str = "block:01a1fae8-d190-7d32-8288-273ef6151ef4";

    fn session(id: &str) -> Trigger {
        Trigger::Session(id.to_owned())
    }

    fn pane(s: &str, b: &str) -> Trigger {
        Trigger::Pane {
            session: s.to_owned(),
            block: b.to_owned(),
        }
    }

    fn closed(s: &str, b: &str) -> Trigger {
        Trigger::PaneClosed {
            session: s.to_owned(),
            block: b.to_owned(),
        }
    }

    #[test]
    fn every_line_of_the_real_capture_is_classified() {
        use Trigger::Ignore;
        let expected = vec![
            Ignore,                             // client_joined
            Ignore,                             // client_connected
            session(S),                         // block_created
            Ignore,                             // block_owner_changed
            pane(S, B),                         // process_changed, foreground null
            session(S),                         // window_created
            session(S),                         // session_view_changed
            Ignore,                             // block_owner_changed
            session(S),                         // session_view_changed
            Ignore,                             // client_disconnected
            Ignore,                             // client_left
            pane(S, B),                         // process_changed: zsh
            pane(S, B),                         // process_changed: bash
            session(S),                         // child_exited
            closed(S, B),                       // block_closed
            session(S),                         // window_closed
            session(S),                         // session_view_changed
            session(T),                         // session_created
            pane(T, TB),                        // process_changed: sleep
            closed(T, TB),                      // block_closed
            session(T),                         // session_view_changed
            Trigger::SessionGone(T.to_owned()), // session_destroyed
        ];
        let got: Vec<Trigger> = FIXTURE
            .lines()
            .map(|l| classify(l).unwrap_or_else(|e| panic!("{e}: {l}")))
            .collect();
        assert_eq!(got, expected);
    }

    #[test]
    fn other_blocks_and_unknown_events_are_ignored() {
        let web = r#"{"type":"session_event","payload":{"session_id":"session:a","event":{"type":"block_event","payload":{"block_id":"block:w","creator_name":"com.superlogical.web","name":"process_changed","payload":{}}}}}"#;
        assert_eq!(classify(web).expect("parses"), Trigger::Ignore);
        let bell = r#"{"type":"session_event","payload":{"session_id":"session:a","event":{"type":"block_event","payload":{"block_id":"block:t","creator_name":"com.superlogical.terminal","name":"bell","payload":{}}}}}"#;
        assert_eq!(classify(bell).expect("parses"), Trigger::Ignore);
        let pwd = r#"{"type":"session_event","payload":{"session_id":"session:a","event":{"type":"block_event","payload":{"block_id":"block:t","creator_name":"com.superlogical.terminal","name":"pwd_changed","payload":{"pwd":"file://host/tmp"}}}}}"#;
        assert_eq!(classify(pwd).expect("parses"), pane("session:a", "block:t"));
        let future = r#"{"type":"something_new","payload":{"x":1}}"#;
        assert_eq!(classify(future).expect("parses"), Trigger::Ignore);
        assert!(classify("not json").is_err());
    }
}
