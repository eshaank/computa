# Rex events & shell scripting

> **When to read this:** you need to react to what happens in Rex (windows/blocks/terminals/sessions/clients), stream events to another program, or automate Rex from plain `sh`/bash with the `rex` CLI.
> It has the complete event catalogue (name, when it fires, payload fields), how to subscribe from Lua and from `rex events`, and shell patterns: tracking IDs, building layouts, send/capture, run-and-wait.
> For the Lua function signatures (`rex.on`, `rex.wait`, `rex.exec`, ...) read `lua-api.md`.

---

## 1. Event model

Rex emits an event whenever something changes. Three sources:

| Kind | Describes | Lua name |
| --- | --- | --- |
| Session events | Changes to one session's windows, blocks, clients. | The event's type, e.g. `block_closed`. |
| Terminal events | Things a terminal reports. | `terminal.` + event, e.g. `terminal.bell`. |
| Server events | Changes to the server as a whole. | The event's type, e.g. `session_created`. |

Consume them via **Lua** (`rex.on` / `rex.wait`, scripts run with `rex do`) or **CLI** (`rex events`). The docs describe no other event-subscription mechanism (nothing about the Server API streaming events in these pages).

### Fields on every Lua `ev`

| Field | Description |
| --- | --- |
| `ev.type` | The event's type. For every terminal event this is `block_event`. |
| `ev.session_id` | Session the event happened in. **Absent for most server events.** |
| `ev.payload` | The event's own fields again, as a table. |
| *(event fields)* | The fields listed per event below are directly on `ev`. |

Block events (terminal events and any other block event) additionally have:

| Field | Description |
| --- | --- |
| `ev.block_id` | Block the event came from. |
| `ev.creator_name` | Kind of block, e.g. `com.superlogical.terminal`. |
| `ev.name` | Event name without the creator, e.g. `bell`. |

`ctx.session_id` and `ctx.block_id` hold the same IDs and are what API calls in the handler default to.

Register for `block_event` to receive **every event from every block**; distinguish with `ev.creator_name` and `ev.name`.

---

## 2. Session events

Heard for the session the script runs against (or `-s NAME`), or for every session with `--all`.

| Event | When | Fields |
| --- | --- | --- |
| `window_created` | A window is created. | `window_id`, `label` |
| `window_closed` | A window is closed. | `window_id` |
| `window_label_changed` | A window is renamed. | `window_id`, `label` |
| `active_window_changed` | A different window becomes active. | `window_id` |
| `block_created` | A block is created. | `block_id` |
| `block_closed` | A block is closed. | `block_id` |
| `session_label_changed` | The session is renamed. | `label` |
| `session_view_changed` | The session's layout changes in any way. | `revision` |
| `client_connected` | A client attaches to the session. | `client_id`, `principal`, `connected_at` |
| `client_disconnected` | A client detaches from the session. | `client_id`, `principal` |
| `client_connection_changed` | An attached client's connection is lost or restored. | `client_id`, `principal`, `connection_state` |
| `creator_changed` | The kinds of block the session can create have changed. | *(none)* |

`session_view_changed` follows almost every other event here (most change layout). Handle it to react to any structural change, then call `rex.session.view` for the new layout. It arrives in bursts: debounce with `rex.after` (see section 5).

## 3. Terminal events

From terminal blocks. In Lua write `terminal.<name>` or in full `com.superlogical.terminal.<name>` (both work). On the wire these are `block_event`s.

| Event | When | Fields |
| --- | --- | --- |
| `terminal.child_exited` | The terminal's program exits. | `exit_code`, and `error` when non-zero |
| `terminal.pwd_changed` | Program reports a new working directory. | `pwd`, `owner` |
| `terminal.title_changed` | The terminal's title changes. | `title`, `owner` |
| `terminal.bell` | The terminal receives a bell character. | *(none)* |
| `terminal.process_changed` | The foreground process changes. | `generation`, `foreground`, `ancestors` |
| `terminal.desktop_notification` | Program asks for a desktop notification. | `title`, `body` |
| `terminal.progress_report` | Program reports progress. | `state`, `progress` |
| `terminal.clipboard_written` | Program writes to the clipboard. | `text` |
| `terminal.program_status_changed` | A program reports/updates its status. | `id`, `record`, `reason` |
| `terminal.program_status_removed` | Program status records are removed. | `ids`, `reason` |

Notes:
- `terminal.child_exited` concerns the program the terminal **started** (usually your shell). It does **not** fire per command typed inside a shell. A terminal started with a `command` fires it when that command exits.
- `pwd` is a **URL** like `file://hostname/Users/you/src`, not a path; only reported by shells set up to report it. Strip with e.g. `ev.pwd:match("([^/]+)/?$")` for the last component.
- `owner` is a table with `pid` and `name` of the process that made the change.
- `foreground` is a table describing the foreground process (`name`, `cwd`, `pid`, more); can be `nil`.

## 4. Server events

Describe the server, not one session. In Lua heard when run with `--all`.

| Event | When | Fields |
| --- | --- | --- |
| `session_created` | A session is created. | `session` (table: `session_id`, `label`) |
| `session_destroyed` | A session is destroyed. | `session_id` |
| `client_joined` | A client connects to the server. | `client` |
| `client_left` | A client disconnects from the server. | `client_id` |
| `client_changed` | A connected client's details change. | `client` |
| `keymap_changed` | The configuration file is reloaded. | `generation`, `hash` |
| `hosts_changed` | The list of hosts changes. | `hash` |
| `tailscale_status_changed` | The server's Tailscale status changes. | *(none)* |

`client` table: `client_id`, `info` (`kind`, `name`, `platform`, `version`), `principal`, `connected_at`.

### Forward compatibility

New Rex versions add events and fields. Rex never validates event names, so you can register for an event only a newer server sends (and a typo silently never fires). **Ignore unknown fields** rather than failing.

---

## 5. Subscribing from Lua

Only in scripts run with `rex do`. (The config file is never sent events; `rex.on` there warns and never fires. Calling `rex.on` from inside a handler is an error.)

```lua
-- label.lua : label each terminal with the directory it is in
rex.on("terminal.pwd_changed", function(ctx, ev)
  local dir = ev.pwd:match("([^/]+)/?$")
  rex.session.set_block_label{ block_id = ctx.block_id, label = dir }
end)
```

```
$ rex do label.lua
listening: 1 handler, session work; Ctrl-C to stop
```

### Name forms accepted by `rex.on` / `rex.wait`

| Name | Matches |
| --- | --- |
| `block_closed`, `window_created`, ... | A session or server event, by type. |
| `terminal.pwd_changed`, `terminal.bell`, ... | One kind of event from a block. |
| `block_event` | Every event from every block. |

### Handlers

- `rex.on(event, fn)` -> `fn(ctx, ev)`. `ctx.session_id` = session of the event; `ctx.block_id` = block for block events.
- Handlers run **one at a time**; the script stays alive while any exist.
- Register handlers while the script first runs.
- API calls inside a handler default to the **event's session** (one handler works across all sessions it hears).
- `rex.wait` / `rex.sleep` work inside a handler; no other event is handled until they return.
- Errors in a handler/timer are printed and the script keeps running (`--fail-fast` = exit 1 on first failure). Failed API calls return `nil, err`, not errors; check them.

### Scope and lifetime flags (`rex do`)

| Flag | Effect |
| --- | --- |
| *(default)* | Events of one session: the one run in, or `-s NAME`. |
| `-s NAME` | Hear session labelled NAME (`rex do -s build label.lua`). |
| `--all` | Hear **every** session, including ones created after start, plus server events. |
| `--for 10m` | Stop after a duration. |
| `--fail-fast` | Exit status 1 at first handler/timer failure. |

A handler script stops when: a handler calls `rex.stop(code)` (exit status `code`, default 0); `--for` elapses; the heard session is destroyed (never with `--all`); Ctrl-C.

### `rex.on` vs `rex.wait`

| Use | When |
| --- | --- |
| `rex.wait(event, filter, timeout)` | Sequential: start a command, wait for exit, act. Returns `ev, ctx`; `nil, "timeout"` on timeout. |
| `rex.on(event, fn)` | Respond every time something happens, for as long as the script runs. |

`filter` = table (fields must equal) or function `filter(ev, ctx)` returning `true`.

```lua
local ev = rex.wait("terminal.child_exited", { block_id = id }, 600)
```

### Debounce bursty events with a timer

Handlers that need to act later should start a timer and return (don't sleep; it blocks all other events). Timer API calls default to the **script's** session, so pass `ctx.session_id` explicitly:

```lua
local pending
rex.on("session_view_changed", function(ctx, ev)
  if pending then pending:cancel() end
  pending = rex.after(0.5, function() export(ctx.session_id) end)
end)
```

### Example: bell -> macOS notification, all sessions

```lua
-- notify.lua    run: rex do notify.lua --all
local function notify(title, text)
  rex.exec{ "osascript", "-e",
    string.format("display notification %q with title %q", text, title) }
end
rex.on("terminal.bell", function(ctx, ev)
  local view = rex.session.view{}        -- no session_id: the session that rang
  notify("Rex", "Bell in " .. view.label)
end)
```

### Example: exit with first failing program's status

```lua
rex.on("terminal.child_exited", function(ctx, ev)
  if ev.exit_code ~= 0 then rex.stop(ev.exit_code) end
end)
```

### Always-on handlers

There is no config-file handler. Start the script yourself when you start your session (e.g. from a terminal you keep open), typically with `--all`.

---

## 6. Subscribing from the CLI: `rex events`

Prints events as they happen; runs until interrupted.

| Command | Prints |
| --- | --- |
| `rex events` | Sessions being created, destroyed, changed. |
| `rex events -s SESSION` | Everything in one session, including terminal events. |
| `rex events --all` | Everything, including clients joining and leaving. |
| `... --json` | One JSON object per line (for `jq`). |

Human format:

```
$ rex events -s work
14:38:07  block_created         …65951c  session …8f9d5d
14:38:07  session_view_changed  …8f9d5d  revision 11
14:38:07  block_event           …65951c  com.superlogical.terminal.bell {}
```

### JSON wire format

Each line has `type` and `payload` (holding the event's fields).

Server event:

```json
{"type":"session_created","payload":{"session":{"session_id":"session:01a1...","label":"work"}}}
```

Session events arrive wrapped in `session_event` (adds `session_id`); terminal/block events wrapped once more in `block_event`:

```json
{"type":"session_event","payload":{
  "session_id":"session:01a1...",
  "event":{"type":"block_event","payload":{
    "block_id":"block:01a1...",
    "creator_name":"com.superlogical.terminal",
    "name":"child_exited",
    "payload":{"exit_code":2,"error":"exit status 2"}}}}}
```

**Lua strips both wrapper layers** - that's why a Lua handler sees `exit_code` directly on `ev`. In shell/jq you must unwrap: terminal fields are at `.payload.event.payload.payload`, the event's name at `.payload.event.payload.name`.

```sh
# block ID of each terminal that rings its bell
rex events -s work --json |
  jq -r 'select(.payload.event.payload.name == "bell")
         | .payload.event.payload.block_id'
```

For acting on events (vs printing), Lua handlers are much less work than a shell pipeline.

---

## 7. Shell scripting with the `rex` CLI

Use plain shell to automate everything in Rex. For more than a few commands, prefer a Lua script: one server connection, no JSON parsing.

```sh
#!/bin/sh
rex new work
rex split -s work -- htop
rex run -s work --label logs -- tail -f app.log
```

### Commands used in scripts

| Command | Purpose |
| --- | --- |
| `rex new [LABEL]` | Create a session (one window, one terminal). |
| `rex run` | Add a window (tab) running a terminal. |
| `rex split` | Split an existing block, new terminal beside it. |
| `rex send` | Type text into a terminal (no Enter added). Reads stdin too. |
| `rex send-key` | Press keys (same names as keyboard shortcuts, e.g. `enter`, `ctrl+c`). |
| `rex capture` | Print a terminal's screen + scrollback. |
| `rex wait` | Wait for a terminal/window/session to close; exit with its status. |
| `rex zoom` | Zoom a block (`rex zoom -b "$block" --on`). |
| `rex do` | Run an action by name (`key=value` args) or a Lua script. |
| `rex events` | Stream events. |
| `rex api list` / `rex api describe METHOD` | Discover server methods (used from Lua docs). |

Targets: `-s SESSION` (name/label), `-b BLOCK` (ID or label). IDs look like `session:...`, `block:...`, `split:...`.

### 7.1 Keep track of IDs

Creating commands print the ID with `--json`. Save and reuse the **ID** so the script survives label changes and focus moves.

```
$ rex split --json -- htop
{
  "anchor_block_id": "block:01a10e00-7268-...",
  "block_ids": [ "block:01a10e00-729d-..." ],
  "split_ids": [ "split:01a10e00-72ab-..." ],
  "revision": 2
}
```

```sh
block=$(rex split --json -- htop | jq -r '.block_ids[0]')
rex zoom -b "$block"
```

| Command | Creates | ID is at |
| --- | --- | --- |
| `rex new --json` | A session with one window and one terminal | `.session_id` |
| `rex run --json` | A terminal in a new window | `.block_ids[0]`, `.window_id` |
| `rex split --json` | A terminal beside an existing one | `.block_ids[0]` |

Alternative: give the block a label and target by it.

```sh
rex split --label logs -- tail -f app.log
rex capture -b logs
```

### 7.2 Build a layout

`rex new` = session, `rex run` = new window, `rex split` = split a block.

```sh
#!/bin/sh
# editor with a shell below it, plus a second window following logs
rex new api --cwd ~/src/api -- nvim
rex split -s api --split=below --ratio 30 --cwd ~/src/api
rex run -s api --label logs --focus=false -- tail -f ~/src/api/app.log
```

Options shared by `rex run` and `rex split`:

| Option | Does |
| --- | --- |
| `-- COMMAND` | Run a command instead of an interactive shell. |
| `--cwd DIR` | Working directory. |
| `--label TEXT` | Label the new block. |
| `--split DIRECTION` | Place the block `right`, `left`, `above`, or `below` its anchor. |
| `--ratio PCT` | Give the new block that percentage of the split. |
| `--focus=false` | Leave focus where it was. |
| `--keep-open` | Keep the terminal open after its command exits. |
| `--wait` | Wait for the command to finish; `rex` exits with its status. |
| `--json` | Print IDs as JSON. |

The command runs with your **login shell's environment** (your `PATH` applies, aliases don't) and is **not parsed by a shell**. For pipes/`&&` run a shell explicitly:

```sh
rex run -- sh -c 'make build && make test'
```

### 7.3 Type into a terminal

```sh
rex send -b logs 'make test'
rex send-key -b logs enter
printf 'make test\n' | rex send -b logs     # stdin; newline in text works too
rex send-key ctrl+c                          # interrupt whatever is running
```

`rex send` never presses Enter for you - follow with `rex send-key enter` or include a newline.

### 7.4 Read a terminal

```
$ rex capture -b logs --trim
hello from logs
```

| Option | Does |
| --- | --- |
| `--trim` | Remove trailing blank lines. |
| `--unwrap` | Join lines the terminal wrapped. |
| `--format html` | Keep colors/styling as HTML. |
| `--format vt` | Keep the terminal's control sequences. |

- Scrollback is about **64 MiB** (~100,000 plain 80-col lines; fewer if wider or styled). Oldest lines drop at the limit; to keep everything a long command prints, **redirect its output to a file**.
- **Full-screen programs** (editors, pagers, TUIs) use a separate screen with no scrollback; `rex capture` returns only what is shown right now. Program-internal history stays inside the program.

### 7.5 Run a command and wait

`--wait` on `rex run`/`rex split` makes `rex` exit with the command's own status:

```sh
if rex run --wait -- make test; then echo "tests passed"; fi
```

`rex wait` on an already-running terminal (ID or label); also accepts a **window or session** and returns when it closes:

```sh
block=$(rex split --json -- make test | jq -r '.block_ids[0]')
# ... do other things ...
rex wait "$block"
echo "make exited with $?"
```

`--for` gives up after a while; a timed-out wait exits **1**:

```sh
rex wait --for 10m "$block" || echo "failed or timed out"
```

### 7.6 Perform actions

`rex do NAME key=value ...` runs app actions and your config-file custom actions:

```sh
rex do dev_layout file=app.log
rex do pane.split direction=right
```

App actions (like `pane.split`) are performed by the **app**: it must be running with **Remote Control** enabled in its settings.

### 7.7 Example: run tests in a split, zoom on failure

```sh
#!/bin/sh
# tests.sh   usage: ./tests.sh 'go test ./...'
cmd="${1:-make test}"

block=$(rex split --keep-open --focus=false --json -- sh -c "$cmd" |
  jq -r '.block_ids[0]')

if ! rex wait --for 10m "$block"; then
  rex zoom -b "$block" --on
  exit 1
fi
```

Equivalent Lua version (see `lua-api.md` section 12) uses `rex.session.new_split` + `rex.wait("terminal.child_exited", {block_id=...}, 600)` and returns the exit code, with no `jq`.

---

## 8. Which approach?

| Need | Use |
| --- | --- |
| A few sequential commands, existing shell tooling | Shell + `rex` CLI + `jq` |
| Logic, loops, many calls, waiting on events | Lua script (`rex do`) |
| React every time something happens | `rex.on` handlers (`rex do ... --all`) |
| Pipe events into another program/tool | `rex events [-s SESSION | --all] --json | jq` |
| Do one thing then wait for exit | `rex wait` (shell) / `rex.wait` (Lua) |
| Debounced layout-change reaction | `session_view_changed` + `rex.after` |

---

## Source pages

- `docs/reference/events.md`
- `docs/automate/lua-events.md`
- `docs/automate/lua-scripts.md`
- `docs/automate/shell-scripting.md`
- `docs/reference/lua.md`
- (related, not provided) `docs/automate/cli.md`, `docs/customize/keyboard-shortcuts.md`
