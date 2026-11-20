//! The JSON shapes the `rex` CLI prints, keeping only the fields the daemon
//! uses. Unknown fields are ignored, because new Rex versions add them.

use serde::Deserialize;

/// The `creator_name` of terminal blocks. Only these are reported as panes.
pub const TERMINAL_CREATOR: &str = "com.superlogical.terminal";

/// `rex api call session.list`.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct SessionList {
    #[serde(default)]
    pub sessions: Vec<SessionRef>,
}

#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct SessionRef {
    pub session_id: String,
    #[serde(default)]
    pub label: String,
}

/// `rex api call session.view`.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct SessionView {
    pub session_id: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub windows: Vec<WindowView>,
}

/// A tab.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct WindowView {
    pub window_id: String,
    #[serde(default)]
    pub label: String,
    /// Tiled and floating layers; a window can have several.
    #[serde(default)]
    pub layers: Vec<LayerView>,
}

#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct LayerView {
    #[serde(default)]
    pub blocks: Vec<BlockView>,
}

/// A pane.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct BlockView {
    pub block_id: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub creator_name: String,
}

impl WindowView {
    /// The window's terminal blocks over all its layers, in layer order.
    pub fn terminal_blocks(&self) -> impl Iterator<Item = &BlockView> {
        self.layers
            .iter()
            .flat_map(|l| l.blocks.iter())
            .filter(|b| b.creator_name == TERMINAL_CREATOR)
    }
}

/// `rex block call -s SESSION -b BLOCK process`.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct PaneProcess {
    /// The program the terminal started: the pane's root process. Often a
    /// root-owned `login`.
    #[serde(default)]
    pub child: Option<ProcInfo>,
    /// The foreground process. Absent while Rex does not know it.
    #[serde(default)]
    pub foreground: Option<ProcInfo>,
    /// The foreground's ancestors up to `child`, nearest first. Absent when
    /// the foreground is `child` itself.
    #[serde(default)]
    pub ancestors: Vec<ProcInfo>,
}

#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct ProcInfo {
    pub pid: i32,
    /// The executable's file name. For Claude Code this is its version
    /// number, for example "2.1.328".
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub argv0: String,
    #[serde(default)]
    pub cwd: String,
}

/// `rex api call server.version`.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct ServerVersion {
    #[serde(default)]
    pub rex_version: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    const VIEW: &str = include_str!("../../tests/fixtures/session-view.json");
    const CLAUDE: &str = include_str!("../../tests/fixtures/process-claude.json");
    const SLEEP: &str = include_str!("../../tests/fixtures/process-sleep.json");

    #[test]
    fn parses_a_session_list() {
        let list: SessionList = serde_json::from_str(
            r#"{"sessions":[{"session_id":"session:a","label":"work","extra":1}]}"#,
        )
        .expect("parses");
        assert_eq!(list.sessions[0].session_id, "session:a");
        assert_eq!(list.sessions[0].label, "work");
    }

    #[test]
    fn collects_terminal_blocks_from_every_layer() {
        let view: SessionView = serde_json::from_str(VIEW).expect("parses");
        assert_eq!(view.label, "rex-menubar-monitor");
        assert_eq!(view.windows.len(), 1);
        let w = &view.windows[0];
        assert_eq!(w.layers.len(), 2, "tiled and floating");
        let ids: Vec<_> = w.terminal_blocks().map(|b| b.block_id.as_str()).collect();
        assert_eq!(
            ids,
            vec![
                "block:01a1f5ee-a390-7e21-95d4-e4469a55c5c6",
                "block:01a1f7bf-c9f3-7c19-ad31-1bb1a2fd4b4f",
                "block:01a1f755-40d0-78ca-9a4b-3f09144a62f6",
                "block:floating-terminal",
            ],
            "the non-terminal block is left out"
        );
    }

    #[test]
    fn parses_a_claude_pane_with_a_root_owned_login() {
        let p: PaneProcess = serde_json::from_str(CLAUDE).expect("parses");
        let child = p.child.expect("child");
        assert_eq!((child.pid, child.name.as_str()), (11827, "login"));
        let fg = p.foreground.expect("foreground");
        assert_eq!((fg.name.as_str(), fg.argv0.as_str()), ("2.1.328", "claude"));
        assert_eq!(fg.cwd, "/Users/eshaan/Documents/computa");
        assert_eq!(p.ancestors.len(), 2);
        assert_eq!(p.ancestors[0].argv0, "-zsh");
    }

    #[test]
    fn parses_a_command_pane_and_a_null_foreground() {
        let p: PaneProcess = serde_json::from_str(SLEEP).expect("parses");
        assert_eq!(p.child.as_ref().map(|c| c.pid), Some(42009));
        assert!(p.ancestors.is_empty());
        let none: PaneProcess =
            serde_json::from_str(r#"{"last_exit":null,"child":{"pid":5},"foreground":null}"#)
                .expect("parses");
        assert!(none.foreground.is_none());
    }

    #[test]
    fn parses_the_server_version() {
        let v: ServerVersion = serde_json::from_str(
            r#"{"rex_version":"0.1.0-preview.14","platform":"darwin_arm64","api_revision":12}"#,
        )
        .expect("parses");
        assert_eq!(v.rex_version, "0.1.0-preview.14");
    }
}
