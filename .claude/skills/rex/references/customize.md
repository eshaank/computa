# Customizing Rex: init.lua, key bindings, sequences, modes, custom actions, custom UI

**When to read this:** you need to change how Rex behaves for a user (keys, shortcuts, tmux-style prefixes, modal key tables),
add named actions that show up in the command palette / CLI, or have an action ask the user a question (text or list).
For scripts run once against a live session (`rex do script.lua`), events, timers, and the full API surface, read the Lua API reference page instead.

## 1. The config file (`init.lua`)
Rex config is **Lua 5.1** in a single file, `init.lua`. No config is required; Rex works without one.

| Platform | Location |
| --- | --- |
| macOS / Linux | `$XDG_CONFIG_HOME/rex/init.lua` if set, else `~/.config/rex/init.lua` |
| Windows | `%AppData%\rex\init.lua` |
| Override | `REX_CONFIG=/path/to/file.lua` (must be set in the environment of the **Rex server process**, since the server reads the file) |

- The file is read by the **server**, so it lives on the server's machine. `rex config reload` must be run on that machine; **it is refused over a remote connection**.
- Split config with `require`: `require("keys")` loads `keys.lua` stored beside `init.lua`. Errors are reported as `keys.lua:2`.
- Standard Lua library is available (`io`, `os`, `require`) except `io.popen` and `os.execute`, which raise errors. Use `rex.exec` to run commands.
- Only the global `rex` table is added by Rex.

```lua
-- ~/.config/rex/init.lua
require("keys")
rex.bind("cmd+d", "pane.split", { direction = "right" })
```

### CLI workflow
| Command | Purpose |
| --- | --- |
| `rex config reload` | Apply the file. Connected clients are notified and it takes effect immediately. **Rex does not watch for file changes; you must run this.** |
| `rex config check [path]` | Load without changing anything; report issues; prints `path`, `exists`, `bindings`, `removals`, `modes`, `actions` counts. Pass a path to check a draft file. |
| `rex keymap` | Ask the running server for the merged result: every binding with ARGS and SOURCE (`init.lua:2`), plus a MODE / EXCLUSIVE / BLOCKED table. Reports things the file alone can't know. |
| `rex actions` | Lists the custom actions the server has loaded. |
| `rex -C <client-label> actions` | Lists a connected client's actions (NAME, TITLE, ARGS; `?` suffix = optional arg). Find labels with `rex client ls`. |
| `rex do <action> key=value ...` | Run an action from the CLI (`--json` for formatted output). |

`rex config reload` and `rex config check` print the file's mistakes and **exit with status 1** if any is an error.

### Validation behavior
- A bad call to a `rex` function (e.g. `rex.bind({ "cmd+k" }, ...)` -> `rex.bind: expected a string, got table`) is **skipped; the rest of the file still loads**.
- A Lua syntax error (anything Lua itself can't get past) **fails the whole load**. On a reload, the server keeps the bindings/actions from the **last good load**.
- A misspelled action name is **not** an error in `rex config check` (actions come from the client). The client reports it as a warning when it loads the keymap; use `rex keymap`.

### Execution model (important gotcha)
- The file runs top to bottom on every load. It is for **defining** bindings, actions, modes, hosts.
- Callbacks (action `run`, bound functions) are deferred until invoked.
- **Rex API calls that act on a session (`rex.session.*`, `rex.call`, `rex.block.call`, e.g. creating a window) do not work at load time** because load time has no client. They return `nil` + error and are reported as a warning; the rest of the file still loads. Put them inside an action's `run`.
- To run Lua once, top to bottom, against a live session, write a separate script and use `rex do script.lua` (not config).

### Where functions work (from the Lua reference)
- **Config, at load only:** `rex.bind`, `rex.unbind`, `rex.mode`, `rex.bindings`, `rex.modes`, `rex.action`, `rex.host` (later = Error, except `bind`/`unbind` with functions only).
- **Config, later (inside action/fn/handler):** `rex.call`, `rex.session.*`, `rex.block.call`, `rex.invoke`; `rex.client.queue` in actions only. At load, `rex.call`/`rex.session.*`/`rex.block.call` Fail (nil, err + warning), `rex.invoke` warns, `rex.client.queue` errors, `rex.on` warns.
- **Anywhere:** `rex.exec`, `rex.exec.start`, `rex.layout.*`, `rex.json.*`, `rex.log`.
- **Script-only (`nil` in config; calling errors, so shared files should check first):** `rex.sleep`, `rex.wait`, `rex.stop`, `rex.after`, `rex.every`, `rex.args`, `rex.session_id`, `rex.block_id`. `rex.on` also works only in scripts.
- In a script, `rex.bind`/`rex.unbind`/`rex.mode`/`rex.host` are accepted but have **no effect** (never reach a keymap/server).

## 2. Binding keys: `rex.bind` / `rex.unbind`
```lua
rex.bind(key, action[, args])   -- key -> action by name, optional args table
rex.bind(key, fn)               -- key -> Lua function fn(ctx, ev); return true = handled. NOT allowed in a mode.
```
```lua
rex.bind("cmd+e", "pane.zoom")
rex.bind("ctrl+alt+shift+left", "pane.resize", { direction = "left", amount = 15 })
```

- Binding a key that already has a binding **replaces** it; **the newest binding wins**. No need to unbind a default before rebinding it.
- Some actions require args (`pane.resize` needs `direction`, optional `amount`). Actions are **provided by the client**, so the list depends on the client (`rex -C <label> actions`). Examples seen in docs: `client.tab.new`, `client.tab.goto` (index), `client.tab.next`, `client.tab.previous`, `pane.split` (direction), `pane.zoom`, `pane.resize` (direction, amount?), `pane.send_key` (key), `pane.close`, `pane.balance`, `session.switch`, `client.sidebar.toggle`, `client.mode.enter/exit/exit_all`.
- `key` can be: a single key, a sequence joined with `>`, or either prefixed by `mode/`.

### Key syntax
A key = zero or more modifiers + one key, joined by `+`. **Case and modifier order don't matter** (`shift+cmd+d` == `Cmd+Shift+D`).

| Modifier | Aliases |
| --- | --- |
| `cmd` | `command`, `super`, `meta`, `win` |
| `ctrl` | `control` |
| `alt` | `opt`, `option` |
| `shift` | (none) |

- Key is a character (`d`, `1`, `,`) or a name: `enter`, `escape`, `tab`, `space`, `backspace`, `delete`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`, `f1`..`f12`.
- Keys follow the user's **keyboard layout** (`ctrl+a` = whichever key types "a"). To bind a **physical** key regardless of layout, use the US-layout W3C `KeyboardEvent.code` name in brackets: `ctrl+[KeyA]`, `[Digit1]`, `[Slash]`, `[ArrowLeft]`.
- **Write the key without shift applied.** On a US layout plus is `cmd+shift+=`, NOT `cmd++`. Bindings are matched on unshifted keys. (`%` = `shift+5`, `"` = `shift+'`.)
- An unparseable key is a `rex config check` error: `error init.lua:1: unknown key "foo"`.

### Removing: `rex.unbind`
```lua
rex.unbind(key[, target])      -- removes ALL bindings for key (yours AND client defaults); target = action name or function limits it
rex.unbind{ mode = name }      -- remove a whole mode (bindings, blocked keys, options)
rex.unbind(binding)            -- remove exactly one binding (table from rex.bindings); returns 1
```

Returns the number of *this file's* bindings removed.

Examples: `rex.unbind("cmd+d")` (every binding for the key); `rex.unbind("cmd+t", "client.tab.new")` (only if bound to that action).

- An **unbound key is not handled by Rex at all** and goes to the focused terminal.
- Rebind example: `rex.bind("cmd+k", "pane.send_key", { key = "ctrl+l" })` (Cmd+K clears the screen).

### Resolution priority (low -> high)
1. Client's default shortcuts
2. Your config file
3. Shortcuts set in the client itself (e.g. the app's **Change Shortcut...** command)

**A shortcut set in the app beats the config file.** If a binding "does nothing", check the app has no shortcut for the same key.

### Binding a Lua function
```lua
rex.bind("ctrl+shift+n", function(ctx, ev)
  rex.session.new_window{ layout = rex.layout.block{ flavor = "com.superlogical.terminal.shell" } }
  return true
end)
```

- `ev.keybinding` = the key pressed. For sequences, `ev.prefix` = list of earlier keys (a single-key binding has no `ev.prefix`).
- Return `false`/nothing -> Rex tries the next-newest function bound to the same key, then sends the key to the focused terminal.
- Function bindings have **no name**: not in the command palette, not runnable from the CLI. For anything reusable, define a custom action and bind that.
- **Not allowed in a mode** (modes need action names).
- `rex.ui.*` prompts do **not** work from a function bound directly to a key (see section 6).

### Inspecting: `rex.bindings` / `rex.modes`
```lua
rex.bindings([filter])   -- filter: table with any of key, mode, action
rex.modes()              -- each: { name, exclusive, source }
```

Each binding table: `key` (without mode), `mode` (or nil), `action` (nil for function bindings), `fn` (nil for action bindings), `args`, `source` (e.g. `keys.lua:3`). Returned in the order made.

```lua
for _, b in ipairs(rex.bindings()) do        -- after require("keys"): strip every ctrl+b> sequence
  if b.key:find("ctrl+b>", 1, true) == 1 then rex.unbind(b) end
end
```

**Limitation:** these only see your config file and files it `require`s, NOT client defaults or app-set shortcuts.

## 3. Key sequences (`a>b>c`)
Join keys with `>`; each key uses normal key syntax (modifiers included). Any length. **Escape cancels** a sequence partway.

```lua
rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>shift+5", "pane.split", { direction = "right" })
rex.bind("ctrl+x>ctrl+k>s", "session.switch")
```

### tmux-style example
```lua
rex.bind("ctrl+b>c", "client.tab.new")      -- also >n next, >p previous (client.tab.next/previous)
rex.bind("ctrl+b>shift+5", "pane.split", { direction = "right" })  -- % on US layout
rex.bind("ctrl+b>z", "pane.zoom")
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })     -- pass one through to the terminal
```

Once the prefix key starts a sequence it **no longer reaches the terminal by itself**, so provide a double-press passthrough.

### Conflict rule (gotcha)
A key either runs an action **immediately** or **starts a sequence**, never both. If bound both ways, **the newer binding wins and the older never runs**:

```lua
rex.bind("cmd+k", "pane.zoom")         -- never runs
rex.bind("cmd+k>s", "session.switch")  -- cmd+k starts a sequence
```

Swap the lines and the sequence can never start. This applies across all three sources: a sequence in your file **hides the client's default for its first key**; an app-set shortcut hides a file sequence with the same first key. Rex doesn't reorder; the client gets a **warning naming both bindings and where they were written**.

### Removing sequences
```lua
rex.unbind("ctrl+b>c")   -- removes exactly this sequence
rex.unbind("ctrl+b")     -- removes ctrl+b alone, NOT sequences starting with it
```

Unbinding a prefix never removes its sequences; each must be unbound by full name. (Prefix removal is planned for the future.)

### Function on a sequence
`rex.bind("ctrl+x>ctrl+s", function(ctx, ev) ... return true end)` gets `ev.prefix == { "ctrl+x" }` and `ev.keybinding == "ctrl+s"`. Called when the **last** key is pressed. If it returns `false`/nothing, **only the last key** is sent to the terminal (earlier keys were already consumed).

## 4. Key modes (key tables)
A mode is a named set of shortcuts active only while the mode is entered. Bind into a mode with `modename/key`:

```lua
rex.bind("cmd+r", "client.mode.enter", { name = "resize" })
rex.bind("resize/left",  "pane.resize", { direction = "left" })
rex.bind("resize/right", "pane.resize", { direction = "right" })
rex.bind("resize/shift+left", "pane.resize", { direction = "left", amount = 15 })
rex.bind("resize/g>g", "pane.zoom")       -- sequences are allowed inside modes
```

- A mode **exists as soon as a key is bound in it**. Mode names: **lowercase letters, digits, `_`, `-` only**.
- Mode bindings are separate from outside bindings (`resize/left` doesn't change plain Left).
- **A mode binding must name an action**; no Lua functions in modes. To run Lua, define a custom action.
- Client actions for modes:

| Action | Description |
| --- | --- |
| `client.mode.enter` | Enter mode given by `name` (arg `once = true` auto-leaves after one shortcut) |
| `client.mode.exit` | Leave the current (most recently entered) mode only |
| `client.mode.exit_all` | Leave every mode |

- **Escape** leaves the current mode unless the mode binds Escape to something else.
- Modes stay active until left. Modes can be entered from inside other modes; the most recently entered is checked first.
- `rex.bind("cmd+r", "client.mode.enter", { name = "resize", once = true })`.

### Unbound keys & `rex.mode`
By default a key the mode doesn't bind does what it does outside the mode (you can still type in the terminal). Declare exclusivity:

```lua
rex.mode(name[, options])            -- only option: exclusive (boolean, default false)
rex.mode("resize", { exclusive = true })   -- only the mode's own bindings do anything
```

`rex.mode` is only needed to set options.

### Removing in modes
```lua
rex.unbind("resize/left")                 -- removes the key's bindings in the mode AND BLOCKS it there (does nothing while mode active, even if bound outside)
rex.unbind("resize/left", "pane.resize")  -- removes one binding WITHOUT blocking
rex.unbind{ mode = "resize" }             -- removes whole mode: bindings, blocked keys, options
```

`rex.unbind("left")` never touches a mode; `rex.unbind("resize/left")` never touches plain Left.


## 5. Custom actions: `rex.action{ ... }`
A named Lua function that behaves like a built-in action: bindable to keys, in the command palette, runnable from the CLI.

```lua
rex.action{
  name  = "scratch",
  title = "Open Scratch Window",
  run   = function(ctx, args)
    rex.session.new_window{
      layout = rex.layout.block{ flavor = "com.superlogical.terminal.shell" },
    }
  end,
}
rex.bind("shift+cmd+n", "scratch")
```

Run with: key, command palette (search the title), or `rex do scratch`. Requires `rex config reload` after edits.

| Field | Type | Description |
| --- | --- | --- |
| `name` | string, **required** | Lowercase letters, digits, underscores only. **No dots** (dotted names like `pane.split` belong to clients/blocks). |
| `title` | string, **required** | Shown in palette and menus. |
| `run` | function, **required** | Called as `run(ctx, args)`. |
| `description` | string | Longer palette explanation. |
| `category` | string | Palette group; default `Actions`. |
| `keywords` | string | Extra palette search words. |
| `args` | table | Argument types, or a JSON Schema. |
| `repeats` | boolean | Re-run while the key is held. |

Defining the same name twice = warning; **later wins**.

### Arguments
```lua
rex.action{
  name  = "dev_layout", title = "Open Dev Layout",
  args  = { file = "string", ratio = "number?" },     -- trailing ? = optional
  run   = function(ctx, args)
    local shell = "com.superlogical.terminal.shell"
    local w, err = rex.session.new_window{ layout = rex.layout.horizontal(args.ratio or 0.5,
      rex.layout.block{ flavor = shell },
      rex.layout.block{ flavor = shell, options = { command = { "tail", "-f", args.file } } }) }
    if err ~= nil then error(err, 0) end
    return { window_id = w.window_id }
  end,
}
rex.bind("shift+cmd+l", "dev_layout", { file = "app.log" })
```

- Types: `string`, `number`, `integer`, `boolean`, `object`, `array`, `any`.
- Declared args let Rex catch mistakes: a binding with a wrong/misspelled arg is a **warning at keymap load**; the **CLI rejects it outright** (`Error: no argument named "bogus"; the action takes file, ratio?`).
- **Undeclared `args` = accepts anything.**
- `args` can be a JSON Schema as a Lua table; **a table with a `type` key is treated as a schema and used exactly as written**.
- CLI: `rex do dev_layout file=app.log ratio=0.3` (key=value pairs).

### The `run(ctx, args)` function
`args` is always a table (even if empty). `ctx` fields (absent when unknown; the Lua reference also lists `ctx.server`):

| Field | Meaning |
| --- | --- |
| `ctx.session_id` | Session the action applies to |
| `ctx.block_id` | Block it applies to, usually the focused one |
| `ctx.client_id` | Client that asked for the action |
| `ctx.origin` | `key`, `palette`, `cli`, `api`, or `script` (timer callbacks get `timer`) |

- API calls inside `run` **default to the action's own session** (no `session_id` needed). Calls on one block (e.g. `rex.session.set_block_label`) still need `block_id`; pass `ctx.block_id`.
- **Errors:** a failed API call returns `nil, errmsg` (doesn't stop the function). Check the second value. `error(msg, 0)` fails the action and reports to whoever ran it.
- **Return value** is the action's result, printed as JSON by the CLI (`{"window_id":"window:01a1..."}`). Returning nothing, `nil`, or `true` = no result.
- Time limit: an action has **30 seconds** to finish (time spent waiting for a user prompt does not count).

### Trying before reload
`rex do ~/.config/rex/init.lua --action dev_layout file=app.log` loads the file and runs one action **without touching the running config**; it really runs against the session you run it in.

### Calling other things from an action
```lua
rex.invoke(name[, args])         -- run another action; returns result, or nil + err. Same session/block/client.
rex.client.queue(name[, args])   -- ask the invoking client to run ITS OWN action (e.g. pane.zoom)
```

Example: `run = function() rex.client.queue("pane.zoom"); rex.client.queue("client.sidebar.toggle") end`.

- `rex.invoke` in config: **only that file's own actions** can be invoked. Calls nest up to **16 deep**. (In scripts, unknown names are run by the server, so a script can invoke config actions.)
- `rex.client.queue`: queued actions run **in order after `run` returns** and are **discarded if `run` fails**. It **raises an error when run from the CLI and no client can be found**, and the app only accepts CLI-run actions when **Remote Control** is enabled in its settings.
- A prompt (`rex.ui.*`) does not work inside an action run via `rex.invoke` (see section 6).

### Running commands: `rex.exec`
```lua
rex.exec(argv[, opts])   -- waits; returns result table, or nil + err ONLY if it never ran (e.g. program missing)
```
```lua
local r, err = rex.exec({ "git", "pull", "--ff-only" },
  { cwd = os.getenv("HOME") .. "/dotfiles", timeout = 20 })
if r == nil then error(err, 0) end
if not r.ok then error(r.stderr, 0) end
return { output = r.stdout }
```

- `argv` = list of strings; **no shell**, no quoting needed; program without a slash is looked up in the command's `PATH`.
- `opts`: `cwd`, `env` (`false` removes a var), `clear_env`, `stdin` (string), `timeout` (seconds -> SIGTERM, SIGKILL 2s later), `stdout`/`stderr` (`false` discards), `text` (`false` keeps `\r\n` on Windows). Unknown option = ignored with warning.
- Result: `code` (-1 if signal), `signal`, `stdout`, `stderr`, `timed_out`, `ok` (code 0 and no timeout). **Non-zero exit is still a result; check `ok`.**
- In a config action, **the server keeps handling keys/other actions while waiting**, but the action still has the 30 s limit, and **any command it started is stopped when it returns**.
- `rex.exec.start(argv[, opts])` returns a handle without waiting. Extra opts: `stdin = true` (keep open for `h:write`), `stdout`/`stderr` = callback(piece) (may end mid-line), `detach = true` (outlive the work that started it; the only way to keep a command running after the action returns). Handle: `h:wait([seconds])`, `h:write(data)`, `h:close_stdin()`, `h:kill([signal])`, `h:running()`, `h.pid`.

### Calling Rex from actions (summary)
All return a result table, or `nil, err`; they never raise.

| Call | Notes |
| --- | --- |
| `rex.session.<method>(args)` | `session_id` auto-filled; `block_id` etc. are not. Methods include `view`, `list_blocks`, `list_clients`, `describe_block`, `new_window`, `new_split`, `new_block`, `new_layer`, `close_window`, `close_layer`, `move_block`, `swap_blocks`, `detach_block`, `float_block`, `zoom_block`, `resize_pane`, `resize_layer`, `raise_layer`, `lower_layer`, `move_window`, `focus_block`, `focus_window`, `focus_direction`, `focus_next_pane`, `focus_previous_pane`, `focus_next_window`, `focus_previous_window`, `set_label`, `set_window_label`, `set_block_label`, `attach`, `detach`, `help` |
| `rex.call(method[, args])` | Any server method by full name, e.g. `rex.call("session.list")`. `rex api list` prints all. |
| `rex.block.call(creator, method[, args])` | Method on a block; `creator` = block kind full name; `block_id` filled from current block. |

Args/result of a method: `rex api describe session.new_split`.

Terminal block (`com.superlogical.terminal`) methods: `format`, `process`, `pwd`, `title`, `size`, `write`, `reset`, `resize`, `set_theme`, `program_status`, `list_dir`.

```lua
rex.block.call("com.superlogical.terminal", "write", { data = "git status\r" })
local title = rex.block.call("com.superlogical.terminal", "title", {}).title
```

### Layout builders (pure table builders, call nothing)
```lua
rex.layout.block{ flavor = "com.superlogical.terminal.shell", options = {...} }
rex.layout.horizontal(ratio, a, b)   -- ratio 0..1 = share for a
rex.layout.vertical(ratio, a, b)
```

Used as `layout =` for `new_window`, `new_split`, `new_layer`. Terminal `options`: `command` (list: program + args; default interactive shell), `shell` (`none` runs `command` directly), `cwd`, `initial_input`, `exit` (`{ on_completion = false }` keeps terminal open after program exits).

### Other helpers usable in config
- `rex.json.encode(value[, opts])` (`opts.indent = true`) / `rex.json.decode(text)`: return `nil, err` on failure. A table with keys 1..n is an array; any other table (including empty) is an object; functions/cyclic tables can't be encoded; JSON `null` -> `nil`.
- `rex.log([level, ]message)`: level `debug|info|warn|error`, default `info`.
- `rex.host{ label=..., endpoints={...} | endpoint=..., id=..., icon=... }`: declare another Rex server (config file only; `label` and `endpoints`/`endpoint` required). `rex.servers()` lists other servers' labels in a running action/script; `rex.server(label)` returns a table with `session`/`block`/`call` that go to that server (raises on unknown label; **does not auto-fill `session_id`/`block_id`**).

## 6. Custom UI: `rex.ui.input` and `rex.ui.pick`
An action can pause, ask the user in the **command palette**, then continue. Other keys/actions/events keep working while the prompt is open, and **user thinking time doesn't count toward the action's time limit**.

### `rex.ui.input{...}` -> text
```lua
local name, why, detail = rex.ui.input{
  title       = "New branch",
  placeholder = "feature/...",
  value       = "feature/",
  confirm     = "Create branch",
}
if name == nil then return end
```

| Field | Description |
| --- | --- |
| `title` | **Required.** Names the question. |
| `placeholder` | Hint shown while empty. |
| `value` | Starting text. |
| `confirm` | Label of the submit row (default row reads `Use "..."`). |
| `timeout` | Seconds to wait; **default 300, max 3600**. |

Text returns **exactly as typed** (spaces kept); may be the empty string.

### `rex.ui.pick{...}` -> id
Takes the same fields as `input` (`placeholder`/`value` apply to the filter field) plus `items`, `multiple`, `allow_other`.

```lua
local dir, why = rex.ui.pick{
  title = "Open project", placeholder = "Filter projects",
  items = {
    { id = "/Users/me/Apps/rex", title = "rex", subtitle = "~/Apps/rex", icon = "folder" },
  },
}
if dir == nil then return end
rex.session.new_window{ layout = rex.layout.block{
  flavor = "com.superlogical.terminal.shell", options = { cwd = dir } } }
```

- `items`: ordered list, **at most 2,000**, may be empty. Plain string item = `{ id = s, title = s }`: `rex.ui.pick{ title = "Fruit", items = { "Apple", "Banana" } }`.

| Item field | Description |
| --- | --- |
| `id` | Returned for the item. **Required, unique in the list.** |
| `title` | Main text; defaults to `id`. |
| `subtitle` | Second, quieter line. |
| `icon` | One of: `document`, `folder`, `branch`, `terminal`, `code`, `server`, `database`, `package`, `globe`, `link`, `person`, `tag`, `clock`, `star`, `gear`, `plus`. Other names ignored with a warning. |
| `detail` | Short text at the row's far end (e.g. file status). |
| `selected` | `true` starts ticked; **only with `multiple`**. |

- **`multiple = true`**: result is a **list of ids in `items` order** (empty list if confirmed with none ticked). Palette shows tick count by the `confirm` label; **Cmd+Return confirms**.
- **`allow_other = true`**: user may answer with typed text; result is then the table `{ text = "..." }`. **Cannot combine with `multiple`.**

Handle it with `if type(fruit) == "table" then fruit = fruit.text end`.

### No answer
Both return `nil, reason[, detail]`:

| Reason | Meaning |
| --- | --- |
| `cancelled` | User closed the prompt. |
| `timeout` | No answer within the timeout. |
| `no_client` | No Rex app connected, or every app showing it disconnected. |
| `unsupported` | No connected app can show prompts (usually older than server). |
| `busy` | Every capable app is already showing another prompt. |
| `failed` | Anything else; `detail` is a sentence (only set for `failed`; **wording may change, check the reason not the detail**). |

Typical handling: `if name == nil then if why == "cancelled" then return end; rex.log("warn", why .. " " .. (detail or "")); return end`.

**A mistake in the call itself (missing `title`, duplicate item `id`) raises an error** instead.

### Where prompts work (gotcha)
Prompts pause the action, so they only work **inside an action's `run` and functions it calls directly**. They return `nil, "failed"` (with a log warning, nobody asked) in:

- a function bound directly to a key (`rex.bind(key, function() ... end)`)
- a `rex.on` event handler
- the top level of the config file
- a function called through `pcall` / `xpcall`
- an action run via `rex.invoke`
- a function a library calls (e.g. a `table.sort` comparator)

Fix for keys: define an action and bind the key to its **name**.

### Which apps are asked
**Every** connected Rex app (including other devices) that supports prompts and isn't already showing one. **First answer wins**, prompt closes on the others; **cancelling on any one cancels everywhere**. The same applies for `rex do` (it waits for an answer; `--timeout` limits the wait).

### Headless-safe pattern
Declare the answer as an optional arg (`args = { name = "string?" }`) and ask only when missing: `local name = args.name or rex.ui.input{ title = "Your name" }`. Then `rex do greet name=Ada` runs with nobody to answer (scripts/CI).

### Server API (for app/client builders)
Apps receive a prompt as the **`client_prompt_requested`** event and answer with **`client.reply`**. Apps asked but not answering get **`client_prompt_ended`** when it closes. **Prompts need control API revision 17.**

## Source pages
- `docs/customize/config.md` (file location, reload/check, validation, require, execution model)
- `docs/customize/keyboard-shortcuts.md` (rex.bind/unbind, key syntax, priority, function bindings, rex.bindings, debugging)
- `docs/customize/key-sequences.md` (`>` sequences, conflicts, removal, ev.prefix)
- `docs/customize/key-modes.md` (`mode/key`, rex.mode, exclusive, enter/exit actions, blocking)
- `docs/customize/actions.md` (rex.action, args, ctx, invoke, client.queue, exec, `rex do --action`)
- `docs/customize/custom-ui.md` (rex.ui.input / rex.ui.pick, reasons, where prompts work)
- `docs/reference/lua.md` (exact signatures, where-each-function-works table, rex.session.*, rex.call, rex.block.call, rex.layout, rex.exec.start, timers, hosts)
- Related, not in this guide: `docs/automate/lua-scripts.md`, `docs/automate/lua-events.md`, `docs/reference/events.md`, `docs/reference/cli.md`, `docs/reference/api.md`
