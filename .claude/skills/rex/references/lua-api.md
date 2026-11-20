# Rex Lua API & Lua scripts

> **When to read this:** you need to automate Rex from Lua: write a `rex do` script, define actions/key bindings in the config file, or call the server (sessions/windows/blocks/terminals) programmatically.
> It lists every function in the global `rex` table with signature, return values and examples, plus how scripts are run, timers, `rex.exec`, JSON, and Lua event subscription (`rex.on`/`rex.wait`).
> For the event catalogue (names + payload fields), CLI `rex events` and shell scripting, read `events-and-shell.md`.

---

## 1. Basics

- Lua **5.1**, full standard library (`io`, `os`, `require` work). **`io.popen` and `os.execute` raise an error** - use `rex.exec`.
- Rex adds API **only** to the global `rex` table.
- Lua runs in two places: the **configuration file** (runs once at load, defines bindings/actions/hosts) and **scripts** run with `rex do` (run top to bottom, then exit unless handlers/timers are active).
- Scripts execute **locally where the `rex` CLI is**; security and program access is up to you.
- Every API call that talks to Rex returns a **result table, or `nil` + error message**. A failed call **never raises**; it does not stop the script. Check the second value:

```lua
local w, err = rex.session.new_window{ layout = layout }
if err ~= nil then error(err, 0) end
```

### Where each function works

| Function | Config, at load | Config, later | Script, at load | Script, later |
| --- | --- | --- | --- | --- |
| `rex.bind`, `rex.unbind` | Yes | Functions only | No effect | No effect |
| `rex.mode`, `rex.bindings`, `rex.modes` | Yes | Error | No effect | Error |
| `rex.action` | Yes | Error | Yes | Error |
| `rex.host` | Yes | Error | No effect | Error |
| `rex.on` | Warning | Error | Yes | Error |
| `rex.call`, `rex.session.*`, `rex.block.call` | Fails | Yes | Yes | Yes |
| `rex.invoke` | Warning | Yes | Yes | Yes |
| `rex.client.queue` | Error | Actions only | Yes | Yes |
| `rex.exec`, `rex.exec.start` | Yes | Yes | Yes | Yes |
| `rex.layout.*`, `rex.json.*`, `rex.log` | Yes | Yes | Yes | Yes |
| `rex.sleep`, `rex.wait`, `rex.stop` | Missing | Missing | Yes | Yes |
| `rex.after`, `rex.every` | Missing | Missing | Yes | Yes |
| `rex.args`, `rex.session_id`, `rex.block_id` | Missing | Missing | Yes | Yes |

- **No effect**: accepted, does nothing useful (a script's key bindings/hosts never reach a keymap/server).
- **Missing**: name is `nil`; calling it is an error. A file shared by config and scripts should check for it first (`if rex.sleep then ...`).
- **Fails**: returns `nil` + error message, reported as a warning.
- "Config later" = inside an action, a function bound to a key, or an event handler.

---

## 2. Running scripts: `rex do`

```sh
rex do ./layout.lua                           # a file
rex do -e 'return rex.call("session.list")'   # inline with -e
rex do - < layout.lua                         # stdin
rex do -s build ./layout.lua                  # target a session (-s) / block (-b)
rex do greet.lua name=rex n=2 on=true         # key=value args -> rex.args
rex do greet.lua --args '{"name": "true"}'    # all args as JSON
rex do greet.lua --args @args.json            # JSON from file
```

- Argument is a **file** if it ends in `.lua` or contains a slash. Anything else is the name of an **action** to run (`rex do pane.split direction=right`).
- A script run inside a Rex terminal acts on that terminal's session and block. Use `-s` / `-b` to target another (see CLI command targets).
- `key=value` types come from how written: `n=2` number, `on=true` boolean, `name=x` string. To force a string or pass nested values use `--args` JSON.
- **Result**: the returned value is printed as JSON (tables become objects/arrays); `--json` indents. No return value prints nothing.
- **Error**: an uncaught `error(msg, 0)` prints `Error: msg` and exits status 1.
- **Exit status**: `rex.stop(3)` ends the script immediately with status 3.
- `print` writes to the terminal; `rex.log` writes a log line.
- Event-related flags: `--all` (hear every session), `--for 10m` (time limit), `--fail-fast` (exit 1 on first handler/timer error). See `events-and-shell.md`.

```
$ rex do -e 'return { name = "rex", tabs = { 1, 2 } }'
{"name":"rex","tabs":[1,2]}
```

### Script values (set in `rex do` scripts only)

| Value | Description |
| --- | --- |
| `rex.args` | The script's arguments, as a table. Empty when none were passed. |
| `rex.session_id` | ID of the session the script runs against. |
| `rex.block_id` | ID of the block the script runs against, or `nil`. |

Calls fill in the script's `session_id` automatically; calls on one block (e.g. `set_block_label`) still need `block_id` (use `rex.block_id`).

### Minimal example

```lua
-- htop.lua : open a new window running htop
rex.session.new_window{
  layout = rex.layout.block{
    flavor  = "com.superlogical.terminal.shell",
    options = { command = { "htop" } },
  },
}
```

---

## 3. Calling Rex

Every call: one table of args in, one result table out (or `nil, err`).

### `rex.session.<method>(args)`

`session_id` is filled in when left out. **Other IDs (e.g. `block_id`) are not.**

```lua
local view, err = rex.session.view{}
rex.session.set_block_label{ block_id = rex.block_id, label = "tests" }
```

| Method | Description |
| --- | --- |
| `view` | Return the session's windows, layouts, and blocks. |
| `list_blocks` | List every block and whether it is placed or detached. |
| `list_clients` | List the clients attached to the session. |
| `describe_block` | Return a block's placement and the methods it offers. |
| `new_window` | Create a window from a layout. |
| `new_split` | Create a split beside an existing block. |
| `new_block` | Create a block without placing it in a layout. |
| `new_layer` | Create a floating layer in a window. |
| `close_window` | Close a window and every block in it. |
| `close_layer` | Close a floating layer and every block in it. |
| `move_block` | Move a block into a new split beside another. |
| `swap_blocks` | Exchange the positions of two blocks. |
| `detach_block` | Remove a block from its layout without closing it. |
| `float_block` | Move a tiled block into a new floating layer. |
| `zoom_block` | Toggle or set whether a block fills its window. |
| `resize_pane` | Move the border between two blocks. |
| `resize_layer` | Set a floating layer's position and size. |
| `raise_layer`, `lower_layer` | Change a floating layer's stacking order. |
| `move_window` | Move a window in the tab order. |
| `focus_block` | Focus a block. |
| `focus_window` | Focus a window. |
| `focus_direction` | Focus the nearest block in a direction. |
| `focus_next_pane`, `focus_previous_pane` | Focus the next or previous pane. |
| `focus_next_window`, `focus_previous_window` | Focus the next or previous window. |
| `set_label` | Set the session's label. |
| `set_window_label` | Set a window's label. |
| `set_block_label` | Set a block's label. |
| `attach`, `detach` | Change which session a script hears events from. |
| `help` | Describe the methods available through the session. |

Exact arguments/results of a method are **not** in the Lua docs; discover them with the CLI:

```sh
rex api describe session.new_split   # args + result of one method (use full name)
rex api list                         # every server method
```

Argument names seen in the docs' examples (others: use `rex api describe`):
- `new_window{ layout = <layout> }`
- `new_split{ direction = "horizontal", side = "after", focus = false, layout = <layout> }` -> result has `block_ids` (list), `split_ids`, `anchor_block_id`, `revision`
- `zoom_block{ block_id = id, zoom = true }`
- `set_block_label{ block_id = id, label = "x" }`
- `view{}` -> table with at least `label` (session label)

### `rex.call(method[, args])`

Call **any** server method by full name, including ones outside `rex.session`.

```lua
local result, err = rex.call("session.list")
```

### `rex.block.call(creator, method[, args])`

Call a method on a block. `creator` = full name of the kind of block. `block_id` is filled from the current block when left out.

```lua
local terminal = "com.superlogical.terminal"
local title = rex.block.call(terminal, "title", {}).title
```

Terminal (`com.superlogical.terminal`) methods:

| Method | Description |
| --- | --- |
| `format` | Return the screen as text, HTML, or VT sequences. |
| `process` | Describe the terminal's child and foreground processes. |
| `pwd` | Return the working directory the terminal last reported. |
| `title` | Return the terminal's title. |
| `size` | Return the terminal's size in cells and pixels. |
| `write` | Write bytes to the terminal as if they were typed. |
| `reset` | Reset the terminal. |
| `resize` | Request a size for the terminal. |
| `set_theme` | Replace the terminal's default colors. |
| `program_status` | Return the status records programs have reported. |
| `list_dir` | List the directories under a path. |

(Per-method argument names are not documented in the Lua pages; for the screen-read use case the CLI equivalent is `rex capture`.)

### `rex.layout` (builders; only build tables, call nothing)

Build the `layout` argument of `new_window`, `new_split`, `new_layer`.

| Function | Description |
| --- | --- |
| `rex.layout.block{ flavor, options }` | One block. `flavor` names what to create, e.g. `com.superlogical.terminal.shell`. |
| `rex.layout.horizontal(ratio, a, b)` | Two layouts split horizontally. `ratio` = share given to `a`, 0 to 1. |
| `rex.layout.vertical(ratio, a, b)` | Two layouts split vertically. |

Nestable. Terminal `options`:

| Option | Description |
| --- | --- |
| `command` | List: program + args. Without it, an interactive shell starts. |
| `shell` | The shell to use. `none` starts `command` directly. |
| `cwd` | Working directory. |
| `initial_input` | Text typed into the terminal once it starts. |
| `exit` | `{ on_completion = false }` keeps the terminal open after its program exits. |

```lua
local shell = "com.superlogical.terminal.shell"
rex.session.new_window{
  layout = rex.layout.horizontal(0.5,
    rex.layout.block{ flavor = shell },
    rex.layout.block{ flavor = shell, options = { command = { "htop" } } }),
}
```

---

## 4. Actions and invoking

### `rex.action{ ... }` (config file at load, or script at load)

Defines a named action (appears in command palette; bindable; runnable via `rex do NAME k=v`).

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | **Required.** Lowercase letters, digits, underscores. |
| `title` | string | **Required.** Shown in the command palette. |
| `run` | function | **Required.** Called as `run(ctx, args)`. |
| `description` | string | Longer explanation. |
| `category` | string | Palette group. Default `Actions`. |
| `keywords` | string | Extra search words. |
| `args` | table | Argument types, or a JSON Schema. |
| `repeats` | boolean | Run again while the key is held. |

- `args` types: `string`, `number`, `integer`, `boolean`, `object`, `array`, `any`. Trailing `?` = optional.
- `ctx` has `session_id`, `block_id`, `client_id`, `origin`, `server`. A field Rex doesn't know is **absent**. Whatever `run` returns is the action's result.

```lua
rex.action{
  name  = "dev_layout",
  title = "Dev layout",
  args  = { file = "string?" },
  run   = function(ctx, args) --[[ ... ]] end,
}
```

### `rex.invoke(name[, args])`

Runs an action; returns its result, or `nil, err`. In the **config file** only that file's own actions can be invoked. In a **script**, a name the script doesn't define is run by the server, so scripts can invoke config-file actions. Nesting up to **16** deep.

### `rex.client.queue(name[, args])`

Ask the **client/app** to perform one of its own actions (e.g. `pane.zoom`). In an action: queued actions run in order after `run` returns, discarded if it fails. In a script: each is performed immediately. **Raises an error when there is no client to ask.** (App actions need the app running with Remote Control enabled.)

---

## 5. Key bindings (config file)

See keyboard-shortcuts / key-sequences / key-modes docs.

| Call | Meaning |
| --- | --- |
| `rex.bind(key, action[, args])` | Bind key to an action name; `args` table passed to it. |
| `rex.bind(key, fn)` | Bind key to Lua `fn(ctx, ev)`. Return `true` to mark handled. **Not allowed in a mode.** |
| `rex.unbind(key[, target])` | Remove bindings of a key in this file **and the client's defaults**. Returns count of this file's bindings removed. `target` (action name or function) limits removal. `rex.unbind("mode/key")` also blocks the key in that mode. |
| `rex.unbind{ mode = name }` | Remove a whole mode: bindings, blocked keys, options. |
| `rex.unbind(binding)` | Remove one binding (a table from `rex.bindings`). Returns 1. |
| `rex.mode(name[, options])` | Declare a mode. Only option: `exclusive` (boolean, default `false`). |
| `rex.bindings([filter])` | Bindings made so far by this file + required files, in order. `filter` table: any of `key`, `mode`, `action`. |
| `rex.modes()` | Modes declared/bound so far: tables with `name`, `exclusive`, `source`. |

`key` = a single key, a sequence with `>`, or either prefixed with a mode and slash (`mode/key`). In a function binding, `ev.keybinding` is the key pressed; for a sequence `ev.prefix` is a list of preceding keys.

```lua
rex.bind("cmd+d", "pane.split", { direction = "right" })
rex.bind("cmd+k", function(ctx, ev) print(ev.keybinding); return true end)
```

Binding table fields (`rex.bindings`): `key`, `mode` (or nil), `action` (nil for function binding), `fn` (nil for action binding), `args`, `source` (e.g. `keys.lua:3`).

---

## 6. Hosts and other servers

| Call | Description |
| --- | --- |
| `rex.host{ ... }` | Declare another Rex server (**config file only**). |
| `rex.servers()` | Labels of other servers available to the running action/script, as a list. |
| `rex.server(label)` | Table with `session`, `block`, `call` like `rex`, but calls go to that server. **Raises** for unknown label. Calls through it do **not** fill in `session_id`/`block_id`. |

`rex.host` fields: `label` (required), `endpoints` (required, list of addresses tried in order), `endpoint` (single address instead of `endpoints`), `id` (stable ID so host keeps identity when renamed), `icon` (icon name for clients).

```lua
-- config file
rex.host{ label = "build-box", endpoints = { "<address>" } }  -- address format: see config docs (not in these pages)
-- action / script
local srv = rex.server("build-box")
local sessions = srv.call("session.list")
```

---

## 7. Sleeping, waiting, stopping (scripts only)

| Call | Description |
| --- | --- |
| `rex.sleep(seconds)` | Block for seconds (fractional OK). |
| `rex.wait(event[, filter][, timeout])` | Block until `event`; returns `ev, ctx`. On timeout returns `nil, "timeout"`. |
| `rex.stop([code])` | End the script immediately; `rex do` exits with `code` (default 0). |

`filter`: a **table** (matches events whose fields equal the table's) or a **function** `filter(ev, ctx)` returning `true` for a match. `timeout` in seconds; omitted = wait forever.

```lua
local ev = rex.wait("terminal.child_exited", { block_id = id }, 600)
if ev == nil then error("timed out", 0) end
```

`rex.wait` and `rex.sleep` also work inside a handler (no other event is handled until they return).

---

## 8. Event subscription from Lua (scripts only)

### `rex.on(event, fn)`

Calls `fn(ctx, ev)` each time `event` happens. Works **only** in scripts run with `rex do`; in the config file it warns and never fires; calling it from inside a handler (after the script first ran) is an **error**. Handlers must be registered during first run.

```lua
-- label.lua : label each terminal with its directory
rex.on("terminal.pwd_changed", function(ctx, ev)
  local dir = ev.pwd:match("([^/]+)/?$")
  rex.session.set_block_label{ block_id = ctx.block_id, label = dir }
end)
```

- `ev` = event fields; `ctx.session_id` = session of the event; `ctx.block_id` = block for block events.
- API calls in a handler default to the **event's session**, so one handler works across sessions with `--all`.
- A script with `rex.on` does not exit at its last line; `rex do` keeps running and calls handlers one at a time.
- Event names: session/server events by type (`block_closed`, `window_created`, `session_created`); block events as `terminal.bell` (short for `com.superlogical.terminal.bell`, both spellings work); `block_event` = every event from every block. Names are **not validated**; a typo registers fine and never fires.
- Scope: default = the one session (current, or `-s NAME`); `--all` hears every session including new ones and server events.
- Script stops when: handler calls `rex.stop(code)`; `--for` elapses; the heard session is destroyed (never with `--all`); Ctrl-C.
- Handler/timer errors are printed and the script keeps running; `--fail-fast` exits 1 on first failure.
- Handlers vs `rex.wait`: `wait` for sequential "do A, wait, then B"; `on` for responding every time.
- **Bursty events**: debounce with a timer (note timer API calls default to the *script's* session, so pass `ctx.session_id` through):

```lua
local pending
rex.on("session_view_changed", function(ctx, ev)
  if pending then pending:cancel() end
  pending = rex.after(0.5, function() export(ctx.session_id) end)
end)
```

- To have a handler running all the time, start the script at session start (e.g. from a terminal you keep open). Config files are never sent events.

Example - macOS notification on any bell, any session:

```lua
-- notify.lua   (run: rex do notify.lua --all)
local function notify(title, text)
  rex.exec{ "osascript", "-e",
    string.format("display notification %q with title %q", text, title) }
end
rex.on("terminal.bell", function(ctx, ev)
  local view = rex.session.view{}      -- no session_id -> the session that rang
  notify("Rex", "Bell in " .. view.label)
end)
```

Every `ev` also has `ev.type`, `ev.session_id`, `ev.payload` (fields again as a table), and for block events `ev.block_id`, `ev.creator_name`, `ev.name`. Full list: `events-and-shell.md`.

---

## 9. Timers (scripts only)

| Call | Description |
| --- | --- |
| `rex.after(seconds, fn)` | Call `fn(ctx)` once after `seconds` (zero/fractional OK). Returns timer. |
| `rex.every(seconds, fn)` | Call `fn(ctx)` every `seconds` (> 0) until cancelled. Returns timer. |
| `t:cancel()` | Stop the timer. |
| `t:active()` | `true` until cancelled or fired for the last time. |

- Does **not** pause the script (unlike `rex.sleep`). Timer keeps running even if you drop the reference - keep it to cancel.
- `ctx` is the same as an action's `run` ctx, with `ctx.origin = "timer"`. API calls default to the **script's** session/block (even if created inside a handler).
- Timers never run concurrently with other script Lua. If busy when `every` ticks, `fn` runs once when free; missed ticks dropped.
- Errors in `fn` are printed; timer keeps running.
- **Max 1,024 live timers**; cancelled/finished `after` timers don't count. Exceeding stops the script with status 1 **even inside `pcall`**.

```lua
rex.every(5, function(ctx) --[[ every 5s ]] end)
local t = rex.after(0.5, function(ctx) --[[ once ]] end)
t:cancel()
```

---

## 10. Running commands: `rex.exec`

### `rex.exec(argv[, opts])`

Runs a command, **waits**, returns a result table. Returns `nil, err` **only** if the command never ran (e.g. program missing). Non-zero exit is still a result.

`argv` = list of strings (program, then args). **No shell** reads it - no quoting needed. Programs without a slash are looked up in the command's `PATH`. For a shell: `{ "sh", "-c", line }`.

| Option | Description |
| --- | --- |
| `cwd` | Working directory. Defaults to Rex's own. |
| `env` | Env vars to set, e.g. `{ GIT_DIR = "/repo/.git" }`. `false` removes one. |
| `clear_env` | `true` starts from empty environment; `env` still applies. |
| `stdin` | String written to the command's stdin. |
| `timeout` | Seconds until `SIGTERM`, then `SIGKILL` 2s later. |
| `stdout`, `stderr` | `false` discards the stream. Both captured by default. |
| `text` | `false` keeps `\r\n` in output on Windows. |

Unknown options are ignored with a warning.

Result fields:

| Field | Description |
| --- | --- |
| `code` | Exit status, or `-1` if a signal ended it. |
| `signal` | Signal name (e.g. `SIGTERM`) or `nil`. |
| `stdout`, `stderr` | Output; `""` when empty. |
| `timed_out` | `true` if `timeout` stopped it. |
| `ok` | `true` if `code == 0` and not timed out. |

```lua
local r, err = rex.exec{ "git", "rev-parse", "--abbrev-ref", "HEAD" }
if r == nil then error(err, 0) end
if r.ok then
  rex.session.set_block_label{ block_id = rex.block_id, label = r.stdout:gsub("\n$", "") }
end

local r = rex.exec({ "make", "test" }, { cwd = "/src/app", env = { CI = "1" }, timeout = 300 })
```

While a config-file action waits on a command, the server keeps handling keys/actions; everywhere else the wait blocks the script.

### `rex.exec.start(argv[, opts])`

Starts without waiting; returns a handle, or `nil, err`. Same args as `rex.exec`, plus:

| Option | Description |
| --- | --- |
| `stdin` | `true` keeps stdin open for `h:write`. |
| `stdout`, `stderr` | Function called with each chunk as it arrives (may end mid-line). |
| `detach` | `true` lets the command outlive the work that started it. |

Handle:

| Method | Description |
| --- | --- |
| `h:wait([seconds])` | Wait for exit; returns same result as `rex.exec`. `nil, "timeout"` if `seconds` pass first. |
| `h:write(data)` | Write to stdin. `true`, or `nil, err`. |
| `h:close_stdin()` | Close stdin. |
| `h:kill([signal])` | Send signal (default `SIGTERM`); name like `SIGINT` or number. |
| `h:running()` | Whether still running. |
| `h.pid` | Process ID. |

**Lifetime**: a started command lasts as long as the work that started it. When an action/handler/timer returns, or a script top level finishes, Rex **stops the commands it started** - unless `detach = true`.

```lua
local h = assert(rex.exec.start({ "make", "build" }, {
  stdout = function(data) io.write(data) end,
}))
local r = h:wait()
```

To *watch* a command run, start it in a terminal block (`rex.layout.block` with `options.command`) instead.

---

## 11. JSON and logging

| Call | Description |
| --- | --- |
| `rex.json.encode(value[, opts])` | Lua value -> JSON text, or `nil, err`. `opts.indent = true` indents 2 spaces. |
| `rex.json.decode(text)` | JSON text -> Lua value, or `nil, err`. `null` -> `nil`; a `null` in an array is dropped. |
| `rex.log([level, ]message)` | Log message. `level`: `debug`, `info`, `warn`, `error` (default `info`). In a script printed to the terminal. |

Encoding rules: same as an API call. A table with keys 1..n -> array; any other table **including an empty one** -> object. Functions and self-referential tables can't be encoded.

```lua
local text = rex.json.encode({ name = "work", panes = { 1, 2 } })
```

---

## 12. Worked examples

### Run tests in a split, zoom on failure

```lua
-- tests.lua   (rex do tests.lua cmd="go test ./...")
local cmd = rex.args.cmd or "make test"

local split, err = rex.session.new_split{
  direction = "horizontal",
  side      = "after",
  focus     = false,
  layout    = rex.layout.block{
    flavor  = "com.superlogical.terminal.shell",
    options = {
      command = { "sh", "-c", cmd },
      exit    = { on_completion = false },  -- keep the output
    },
  },
}
if err ~= nil then error(err, 0) end
local block_id = split.block_ids[1]

local ev = rex.wait("terminal.child_exited", { block_id = block_id }, 600)
if ev == nil then error("timed out waiting for: " .. cmd, 0) end
if ev.exit_code ~= 0 then
  rex.session.zoom_block{ block_id = block_id, zoom = true }
end
return { block_id = block_id, exit_code = ev.exit_code }
-- -> {"block_id":"block:01a1...","exit_code":1}
```

### Export session layout every 5 seconds

```lua
-- export.lua   (rex do export.lua path=/tmp/work.json)
local path = rex.args.path or "session.json"
local function export()
  local view, err = rex.session.view{}
  if err ~= nil then error(err, 0) end
  local f = assert(io.open(path, "w"))
  f:write(rex.json.encode(view, { indent = true }))
  f:close()
end
export()
rex.every(5, export)    -- prints "running: 1 timer; Ctrl-C to stop"
```

If the server is briefly unreachable, `export` raises, the error is printed, and the timer tries again next tick.

### Exit with the first failing program's status

```lua
rex.on("terminal.child_exited", function(ctx, ev)
  if ev.exit_code ~= 0 then rex.stop(ev.exit_code) end
end)
```

---

## 13. Gotchas checklist

- Failed API calls return `nil, err`; they do not throw. Check `err`.
- `block_id` is never auto-filled by `rex.session.*` (only `session_id`); use `rex.block_id` / `ctx.block_id`.
- `rex.on` only in `rex do` scripts, only at first run; never in the config file.
- Config file does **not** receive events; `rex.sleep/wait/stop/after/every/args/session_id/block_id` are `nil` there.
- Timer API calls default to the script's session; handler API calls default to the event's session.
- `terminal.child_exited` fires for the terminal's started program, not for each command inside a shell; use a `command` option to get per-command exits.
- Commands started with `rex.exec.start` die when their owning work ends unless `detach = true`.
- Event-name typos are silent. Ignore unknown event fields.
- Prefer `rex api describe <method>` over guessing argument names.

---

## Source pages

- `docs/reference/lua.md`
- `docs/automate/lua-scripts.md`
- `docs/automate/lua-events.md`
- `docs/reference/events.md`
- (related, not provided) `docs/automate/cli.md`, `docs/customize/config.md`, `docs/customize/actions.md`
