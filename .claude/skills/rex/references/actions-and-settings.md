# Built-in actions & settings (macOS, iOS)

**When to read this:** you need the exact name of a built-in Rex action (to `rex.bind`, run with `rex do`, or queue with `rex.client.queue`) or want to know which setting exists, what values it takes, and where it lives in the Settings UI.
Mac is the superset; iOS is a strict subset of Mac action names plus 3 iOS-only actions (section 4).
The reference pages document names, titles, default keys and one-line purposes only. They do NOT document per-action argument schemas, setting value types, defaults, or a Lua settings API (see section 1 for how to discover those).

---

## 1. How actions and settings are named, invoked, and configured

### 1.1 Action naming
- Dotted lowercase names with underscores inside segments: `pane.split.left`, `client.tab.recent.in_session`, `session.new.on_host`.
- Prefix tells the owner: `client.*` = performed by the app (client) UI; `pane.*` = a block (pane) in the focused tab; `session.*` = session-level. Names containing a dot are built-in (client/block provided). Your own custom actions must NOT contain a dot (`rex.action{ name = "scratch", ... }`).
- Actions are provided by the connected client, so the list depends on the client (Mac vs iOS). Authoritative per-client list WITH argument names: `rex client ls` then `rex -C <client-label> actions` (output columns `NAME TITLE ARGS`; a trailing `?` on an arg means optional). Example from the docs: `client.tab.goto index`, `pane.split direction`, `pane.resize direction, amount?`, `pane.send_key key`.
- Known argument names confirmed in other Rex docs (not in the four reference pages): `pane.split {direction}` (left/right/up/down), `pane.resize {direction, amount?}`, `client.tab.goto {index}`, `pane.send_key {key}` (e.g. `"ctrl+l"`), `client.mode.enter {name}`. Always check `rex -C <label> actions` for the rest.
- Title shown in the command palette and menus is the "Action" column below (e.g. "Split Pane Right"); the "Name" is what you bind/run.

### 1.2 Ways to invoke an action
| Where | How |
| --- | --- |
| Key binding (Lua, `init.lua`) | `rex.bind("cmd+d", "pane.split", { direction = "right" })` -> `rex.bind(key, action, args)`; newest binding for a key wins; `rex.unbind("cmd+d")` / `rex.unbind("cmd+t", "client.tab.new")` removes defaults. Sequences `"ctrl+b>c"`, modes `"resize/left"`. |
| Command palette | Mac `shift+cmd+p` (`client.palette.toggle`); searches titles + hidden keywords. |
| CLI | `rex do <action> [KEY=VALUE ...]` (add `--json`); e.g. `rex do client.tab.new`. Built-in `client.*` actions run only if the target app has **Remote Control** on (Settings > Server > Client Info). Target a specific client with `rex -C <label> ...`. |
| Lua / scripts | `rex.client.queue("pane.zoom")` (asks the client that ran the action to run a client action; errors when run from CLI with no client); custom actions run other custom actions via `rex.invoke`. |
| Server API | Same names; see the Server API reference. |
| Config reload | `rex config reload` (server-side only); `rex config check` validates; `rex keymap` shows the merged result and flags unknown action names. |

Misspelled action names are not caught from the file alone (the client provides the action list); `rex keymap` does catch them.

### 1.3 Settings
- Settings are changed in the app UI: Mac `cmd+,` (`client.settings`) -> Settings > <Section> > <Page>; iOS Settings app screen. Each setting below lists its page.
- Almost every UI setting is also exposed as an **action** named `client.setting.<group>.<...>` (listed in 3.10 for Mac, 4.3 for iOS). Running it (`rex do client.setting.terminal.cursor.style ...`, palette entry, or `rex.bind`) drives the same setting. The reference does not document the argument/value shape of these actions; check `rex -C <label> actions` for the ARGS column.
- The reference pages do **not** document a Lua settings API (`init.lua` is for bindings, actions, modes, hosts and scripts). Do not invent one; set settings via UI or the `client.setting.*` actions.
- Types/defaults are not documented; the "Values / notes" column below records exactly the choices the descriptions mention. Where defaults are implied they are noted ("default ...").
- Items tagged "Bleeding Edge" in the source are available only on the Bleeding Edge update channel (Settings > Developer > App Version > Update Channel; needs Developer Mode). The markdown source has the tag stripped, so per-item tags are not recoverable here.
- Config file: `$XDG_CONFIG_HOME/rex/init.lua` or `~/.config/rex/init.lua` (macOS/Linux), `%AppData%\rex\init.lua` (Windows), override with `REX_CONFIG`. Action `client.config.copy_path` copies the path; `client.config.reload` reloads it.

---

## 2. Mac action index (228 actions)

Column notes: **Key** = default shortcut (empty = none). **iOS** = `y` if the same name exists in the iOS palette. Purpose is the doc's one-liner (or the title when no description is given).

### 2.1 Window
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `client.window.new` | `cmd+n` | y | New Window (create workspace window) |
| `client.window.close` | `shift+cmd+w` | y | Close Window |
| `client.window.fullscreen.toggle` | `ctrl+cmd+f` | | Toggle Full Screen |
| `client.close` | `cmd+w` | y | Close: focused pane, else selected tab, else the window |

### 2.2 App
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `client.palette.toggle` | `shift+cmd+p` | y | Command Palette |
| `client.settings` | `cmd+,` | y | Settings |
| `client.diagnostics` | `shift+cmd+,` | y | Rex Diagnostics (logs, server report) |
| `client.onboarding` | | | Open Onboarding Session (welcome, import keybindings/theme from ghostty/tmux/zellij, agent setup) |
| `client.permissions` | | | Grant System Permissions (full disk access, screen recording, system audio, TCC) |
| `client.visibility.toggle` | | | Toggle Visibility: show Rex from any app, or hide when frontmost (global-hotkey use) |
| `client.version.copy` | | y | Copy Version Info (app + server versions) |
| `client.debug.copy` | | y | Copy Debug Info (app, system, server, host state report) |
| `client.pair_device` | | | Pair Device with QR Code (iPhone/iPad, Tailscale) |
| `client.update.accept` | `shift+cmd+u` | | Install Update (menu shows the update's own title; static fallback) |
| `client.update.accept_when_idle` | `alt+shift+cmd+u` | | Relaunch when Idle: relaunch into downloaded update once windows are out of sight |
| `client.update.check` | | | Check for Updates in Background; silent, returns what it found |
| `client.update.status` | | | Report Update Status: running version, update settings, updater state |
| `client.update.install` | | | Install Update and Relaunch: download if needed, install, relaunch without asking |
| `client.update.set_automation` | | | Set Update Automation: only offer / download / install updates |
| `client.update.set_channel` | | | Set Update Channel (Preview vs Bleeding Edge) |
| `client.notice.dismiss` | `shift+cmd+.` | | Dismiss Notice (banner/alert) |
| `client.shortcuts.edit` | | | Change Shortcut (record/rebind a key) |
| `client.agents.setup` | | y | Install Rex for Agents: installs the Rex skill + hooks for Claude Code, Codex, others |
| `client.server.restart` | | | Restart Server: stops and restarts the local Rex server |

### 2.3 Session
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `session.new` | `shift+cmd+n` | y | New Session |
| `session.new.on_host` | `alt+shift+cmd+n` | | New Session on Host (choose remote host) |
| `session.switch` | `cmd+k` | y | Change Session (picker) |
| `session.select` | | y | Go to Session (by identifier/id) |
| `session.next` | | y | Next Session |
| `session.previous` | | y | Previous Session |
| `session.back` | | | Go Back One Session; repeat to keep going back (history) |
| `session.recent` | | | Go to Recent Session; use again to return (toggle) |
| `session.rename` | | y | Rename Session |
| `session.close` | | y | Close Session |
| `session.refresh` | `cmd+r` | y | Refresh Sessions |
| `session.collapse` | | | Collapse Session (sidebar tabs) |
| `session.expand` | | | Expand Session |
| `session.collapse_others` | | | Collapse Other Sessions |

### 2.4 Host
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `client.host.switch` | | | Switch Host |
| `client.host.add` | | y | Add Remote Host (url http/https) |
| `client.host.remove` | | y | Remove Host |
| `client.host.forward_port` | | y | Forward Port (tunnel, like ssh -L) |

### 2.5 Tab (tab = window inside a session)
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `client.tab.new` | `cmd+t` | y | New Tab |
| `client.tab.close` | `alt+cmd+w` | y | Close Tab |
| `client.tab.close_others` | | y | Close Other Tabs |
| `client.tab.rename` | | y | Rename Tab |
| `client.tab.next` | `ctrl+tab`, `shift+cmd+]` | y | Show Next Tab |
| `client.tab.previous` | `ctrl+shift+tab`, `shift+cmd+[` | y | Show Previous Tab |
| `client.tab.back` | | | Go Back One Tab (any session); repeat to keep going back |
| `client.tab.back.in_session` | | | Go Back One Tab in Session |
| `client.tab.recent` | | | Go to Recent Tab (any session); toggle |
| `client.tab.recent.in_session` | `cmd+'` | | Go to Recent Tab in Session; toggle |
| `client.tab.goto` | `cmd+[Digit1]` ... `cmd+[Digit9]` | y | Go to Tab (arg `index`) |
| `client.tab.move` | | y | Move Tab |
| `client.tab.move.backward` | `ctrl+shift+pageup` | y | Move Tab Backward |
| `client.tab.move.forward` | `ctrl+shift+pagedown` | y | Move Tab Forward |
| `client.tab.move_to_new_window` | | y | Move Tab to New Window (tear off) |
| `client.tab.mute` | | | Mute Tab (silence sound/notification/alert/badge) |

### 2.6 Pane (pane = block)

#### Split / focus / move / float
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `pane.split` | | y | Split Pane (arg `direction`) |
| `pane.split.left` | `shift+cmd+left` | y | Split Pane Left |
| `pane.split.right` | `cmd+d`, `shift+cmd+right` | y | Split Pane Right |
| `pane.split.up` | `shift+cmd+up` | y | Split Pane Up |
| `pane.split.down` | `shift+cmd+d`, `shift+cmd+down` | y | Split Pane Down |
| `pane.split.auto` | `cmd+enter` | y | Split Pane Best Fit |
| `pane.focus` | | | Focus Pane |
| `pane.focus.left` | `alt+cmd+left` | y | Focus Pane Left |
| `pane.focus.right` | `alt+cmd+right` | y | Focus Pane Right |
| `pane.focus.up` | `alt+cmd+up` | y | Focus Pane Up |
| `pane.focus.down` | `alt+cmd+down` | y | Focus Pane Down |
| `pane.focus_next` | `cmd+]` | y | Focus Next Pane |
| `pane.focus_previous` | `cmd+[` | y | Focus Previous Pane |
| `pane.focus_back` | | | Go Back One Pane (any tab/session); repeat |
| `pane.focus_back.in_tab` | | | Go Back One Pane in Tab |
| `pane.focus_back.in_session` | | | Go Back One Pane in Session |
| `pane.focus_recent` | | | Go to Recent Pane (any tab/session); toggle |
| `pane.focus_recent.in_tab` | `cmd+;` | | Go to Recent Pane in Tab; toggle |
| `pane.move` | | | Move Pane (swap/rearrange) |
| `pane.move.left` | `alt+shift+cmd+left` | y | Move Pane Left |
| `pane.move.right` | `alt+shift+cmd+right` | y | Move Pane Right |
| `pane.move.up` | `alt+shift+cmd+up` | y | Move Pane Up |
| `pane.move.down` | `alt+shift+cmd+down` | y | Move Pane Down |
| `pane.float` | `alt+cmd+enter` | y | Float Pane (dock/undock overlay) |
| `pane.new_floating` | | y | New Floating Pane (scratchpad popup) |
| `pane.minimize_floating` | `alt+cmd+m` | y | Minimize Floating Window (toggle) |
| `pane.minimize_all_floating` | `alt+shift+cmd+enter` | y | Minimize Floating Windows (all, toggle) |
| `pane.zoom` | `shift+cmd+enter` | y | Zoom Pane (maximize/restore) |
| `pane.close` | `cmd+w` | y | Close Pane |
| `pane.close_others` | | y | Close Other Panes |
| `pane.balance` | | y | Balance Splits |
| `pane.resize` | | y | Resize Pane (args `direction`, `amount?`) |
| `pane.move_to_new_tab` | | y | Move Pane to New Tab |
| `pane.move_to_tab` | | y | Move Pane to Tab (existing tab) |

#### Navigate / insert / identify / clipboard
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `pane.go_to_directory` | `shift+cmd+g` | y | Go to Directory (cd / open in new tab) |
| `pane.go_to` | `cmd+p` | y | Go to Anything (pane/block/tab/session/agent tree search) |
| `pane.view_activity` | | y | View Activity (working/blocked/failed/done programs) |
| `pane.insert_path` | `ctrl+cmd+i` | y | Insert Path (browse and type a path at the cursor) |
| `pane.insert_photo` | | y | Insert Photo: send library photos to the terminal and type their paths |
| `pane.insert_file` | | y | Insert File: send files from this device and type their paths |
| `pane.copy_id` | | y | Copy Block ID (focused block id; use as agent/CLI target) |
| `pane.rename` | | y | Rename Pane |
| `pane.paste` | | y | Paste into Pane (clipboard to focused terminal) |
| `pane.copy` | | y | Copy from Pane (selection to clipboard) |
| `pane.select_all` | | y | Select All in Pane (incl. scrollback) |
| `pane.send_key` | `cmd+backspace`, `cmd+left`, `cmd+right`, `alt+left`, `alt+right` | y | Send Key: send one key to the focused terminal as if pressed there (arg `key`) |
| `client.key.forward` | | | Send Key to Server: forwards the key that triggered it to the focused terminal, for a Lua script to answer |
| `client.prompt.previous` | `cmd+up` | y | Jump to Previous Prompt (shell integration marks) |
| `client.prompt.next` | `cmd+down` | y | Jump to Next Prompt |
| `client.scroll.page_up` | | y | Scroll Page Up |
| `client.scroll.page_down` | | y | Scroll Page Down |
| `client.quick_look` | `cmd+y` | | Quick Look: preview files and web links on screen |

#### Copy mode (vim/tmux-style keyboard selection; all Mac-only)
| Name | Key(s) | Purpose |
| --- | --- | --- |
| `pane.copy_mode.enter` | `shift+cmd+c` | Enter Copy Mode (move through scrollback and select with keyboard) |
| `pane.copy_mode.exit` | `esc`, `q` | Exit Copy Mode (scrolls back to where it was) |
| `pane.copy_mode.move` | `h` `left` `l` `right` `k` `up` `j` `down` `w` `b` `e` `shift+w` `shift+b` `shift+e` `0` `home` `shift+6` `shift+4` `end` `shift+h` `shift+m` `shift+l` `ctrl+u` `ctrl+d` `ctrl+b` `pageup` `ctrl+f` `pagedown` `g` `shift+g` `shift+[` `shift+]` | Move Copy Mode Cursor by char/word/line/screen/paragraph |
| `pane.copy_mode.select` | `v`, `shift+v`, `ctrl+v` | Start/end char, line or block selection |
| `pane.copy_mode.swap_ends` | `o` | Move cursor to the other end of the selection |
| `pane.copy_mode.yank` | `y`, `enter` | Copy selection to clipboard and leave copy mode |
| `pane.copy_mode.copy_to_line_end` | `shift+d` | Yank from cursor to end of line and leave |
| `pane.copy_mode.search` | `/`, `shift+/` | Search scrollback from cursor (forward/backward) |
| `pane.copy_mode.search_again` | `n`, `shift+n` | Next/previous match of last search |
| `pane.copy_mode.find` | `f`, `shift+f`, `t`, `shift+t` | Find character in cursor's line (find/till) |
| `pane.copy_mode.find_again` | `;`, `,` | Repeat last character find (same/reverse) |
| `pane.copy_mode.count` | `0`-`9` | Type a count prefix for the next motion |

### 2.7 Keys (modes; all Mac-only)
| Name | Key | Purpose |
| --- | --- | --- |
| `client.mode.enter` | | Enter Mode: makes the keys a mode binds active until left (arg `name`; bind keys as `"<mode>/<key>"`) |
| `client.mode.exit` | | Exit Mode (the current one) |
| `client.mode.exit_all` | | Exit All Modes |

### 2.8 Find (Mac-only)
| Name | Key | Purpose |
| --- | --- | --- |
| `client.find.open` | `cmd+f` | Find (scrollback text, highlight) |
| `client.find.next` | `cmd+g` | Find Next |
| `client.find.previous` | `shift+cmd+g` | Find Previous |

### 2.9 View
| Name | Key | iOS | Purpose |
| --- | --- | --- | --- |
| `client.font.increase` | `shift+cmd+=`, `cmd+=` | y | Increase Font Size |
| `client.font.decrease` | `cmd+-` | y | Decrease Font Size |
| `client.font.reset` | `cmd+[Digit0]` | y | Reset Font Size |
| `client.sidebar.toggle` | `cmd+/` | y | Toggle Sidebar |
| `client.sidebar.activity.toggle` | `cmd+.` | y | Toggle Activity (filter to working/waiting/attention programs) |
| `client.sidebar.activity.by_session` | | | Show Activity by Session |
| `client.sidebar.activity.by_priority` | | | Show Activity by Priority (blocked/failed/done/working/idle) |
| `client.sidebar.filter.focus` | | y | Focus Tab Filter (search tabs/sessions/hosts) |
| `client.tab_style.toggle` | `shift+cmd+s` | | Toggle Toolbar Layout (horizontal/vertical) |
| `client.toolbar.reveal` | `alt+cmd+t` | | Reveal Toolbar (peek when auto-hidden) |
| `client.pane_header.reveal` | `alt+shift+cmd+t` | | Reveal Pane Header (peek when hidden) |
| `client.theme.change` | | y | Change Theme |
| `client.theme.import` | | | Import Theme File (Ghostty theme or iTerm color file; selects it) |
| `client.appearance.switch_mode` | | y | Switch Appearance Mode (light/dark) |
| `client.config.copy_path` | | y | Copy Config File Path (init.lua location) |
| `client.config.reload` | | | Reload Config (reread init.lua) |

### 2.10 Setting actions (`client.setting.<suffix>`)
Each is the action form of a Settings entry (cross-reference with section 3). Prefix every suffix with `client.setting.`. Value shape/args are not documented; see `rex -C <label> actions`. **iOS** = `y` if present on iOS.

| Suffix | Title | iOS | Purpose |
| --- | --- | --- | --- |
| `notifications.overview.position` | Notification Position | | Where floating notifications appear in the window |
| `notifications.activity.tab_activity` | Show Activity in Tabs | | Show/hide program activity on tabs |
| `notifications.activity.idle_in_activity` | Include Idle Processes in Activity | | Keep idle-program tabs in Activity filter/popup |
| `notifications.activity.system_notifications` | Show System Notifications | | System notification when a program reports status in background |
| `notifications.activity.dock_badge` | Badge Dock Icon | | Dock icon count of tabs needing attention |
| `notifications.activity.sounds` | Play Activity Sounds | | Sound when a program is blocked/fails/finishes |
| `notifications.activity.sound_volume` | Activity Sound Volume | | Loudness of activity sounds |
| `notifications.activity.status_working` | Working Status Activity | | What Rex does for working programs |
| `notifications.activity.status_blocked` | Blocked Status Activity | | What Rex does for programs waiting for an answer |
| `notifications.activity.status_error` | Error Status Activity | | What Rex does for programs reporting an error |
| `notifications.activity.status_done` | Done Status Activity | | What Rex does for programs that finish |
| `notifications.macos.terminal_notifications` | Terminal Notifications | | Let terminal programs send native notifications (OSC 9/777) |
| `interface.appearance.scheme` | Color Scheme | y | Follow system, or always light/dark |
| `interface.appearance.style` | Interface Style | | Glass or Classic materials |
| `interface.appearance.tint` | Tint with Theme | y | Apply theme colors to interface surfaces |
| `interface.appearance.glass` | Use Glass for Panes | | Glass on panes while Glass style is chosen |
| `interface.toolbar.layout` | Toolbar Layout | | Toolbar/tabs above panes or down either side |
| `interface.toolbar.auto_hide_toolbar` | Toolbar Behavior | | Always show, show on hover, or hidden |
| `interface.tab_behavior.fill` | Tabs Fill Available Space | | Horizontal tabs fill the tab bar equally |
| `interface.tabs.color` | Use Color for Tab Icons | | When tab icons draw in color |
| `interface.tabs.shell_icon_theme` | Shell Icon Theme | | How shell icons are colored |
| `interface.tabs.count` | Tab Icon Count | | How many pane icons a tab shows |
| `interface.panes.density` | Pane Style | | Comfortable or Compact |
| `interface.panes.headers` | Pane Header Behavior | | Always, on hover, or hidden |
| `interface.window.sidebar_text_size` | Sidebar Text Size | | Size of session/tab titles in sidebar |
| `interface.window.window_width` | Preserve Width When Resizing Sidebar | | Keep window width when sidebar shows/hides |
| `interface.window.sidebar_swipe` | Sidebar Swipe Gesture | | Which swipe shows/hides the sidebar |
| `interface.pane_padding.horizontal` | Padding X | | Space left/right of terminal text |
| `interface.pane_padding.vertical` | Padding Y | | Space below text (and above when headers hidden) |
| `interface.pane_padding.color` | Fill Padding with Program Colors | | Let a full-screen program color the padding |
| `interface.pane_padding.program_background` | Include Pane Header in Program Colors | | Color the pane header to match the program |
| `interface.active_panes.active_border` | Highlight Active Pane Edges | y | Highlight focused pane edges |
| `interface.active_panes.active_border_color` | Active Pane Highlight Color | y | Highlight color |
| `interface.active_panes.active_border_opacity` | Active Pane Highlight Opacity | y | Highlight strength |
| `interface.active_panes.active_border_animation` | Animate Active Pane Highlight | y | Fade, move, or instant switch |
| `interface.active_panes.fade` | Fade Inactive Panes | | Fade surfaces, content, both, or neither |
| `interface.active_panes.inactive_window` | Fade Panes for Inactive Windows | | Fade panes in windows not in front |
| `interface.splits_focus.autobalance` | Autobalance Splits | y | Even resize when a pane opens/closes |
| `interface.splits_focus.focus_follows_mouse` | Focus Follows Mouse | | Focus pane on pointer hover |
| `interface.gestures.use_gestures` | Use Trackpad Gestures | | Pinch/spread/swipe gestures on or off |
| `interface.animation.style` | Animation Style | y | How panes move, open, close |
| `interface.app_icon.selection` | App Icon | | App icon artwork |
| `interface.app_icon.show_app_icon` | Show App Icon | | Icon in Dock, menu bar, or both |
| `interface.launch.show_window` | Show Window on Launch | | Open workspace windows at launch |
| `themes.light.palette` | Light Theme | y | Theme used in light appearance |
| `themes.light.extended_palette` | Use Extended Light Theme Palette | | Theme colors 16-255 vs xterm standard |
| `themes.dark.palette` | Dark Theme | y | Theme used in dark appearance |
| `themes.dark.extended_palette` | Use Extended Dark Theme Palette | | Theme colors 16-255 vs xterm standard |
| `terminal.typography.font` | Terminal Font | y | Terminal typeface |
| `terminal.typography.size` | Terminal Font Size | y | Starting text size |
| `terminal.typography.style` | Terminal Font Style | | Installed face of the font |
| `terminal.typography.line_height` | Line Height | | Space between lines |
| `terminal.advanced_fonts.character_spacing` | Character Spacing | | Tighten/widen characters |
| `terminal.advanced_fonts.ligatures` | Ligatures | | Join `->`, `!=` into single symbols |
| `terminal.advanced_fonts.bold_italic` | Render Bold and Italic | | Bold+italic, one, or neither |
| `terminal.advanced_fonts.synthesize` | Force Bold and Italic Styles | | Faux bold/italic for fonts lacking them |
| `terminal.advanced_fonts.smoothing` | Font Smoothing | | Smooth text edges |
| `terminal.advanced_fonts.fallback_fonts` | Fallback Fonts | | Fonts for missing glyphs |
| `terminal.colors.contrast` | Improve Text Contrast | y | Adjust low-contrast text |
| `terminal.colors.palette` | Force Theme Palette for Text | y | Map RGB/extended colors to nearest theme color |
| `terminal.colors.display_p3` | Use Display P3 Color Space | | Read colors as Display P3 |
| `terminal.cursor.blink` | Cursor Blink Speed | y | Blink speed |
| `terminal.cursor.interval` | Cursor Blink Interval | | Time between blinks |
| `terminal.cursor.style` | Cursor Style | y | Block, bar, underline |
| `terminal.cursor.force` | Force Cursor Style | y | Ignore programs' cursor-shape requests |
| `terminal.cursor.shaders` | Cursor Shaders | y | Trail shader behind cursors |
| `terminal.cursor.shader` | Cursor Shader | y | Which shader effect |
| `terminal.keyboard.sequence_hints` | Show Key Sequence Hints | | Show keys that can follow a sequence prefix |
| `terminal.keyboard.option` | Option Key | | Option sends Alt or types special characters |
| `terminal.scrolling.smooth` | Smooth Scrolling | y | Pixel scrolling |
| `terminal.resizing.smooth` | Smooth Terminal Resizing | y | Reflow on the frame a pane resizes |
| `terminal.selection.copy_on_select` | Copy on Selection | | Auto-copy selection |
| `terminal.selection.play_animation_on_copy` | Play Animation on Copy | | Shine across selection on copy |
| `terminal.selection.foreground` | Selection Foreground | | Text color inside selection |
| `terminal.selection.background` | Selection Background | | Fill behind selected text |
| `terminal.selection.corners` | Rounded Selection Corners | | Round selection corners |
| `terminal.links.custom_schemes` | Links That Open Apps | | Ask/always/never for app-launching links |
| `terminal.path_browser.recent_paths` | Show Recently Used Paths | | Recents first in Insert Path |
| `terminal.titles.prefer_generated` | Prefer Generated Titles | y | Name tabs after running program, not shell title |
| `terminal.shell.command` | Startup Command | | Command a new local terminal runs |
| `remote_hosts.ssh.agent` | SSH Agent | | Agent ssh asks for keys for ssh:// hosts |
| `remote_hosts.ssh.custom_path` | SSH Agent Socket | | Socket path of a custom agent |
| `developer.mode.enabled` | Developer Mode | y | Reveal developer/debug settings |
| `developer.experimental.terminal_anchor` | Terminal Anchoring | | Pin terminal text to top or bottom of pane |
| `developer.experimental.new_quick_switcher` | New Quick Switcher | | One list of every session/block/process from Go to Anything |

---

## 3. Mac settings index

Reference format: **Setting** (UI label) | **Values / notes** (choices named in the doc) | **Action suffix** (`client.setting.<suffix>` from 2.10, `-` = none documented). Path is `Settings > <section heading> > <page heading>`. No defaults/types are documented unless stated.

### 3.1 Integrations
**Coding Agents** (Settings > Integrations > Coding Agents; for Claude Code, Codex, OpenCode, Pi)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Integrate with available agents | on/off; installs Rex skill + session hooks for supported agents (also removes/updates) | - (related: `client.agents.setup`) |

**Agent Behavior** (Settings > Integrations > Agent Behavior)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Let agents name sessions | on/off; agents label the session after their task; shown only while "Integrate with available agents" is on | - |

### 3.2 Notifications
**In-App Notifications** (Settings > Notifications > In-App Notifications)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Notification position | click diagram: top/bottom x left/center/right (6 positions) | `notifications.overview.position` |

**Program Activity** (Settings > Notifications > Program Activity; programs report status e.g. via OSC 7501)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Show activity in tabs | on/off; working dots, progress pies, needs-attention dots/messages on tabs | `notifications.activity.tab_activity` |
| Include idle processes in activity | on/off; keep idle-program tabs in Activity filter/popup even after seen | `notifications.activity.idle_in_activity` |
| Show system notifications | on/off; macOS notification when a program reports status while Rex is backgrounded; click opens its tab | `notifications.activity.system_notifications` |
| Badge Dock icon | on/off; count of tabs with unseen blocked/failed/finished programs | `notifications.activity.dock_badge` |
| Play sounds | on/off; sound on blocked/error/done | `notifications.activity.sounds` |
| Sound volume | slider, quieter to louder than default | `notifications.activity.sound_volume` |
| Working | enable/disable all, or per-channel (tab indicators, notifications, Dock badges, sounds) | `notifications.activity.status_working` |
| Blocked | same; programs waiting for you | `notifications.activity.status_blocked` |
| Error | same; programs reporting errors | `notifications.activity.status_error` |
| Done | same; finished programs | `notifications.activity.status_done` |

**System Notifications** (Settings > Notifications > System Notifications)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Terminal notifications | on/off; programs send native notifications via OSC 9 / OSC 777 | `notifications.macos.terminal_notifications` |
| Tailscale sign-in | on/off; notify when Rex needs Tailscale sign-in | - |
| Tailscale device approval | on/off; notify when a tailnet admin must approve this Mac | - |
| Tailscale failures | on/off; notify when Tailscale stops or errors | - |

### 3.3 Server
**Rex Server** (Settings > Server > Rex Server)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Server status | read-only: running/stopped/preparing/failed, uptime, version + API revision in info popover | - (related: `client.server.restart`) |
| Compatibility | shows update/compat/pending-settings discrepancies; buttons to update or restart server (bundled server or source checkout) | - |

**Remote Address** (Settings > Server > Remote Address)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Remote Address | serving progress + cert readiness, retry, copy address, QR to pair iPhone/iPad | - (related: `client.pair_device`) |

**Tailscale** (Settings > Server > Tailscale)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Serve over Tailscale | on/off; access to Rex over your tailnet | - |
| Preferred Hostname | text; this Mac's Tailscale hostname while serving (assigned may differ) | - |
| Limit access to your Tailscale account | on/off; restrict callers to your account vs allow tailnet members | - |
| Tags | read-only; sign out/in to change | - |
| Control Server | read-only; sign out/in to change | - |
| Sign in to Tailscale | account/sign-out status, hostname + sign in, reopen/cancel enrollment, turn off serving while signed out, sign out | - |

**Client Info** (Settings > Server > Client Info; relates to `rex client ls`, `-C`)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Label | text; names this Mac in client lists and for targeting with `rex -C <label>` | - |
| Remote Control | on/off; lets Rex/other clients perform actions in this app (needed for `rex do client.*` from CLI) | - |

### 3.4 Interface
**Appearance** (Settings > Interface > Appearance)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Color scheme | Auto (follows system) / Light / Dark | `interface.appearance.scheme` |
| Interface style | Glass / Classic | `interface.appearance.style` |
| Tint with theme | on/off; theme colors on interface surfaces | `interface.appearance.tint` |
| Use glass for panes | on/off; only with Glass style | `interface.appearance.glass` |

**Toolbar** (Settings > Interface > Toolbar)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Toolbar layout | Above / Below / Left / Right of panes | `interface.toolbar.layout` |
| Toolbar behavior | Always show / Show on hover / Hidden (until `client.toolbar.reveal`) | `interface.toolbar.auto_hide_toolbar` |

**Tab behavior** (opens from "Customize tabs" under Toolbar)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Tabs fill available space | on/off; horizontal tabs only; backgrounds shown only for 2+ tabs | `interface.tab_behavior.fill` |

**Tab icons** (opens from "Customize tabs")
| Setting | Values / notes | Action |
| --- | --- | --- |
| Use color for tab icons | Always / For active panes / For active tabs / Never | `interface.tabs.color` |
| Shell icon theme | Default artwork / Use theme for background+foreground / Use theme accent for accents | `interface.tabs.shell_icon_theme` |
| Show tab icons | 0-3 pane icons in vertical tabs, up to 5 in horizontal tabs | `interface.tabs.count` |

**Panes**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Pane style | Comfortable / Compact | `interface.panes.density` |
| Pane header behavior | Always show / Show on hover / Hidden | `interface.panes.headers` |

**Window** (only with sidebar/vertical toolbar layouts)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Sidebar text size | size of session/tab titles, or follow macOS "Sidebar icon size" | `interface.window.sidebar_text_size` |
| Preserve width when resizing sidebar | on/off; resize panes instead of window when sidebar toggles | `interface.window.window_width` |
| Use a gesture to toggle the sidebar | swipe / Option-swipe / off (hold Option to scroll sideways instead) | `interface.window.sidebar_swipe` |

**Padding** (opens from "Customize panes")
| Setting | Values / notes | Action |
| --- | --- | --- |
| Padding X | left/right space around terminal text | `interface.pane_padding.horizontal` |
| Padding Y | space below text (and above when headers hidden) | `interface.pane_padding.vertical` |
| Fill with program colors | Off / Automatic / Always (full-screen programs color the padding) | `interface.pane_padding.color` |
| Include pane header | on/off; color header to match program while padding fills | `interface.pane_padding.program_background` |

**Active Pane** (opens from "Customize panes")
| Setting | Values / notes | Action |
| --- | --- | --- |
| Highlight active pane edges | on/off; follows focus | `interface.active_panes.active_border` |
| Highlight color | accent / a terminal palette color / terminal text color | `interface.active_panes.active_border_color` |
| Highlight opacity | strength slider | `interface.active_panes.active_border_opacity` |
| Animate active pane highlight | Fade / Move / Off (instant) | `interface.active_panes.active_border_animation` |
| Fade inactive panes | Surface / Content / Surface & content / Off | `interface.active_panes.fade` |
| Fade panes for inactive windows | on/off; respects the pane fade choice | `interface.active_panes.inactive_window` |

**Splits & Focus** (opens from "Customize panes")
| Setting | Values / notes | Action |
| --- | --- | --- |
| Autobalance splits | on/off; even resize when a pane opens/closes, keeping dragged dividers | `interface.splits_focus.autobalance` |
| Focus follows mouse | on/off; hover focuses pane | `interface.splits_focus.focus_follows_mouse` |

**Floating Windows** (opens from "Customize panes")
| Setting | Values / notes | Action |
| --- | --- | --- |
| Minimized floating windows | pick (or drag to) the tab corner where minimized floating windows line up | - |

**Gestures**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Use trackpad gestures | on/off; spread to zoom a pane, pinch to restore, swipe toggles sidebar | `interface.gestures.use_gestures` |

**Animation**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Animation style | Snappy / Natural / Off (forced Off while macOS Reduce Motion is on) | `interface.animation.style` |

**App Icon**
| Setting | Values / notes | Action |
| --- | --- | --- |
| App Icon | Default - Dynamic / Bright / Twilight | `interface.app_icon.selection` |
| Show app icon | Dock and menu bar / Dock only / menu bar only (while no window open) | `interface.app_icon.show_app_icon` |

**Launch**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Show window on launch | on/off | `interface.launch.show_window` |

### 3.5 Themes
| Page | Setting | Values / notes | Action |
| --- | --- | --- | --- |
| Light Mode | Light theme | custom, default or built-in palette; new/edit/duplicate/delete custom themes, live preview | `themes.light.palette` |
| Light Mode | Use extended theme palette | on/off; theme colors 16-255 vs xterm standard | `themes.light.extended_palette` |
| Dark Mode | Dark theme | same as above for dark | `themes.dark.palette` |
| Dark Mode | Use extended theme palette | on/off | `themes.dark.extended_palette` |
| Import Theme | (import action) | add a Ghostty or iTerm palette to custom themes | - (related: `client.theme.import`) |

### 3.6 Terminal
**Typography**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Terminal font | browse monospaced or all installed fonts | `terminal.typography.font` |
| Font size | points | `terminal.typography.size` |
| Font style | installed face (e.g. Light, Book) | `terminal.typography.style` |
| Font weight | stroke weight of a variable font | - |
| Line height | add/remove space between lines | `terminal.typography.line_height` |

**Advanced Font Settings** (opens from "Advanced font settings" under Typography)
| Setting | Values / notes | Action |
| --- | --- | --- |
| Character spacing | tighten/widen, in pixels or percent | `terminal.advanced_fonts.character_spacing` |
| Ligatures | on/off | `terminal.advanced_fonts.ligatures` |
| Render bold and italic | both / bold only / italic only / neither | `terminal.advanced_fonts.bold_italic` |
| Force bold and italic styles | on/off; faux styles; shown only for fonts lacking native styles | `terminal.advanced_fonts.synthesize` |
| Font smoothing | smooth text edges | `terminal.advanced_fonts.smoothing` |
| Fallback fonts | ordered list for missing glyphs | `terminal.advanced_fonts.fallback_fonts` |

**Colors**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Improve text contrast | on/off; included when using theme palette | `terminal.colors.contrast` |
| Force theme palette for text | on/off; nearest theme color, then contrast fix | `terminal.colors.palette` |
| Use Display P3 color space | on/off; like Ghostty window-colorspace | `terminal.colors.display_p3` |

**Cursor**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Blink speed | Off / Slow / Normal / Fast / Custom | `terminal.cursor.blink` |
| Blink interval | milliseconds; applies when Blink speed = Custom | `terminal.cursor.interval` |
| Cursor style | block / bar / underline | `terminal.cursor.style` |
| Force style | on/off; ignore apps' shape requests | `terminal.cursor.force` |
| Cursor shaders | on/off; trail shader behind cursors | `terminal.cursor.shaders` |
| Shader | Warp, Comet, Blaze (also sweep, tapered, rainbow, gradient, frozen per keywords); needs Cursor shaders on | `terminal.cursor.shader` |

**Keyboard**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Show key sequence hints | on/off; which-key style popup after first key of a sequence (e.g. tmux prefix) | `terminal.keyboard.sequence_hints` |
| Option key | Option sends Alt, or types special characters (left/right) | `terminal.keyboard.option` |

**Scrolling / Resizing**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Smooth scrolling | on/off; pixel vs line scroll | `terminal.scrolling.smooth` |
| Smooth terminal resizing | on/off; reflow on the frame a pane changes size, without waiting for server | `terminal.resizing.smooth` |

**Selection**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Copy on selection | on/off | `terminal.selection.copy_on_select` |
| Play animation on copy | on/off | `terminal.selection.play_animation_on_copy` |
| Selection foreground | color | `terminal.selection.foreground` |
| Selection background | color | `terminal.selection.background` |
| Rounded corners | on/off | `terminal.selection.corners` |

**Links / Path Browser / Titles / Shell**
| Setting | Values / notes | Action |
| --- | --- | --- |
| Links that open apps | Ask before / Always / Never open links like ssh:// that launch another app | `terminal.links.custom_schemes` |
| Trusted links | review/remove links set to "Always Open" (appears once one exists) | - |
| Show recently used paths | on/off; recents first in Insert Path, shared by sessions on a host | `terminal.path_browser.recent_paths` |
| Prefer generated titles | on/off; show running program + directory instead of shell titles | `terminal.titles.prefer_generated` |
| Startup command | executable + arguments; empty = default login shell | `terminal.shell.command` |

### 3.7 Remote Hosts
| Page | Setting | Values / notes | Action |
| --- | --- | --- | --- |
| Remote hosts | (host list) | add/reorder/remove remote Rex hosts, status, answer SSH questions, retry, forward ports | - (related: `client.host.add`, `client.host.remove`, `client.host.forward_port`, `client.host.switch`) |
| SSH | SSH agent | macOS agent / an agent on this Mac (Secretive, 1Password, Bitwarden, yubikey-agent, gpg-agent) / custom socket | `remote_hosts.ssh.agent` |
| SSH | SSH agent socket | path of custom agent socket | `remote_hosts.ssh.custom_path` |
| SSH | SSH agent status | read-only; whether agent answers and key count | - |

### 3.8 Developer (reveal with Developer Mode)
| Page | Setting | Values / notes | Action |
| --- | --- | --- | --- |
| Developer | Developer Mode | on/off; shows update-channel, installation, local API, web-client origin and experiment settings | `developer.mode.enabled` |
| Experimental | Download new updates when available | background download (not on Low Data Mode/hotspot), asks before restart; needs Developer Mode | - (related: `client.update.set_automation`) |
| Experimental | Install updates automatically | relaunch into new version while Rex not visible; needs Developer Mode | - (related: `client.update.set_automation`) |
| Experimental | Terminal anchoring | pin terminal text to top or bottom of each pane | `developer.experimental.terminal_anchor` |
| Experimental | New quick switcher | one list of every session/block/reporting process from Go to Anything | `developer.experimental.new_quick_switcher` |
| App Version | Update Channel | Preview or Bleeding Edge | - (related: `client.update.set_channel`) |
| Rex Server | Location | included server (Rex.app) or local source checkout | - |
| Rex Server | Source Directory | folder of source checkout | - |
| Rex Server | Rex Server status | read-only: ready/running/waiting for restart; details | - |
| Rex Server | Included Version | read-only, copyable | - |
| Rex Server | Included Commit | read-only, copyable | - |
| Rex Server | Final SHA-256 | read-only checksum, copyable | - |
| Local API | Local API URL | read-only, copyable local server endpoint (address/port or unix socket path) | - |
| Web Client Origins | Allowed origins | review permitted browser origins for Rex WebSocket streams; remove custom ones | - |
| Web Client Origins | Origin pattern | add browser origin or wildcard subdomain; takes effect after restarting Rex | - |

### 3.9 Settings with no matching action vs. actions with no matching setting
- Setting-only (no `client.setting.*`): Coding Agents/Agent Behavior toggles, Tailscale notifications and all Tailscale/Remote Address/Client Info items, Floating Windows corner, Font weight, Trusted links, SSH agent status, Remote hosts list, experimental update toggles, Update Channel, Rex Server (Developer) items, Local API URL, Web Client Origins.
- Action-only convenience: `client.update.*`, `client.theme.import`, `client.agents.setup`, `client.server.restart`, `client.pair_device`.

---

## 4. iOS

### 4.1 What differs from Mac
- iOS palette has 109 actions: 106 share Mac names and **3 are iOS-only**: `client.composer.open` (Compose Input: message/prompt composer with image/photo/file attach for Claude/Codex), `client.keyboard.show` (Show Keyboard), `client.keyboard.hide` (Hide Keyboard).
- The iOS reference lists **no default shortcuts** (touch-first; hardware keyboards still apply). iOS actions are run with `rex do` (the iOS page does not mention binding keys).
- Mac-only (not in iOS): all Find, Keys/mode, copy mode, update, window fullscreen, visibility/onboarding/permissions/pair_device/server.restart/notice.dismiss/shortcuts.edit, host.switch, session history (`back`, `recent`) + collapse/expand + `new.on_host`, tab history (`back`, `recent`, `mute`), pane history (`focus`, `focus_back*`, `focus_recent*`), `pane.move`, `client.key.forward`, `client.quick_look`, `client.theme.import`, `client.config.reload`, `client.tab_style.toggle`, `client.toolbar.reveal`, `client.pane_header.reveal`, `client.sidebar.activity.by_session|by_priority`, and 61 `client.setting.*` actions.
- iOS action titles/descriptions are identical to Mac for shared names. The iOS Settings screen is a much smaller set (4.4); several `client.setting.*` actions exist on iOS with no matching Settings entry (active-pane highlight x4, autobalance, animation style).

### 4.2 iOS actions (name, purpose = same as the Mac row in section 2)
**Window:** `client.window.new`, `client.window.close`, `client.close`
**App:** `client.settings`, `client.palette.toggle`, `client.version.copy`, `client.debug.copy`, `client.diagnostics`, `client.agents.setup`
**View:** `client.sidebar.toggle`, `client.sidebar.activity.toggle`, `client.config.copy_path`, `client.font.increase|decrease|reset`, `client.theme.change`, `client.appearance.switch_mode`, `client.sidebar.filter.focus`, **`client.keyboard.show`**, **`client.keyboard.hide`** (iOS-only)
**Session:** `session.new`, `session.select`, `session.next`, `session.previous`, `session.rename`, `session.close`, `session.refresh`, `session.switch`
**Host:** `client.host.add`, `client.host.remove`, `client.host.forward_port`
**Tab:** `client.tab.new`, `client.tab.previous`, `client.tab.next`, `client.tab.goto`, `client.tab.move.backward`, `client.tab.move.forward`, `client.tab.rename`, `client.tab.close`, `client.tab.close_others`, `client.tab.move`, `client.tab.move_to_new_window`
**Pane:** `pane.split`, `pane.split.left|right|up|down|auto`, `pane.focus_previous`, `pane.focus_next`, `pane.focus.left|right|up|down`, `pane.move.left|right|up|down`, `pane.zoom`, `pane.move_to_new_tab`, `pane.move_to_tab`, `pane.close`, `pane.close_others`, `pane.go_to_directory`, `pane.insert_path`, `pane.insert_photo`, `pane.insert_file`, `pane.copy_id`, `pane.rename`, `pane.balance`, `pane.resize`, `pane.float`, `pane.new_floating`, `pane.minimize_floating`, `pane.minimize_all_floating`, `pane.paste`, `pane.copy`, `pane.select_all`, `pane.send_key`, `pane.go_to`, `pane.view_activity`, `client.prompt.previous`, `client.prompt.next`, `client.scroll.page_up`, `client.scroll.page_down`, **`client.composer.open`** (iOS-only)

### 4.3 iOS setting actions (23; prefix `client.setting.`)
`interface.appearance.scheme`, `interface.appearance.tint`, `interface.active_panes.active_border`, `interface.active_panes.active_border_color`, `interface.active_panes.active_border_opacity`, `interface.active_panes.active_border_animation`, `interface.splits_focus.autobalance`, `interface.animation.style`, `themes.light.palette`, `themes.dark.palette`, `terminal.typography.font`, `terminal.typography.size`, `terminal.colors.contrast`, `terminal.colors.palette`, `terminal.cursor.blink`, `terminal.cursor.style`, `terminal.cursor.force`, `terminal.cursor.shaders`, `terminal.cursor.shader`, `terminal.scrolling.smooth`, `terminal.resizing.smooth`, `terminal.titles.prefer_generated`, `developer.mode.enabled`.

### 4.4 iOS settings (Settings screen)
Format: Section > Setting | Values / notes | Matching action.

| Section | Setting | Values / notes | Action (prefix `client.setting.`) |
| --- | --- | --- | --- |
| Interface (Appearance) | Color Scheme | Auto / Light / Dark | `interface.appearance.scheme` |
| Interface (Appearance) | Tint with Theme | on/off; match terminal colors vs standard iOS colors | `interface.appearance.tint` |
| Interface (Panes) | Match Program Backgrounds | on/off; color the screen with a full-screen program's background (Mac analog: Padding "Fill with program colors" + "Include pane header") | - |
| Themes | Light Theme | terminal palette for light appearance | `themes.light.palette` |
| Themes | Dark Theme | terminal palette for dark appearance | `themes.dark.palette` |
| Terminal (Typography) | Terminal Font | font family (e.g. Menlo, SF Mono, JetBrains Mono, Geist Mono, Ioskeley Mono, Roboto Mono, system font) | `terminal.typography.font` |
| Terminal (Typography) | Font Size | size on this device (points) | `terminal.typography.size` |
| Terminal (Colors) | Improve Text Contrast | on/off; included when forcing theme palette | `terminal.colors.contrast` |
| Terminal (Colors) | Force Theme Palette for Text | on/off | `terminal.colors.palette` |
| Terminal (Cursor) | Cursor Style | block / bar / underline | `terminal.cursor.style` |
| Terminal (Cursor) | Blink Speed | slow / normal / fast / none | `terminal.cursor.blink` |
| Terminal (Cursor) | Force Style | on/off; keep your style when programs request another | `terminal.cursor.force` |
| Terminal (Scrolling) | Smooth Scrolling | on/off | `terminal.scrolling.smooth` |
| Terminal (Resizing) | Smooth Terminal Resizing | on/off; reflow immediately (rotation, Stage Manager, Split View) | `terminal.resizing.smooth` |
| Terminal (Titles) | Prefer Generated Titles | on/off | `terminal.titles.prefer_generated` |
| Keyboard (On-Screen) | Autocorrect | on/off; correct/predict words | - |
| Keyboard (On-Screen) | Keep Keyboard Open | on/off; reopen when returning to a terminal | - |
| Keyboard (On-Screen) | Open Keyboard Manually | on/off; keyboard stays closed on tap; use keyboard button (see `client.keyboard.show`) | - |
| Keyboard (Hardware) | Key Repeat | on/off; repeat a held key | - |
| Keyboard (Hardware) | Delay Until Repeat | seconds before repeat starts | - |
| Keyboard (Hardware) | Key Repeat Interval | seconds between repeats | - |
| Keyboard (Hardware) | Repeat Held Letters | on/off; repeat instead of showing accents | - |
| Keyboard (Key Bar) | Key Bar Layout | arrange/hide/reorder built-in keys (arrows, escape, tab, ctrl/option/shift, paste, home/end, page up/down, delete, return) | - |
| Keyboard (Key Bar) | Shortcut Groups | add Control shortcuts, function keys, custom keys | - |
| Keyboard | Characters | choose punctuation keys (tilde, pipe, slash, ...) | - |
| Keyboard (Key Bar) | Use Symbols | on/off; symbols instead of abbreviated key names | - |
| Keyboard (Key Bar) | Haptic Feedback | on/off; light tap on key bar presses | - |
| Keyboard (Key Bar) | Command Palette | informational: how to open commands and use modifier keys | - |
| Remote Hosts | SSH Key | create/import the key used for ssh:// hosts; manage trusted host keys. Also hosts list: pair, connect, edit, delete, startup command/shell per host, port forwards | - |
| Developer Mode | Network Diagnostics | on/off (needs Developer Mode); floats network path + host connections over screen | - |
| Developer Mode | Cursor Shaders | on/off (needs Developer Mode); trail shader (Warp, Comet, Blaze, ...) behind cursor | `terminal.cursor.shaders` |
| About | version / device info | read-only; copy version info and debug info for a bug report; licenses/acknowledgements | - (related: `client.version.copy`, `client.debug.copy`) |

Settings sections on iOS: Interface, Themes, Terminal, Keyboard, Remote Hosts, Developer Mode, About. Notably absent vs Mac: Integrations/Agent Behavior (iOS still has `client.agents.setup`), Notifications, Server/Tailscale, toolbar/tab/pane/padding/window/gesture/app-icon/launch pages, advanced fonts, selection, links, path browser, shell startup command, SSH agent (iOS uses its own SSH Key), update channel/experimental.

---

## Source pages (relative to the Rex docs root)
- `reference/mac-actions.md` (Mac action names, default shortcuts, descriptions)
- `reference/mac-settings.md` (Mac settings pages and descriptions)
- `reference/ios-actions.md` (iOS action names)
- `reference/ios-settings.md` (iOS settings screens)
- Supporting (invocation/arg details referenced above): `customize/keyboard-shortcuts.md` (`rex.bind`, `rex -C <label> actions`), `customize/actions.md` (custom actions, `rex do`, `rex.client.queue`), `customize/key-modes.md` (`client.mode.*`), `customize/config.md` (`init.lua`, `rex config reload|check`), `reference/cli.md` (`rex do`, `rex actions`, `rex keymap`)
