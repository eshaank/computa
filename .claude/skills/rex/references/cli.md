# Rex CLI & Agents

> **When to read this:** Read before running or scripting any `rex` command, or when an agent running inside a Rex terminal
> needs to open tabs, split panes, send input, read a screen, or wait for a command.
> It covers terminology, targeting, every documented command and flag, exit codes, recipes, and the agent skill.
> Only commands documented in the source pages are listed here. If something is not here, run `rex help <command>` rather than guessing.

---

## 1. What the CLI is

`rex` is the command-line interface to Rex. It is both:

- an **administrative tool**: create sessions, split panes, list active clients, force-disconnect a client, run the server, manage hosts;
- an **automation foundation**: it has a complete Lua scripting interface (`rex do`), an event stream (`rex events`), and a raw Server API (`rex api`).

Rex adds `rex` to the `PATH` of every terminal it opens and sets environment variables so the CLI already knows which session
and block you are in. Quick try:

```sh
rex ls                 # list your sessions
rex session inspect    # details of the session you are in
rex block inspect      # details of the terminal you are typing in
rex help               # every command
rex help <command>     # details of one command
```

## 2. Terminology (taxonomy)

| Term | Meaning |
| --- | --- |
| **Session** | A group of related work, such as one project. The server keeps a session running whether or not anything is looking at it. |
| **Window** | A **tab** inside a session. Holds a layout of blocks. Windows are numbered in tab order starting at 1. |
| **Block** | One application in a window, i.e. a **pane**. Today that means a terminal. (`rex block types` lists block types.) |
| **Client** | A program connected to the server, such as Rex.app (macOS/iOS/Windows apps) or a `rex` CLI invocation. Matters when you ask the app itself to do something (e.g. open its command palette, switch session, change font size). |
| **Server** | The process that runs sessions and terminals. Reached by local Unix socket (Windows: named pipe) by default, or by host label / address. |
| **Host** | A named Rex server you connect to by label (`rex hosts`). Use with `-S LABEL`. |
| **Home** | The server this device follows for hosts and shortcuts (`rex home`). Defaults to this machine. |
| **Label** | A name you choose and can change, on sessions, windows, blocks, clients. Not unique. |
| **ID** | Never changes, never reused. Example: `block:01a10d99-0c06-7795-bf67-798ce4c36a33`, `session:01a10cf3-...`. Listing commands print short IDs (the tail, e.g. `…12bef5`). |

## 3. Environment variables

Rex sets these in every terminal it opens. Agents running in Rex terminals inherit them.

| Variable | Holds / effect |
| --- | --- |
| `REX_SESSION` | ID of the session the terminal belongs to. |
| `REX_BLOCK` | ID of the terminal's own block. |
| `REX_SERVER` | Address of the server that runs the terminal. Also sets a default for `-S`. |
| `REX_CLIENT` | Optional. Sets a default for `-C` (which client to act on). |
| `REX_BIN_DIR` | Directory containing the server's `rex` executable; Rex puts it at the front of `PATH`. |
| `REX_CONFIG` | If set, path of the config file (otherwise `rex/init.lua` in the config dir). |
| `REX_HOME` | Chooses a home for one environment; overrides `home.json`. |
| `REX_TERM` | Overrides which TERM a new terminal gets (`xterm-256color` = off switch; `auto` = server's rule). |

An agent **started outside Rex** has no `REX_SESSION`: it should run `rex ls` and work in the session matching the request
(or ask the user to choose if several match).

### PATH gotcha

Rex prepends `REX_BIN_DIR` to `PATH`, but shell startup files run afterwards and can drop it or reorder it. Check:

```sh
echo "$REX_BIN_DIR"
echo "$PATH"
```

If `PATH` does not start with `REX_BIN_DIR`, add at the **end of the shell startup file** (and prepend, never append):

```sh
# ~/.zshrc or ~/.bashrc
if [ -n "$REX_BIN_DIR" ]; then
    export PATH="$REX_BIN_DIR:$PATH"
fi
```
```fish
# ~/.config/fish/config.fish
if set -q REX_BIN_DIR
    fish_add_path --path --prepend --move $REX_BIN_DIR
end
```

Nix (NixOS / nix-darwin / home-manager): put the same check in `environment.interactiveShellInit`; for fish use
`programs.fish.interactiveShellInit`; for home-manager use e.g. `programs.zsh.initContent`. Do **not** put `REX_BIN_DIR`
in `home.sessionPath` (it is empty outside Rex, adding an empty `PATH` entry).

## 4. Global options and targeting

### 4.1 Global options (every command)

| Flag | Description |
| --- | --- |
| `-S, --server SERVER` | Connect to SERVER: a host label (from `rex hosts`) or a server address. A value with a port is always an address. `REX_SERVER` sets the default. |
| `-C, --client CLIENT` | Act on client CLIENT (label or ID). `REX_CLIENT` sets the default. |
| `--autostart` | Start a missing local server. Default `true`. |
| `--color WHEN` | `auto` (default), `always`, `never`. |
| `--timeout DURATION` | Limit each connection and non-streaming request. Default `10s`. (Does not limit event streaming.) |
| `-v, --verbose` | Increase diagnostic verbosity (repeatable). |

### 4.2 Targeting flags (per command, where supported)

With no options, a command acts on its context: inside a Rex terminal that is the terminal's own block and session,
so `rex split` splits the terminal you typed it in.

| Flag | Chooses |
| --- | --- |
| `-s, --session` | A session |
| `-w, --window` | A window (tab) within the session |
| `-b, --block` | A block (pane) |
| `-C, --client` | A client |
| `-S, --server` | A server/host |

```sh
rex send -s build -w 2 'make test'   # type into window 2 of the "build" session
rex capture -b logs                  # print the screen of the block labeled "logs"
rex -S studio ls                     # list sessions on the host labeled "studio"
```

Note: `-S`/`-C`/`--timeout` etc. are global and may appear before the subcommand (`rex -S studio ls`, `rex -C studio do ...`).

### 4.3 How a target is resolved

For a session, window, block, or client target Rex tries, in order, and stops at the first kind of match:

1. **Full ID**, e.g. `session:01a10cf3-2655-7e48-9b9c-43dd6612bef5`.
2. **Case-insensitive label**, e.g. `build`.
3. **Position counting from one** (windows are in tab order: `-w 2` is the second tab; sessions in `rex ls` order).
4. **End of an ID**, at least 4 characters, e.g. `12bef5` (what listing commands print).

If a target matches more than one thing, the command changes nothing, lists the matches, and exits with **status 3**:

```
Error: session target "work" is ambiguous
  first   …001234
  second  …00abcd
```

`-S` is the exception: it takes only a host label or an address.

**Best practice for scripts:** labels can change and can be shared; capture the ID a command returns (via `--json`) and use
that. If a block label is also a direction word (`left`, `right`, `above`, `below`), use the full ID or a hex suffix with
`rex move`. If a target could be both a block and a window (`rex focus`, `rex wait`), use a full ID.

### 4.4 "Where does the agent act?" (from the Agents page)

- **"Here", "beside you", or nothing:** the agent's own session and terminal (`REX_SESSION`/`REX_BLOCK`).
- **"The focused pane / current tab":** the pane or tab with focus in the session the user is viewing.
- **A name:** the session/tab/pane with that label. A name always wins over the agent's own location and the app's focus.

## 5. Output and exit codes

Most commands print a human table. Pass `--json` for stable JSON with **full IDs**. Example:

```
$ rex ls --json
{
  "sessions": [
    { "session_id": "session:01a10cf3-2655-7e48-9b9c-43dd6612bef5", "label": "Research" },
    { "session_id": "session:01a10d97-414b-79ee-9988-4d96d804ef90", "label": "SL Website" }
  ]
}
```

- Listing commands also accept `-q, --quiet` (IDs only, one per line) and `--short` (short IDs; `--short=false` for full IDs; default true).
- Creation commands (`rex new`, `rex run`, `rex split`, `rex window new`) take `--json` to print the created resource, so you can capture its ID.
- `rex api call`, `rex block call` print JSON results; indented on a TTY, single-line when redirected.
- `rex events --json` emits newline-delimited JSON, flushed per event.
- `rex capture` output always ends with a newline.

| Exit status | Meaning |
| --- | --- |
| 0 | Succeeded |
| 1 | Failed |
| 2 | Invalid command line |
| 3 | Target not found or ambiguous |
| 4 | Server could not be reached |
| 130 | Interrupted |

Commands that wait for a program (`rex wait`, `rex run --wait`, `rex split --wait`) exit with **that program's exit status**
(statuses above 255 are reduced modulo 256). `rex wait` returns 1 if the terminal closed before reporting a child exit, or if
the block was already closed before the wait began.

## 6. Command index

Convention: `[ ]` optional, `( | )` alternatives. All commands also accept the global options in 4.1. Several top-level
commands are documented with identical flags to a `rex block ...` subcommand (send, send-key, capture, zoom, move, swap) and
`rex new`/`rex kill` mirror `rex session new`/`rex session kill`; the top-level forms are the short everyday spellings.

### 6.1 Common commands

| Command | Purpose |
| --- | --- |
| `rex new [LABEL] [-- COMMAND...]` | Create a session (same as `rex session new`). |
| `rex ls` | List sessions. |
| `rex run [flags] -- COMMAND...` | Run a command in a **new block** (new window by default; `--split` to put it beside a block). |
| `rex split [flags] [-- COMMAND...]` | Split the focused block (default: new block on the right) running a shell or command. |
| `rex do (ACTION \| SCRIPT \| -e CODE) [KEY=VALUE...]` | Perform an action by name, or run a Lua script. |
| `rex send [TEXT]` | Send text input to a terminal. |
| `rex send-key KEY...` | Send key presses to a terminal. |
| `rex capture` | Print a terminal's screen and scrollback. |
| `rex kill SESSION...` | Kill sessions. |
| `rex forward ...` | Forward TCP ports (new, open, share, ls, close). |

#### `rex new [LABEL] [-- COMMAND...]` / `rex session new`

| Flag | Description |
| --- | --- |
| `-c, --cwd string` | Working directory for the terminal. |
| `--keep-open` | Keep the terminal open after its command exits. |
| `--shell SHELL` | Run COMMAND through SHELL's login environment (`none` starts it directly). |
| `--interactive` | Also read the shell's interactive startup files (e.g. `~/.zshrc`). |
| `--window string` | Label for the first window. |
| `--json` | Output the created session as JSON. |

#### `rex ls` / `rex session ls`

`--json`, `-q/--quiet` (IDs only), `--short` (default true).

#### `rex run [flags] -- COMMAND...`

Runs COMMAND in a new terminal block. COMMAND runs through your **login shell's environment but not its interactive
configuration**: profile variables and `PATH` apply, aliases do not. Use `--interactive` to read `~/.zshrc` etc. (for a
program whose directory is added to PATH there), `--shell` to pick another shell, `--shell=none` to start directly.
By default the block goes in a **new window**; use `--split` to place beside an existing block; `--focus=false` preserves the
active window. With `--wait`, Rex writes the creation result, then waits and returns the child's exit status.

| Flag | Description |
| --- | --- |
| `--split DIRECTION` | Place new block `right`, `left`, `above`, or `below` the anchor. |
| `--ratio PCT` | PCT percent of the split for the new block. Default `50`. |
| `-b, --block BLOCK` | Split anchor (default: focused). |
| `-s, --session` / `-w, --window` | Scope to session / window. |
| `-c, --cwd string` | Working directory. |
| `--keep-open` | Keep terminal open after its command exits. |
| `--shell SHELL` / `--interactive` | Shell choice / read interactive startup files. |
| `--label TEXT` | Label for the new block. |
| `--focus` | Focus the new block. Default `true` (use `--focus=false`). |
| `--json` | Output the creation result as JSON. |
| `--wait` | Wait and return the terminal child's exit status. |

```sh
rex run -- htop
rex run --wait -- go test ./...
rex run --split=below --ratio 30 -- tail -f app.log
rex run -b editor --split=left -- lazygit
rex run -s build -- make
rex run --interactive -- opencode
rex run --shell=none -- /opt/tool/bin/x
```

#### `rex split [flags] [-- COMMAND...]`

Same flags as `rex run`, except `--split DIRECTION` **defaults to `right`** and the command is optional (no command = a shell).
By default splits the focused block and puts the new block on its right. Use `-b BLOCK` for another anchor, `--split` for
direction, `--focus=false` to keep focus, `--wait` to wait for the exit status. Use `rex run` to place the block in a new window.

```sh
rex split
rex split --split=below
rex split -b editor --split=left -- lazygit
rex split --wait -- make
rex split -- htop
```

#### `rex do (ACTION | SCRIPT | -e CODE) [KEY=VALUE...]`

Perform an action or run Lua. Rules for the first argument:

- A name **without a dot** is an action defined in `init.lua` with `rex.action`.
- A name starting with a **client prefix** (e.g. `pane.split`, `client.tab.goto`) is performed by the targeted client (needs `-C` / `REX_CLIENT`, or exactly one connected app client).
- A name starting with a **block type's creator name** (e.g. `com.superlogical.terminal.reset`) is a block action/method.
- `rex actions` lists them.
- A **script**: path containing a slash (backslash on Windows) or ending in `.lua`; `-` reads the script from stdin; `-e CODE` gives it inline. A script can call the same API as `init.lua`; its return value prints like an action's result.
- Arguments are `KEY=VALUE` typed against the action's schema (scripts have no schema: `n=2` is a number, `name=x` a string), or `--args JSON` (also `@FILE` or `-` for stdin). Scripts read args from `rex.args`. Use `@FILE`/`-` for big args (Linux may refuse a single CLI argument > 128 KiB; the server accepts requests up to 1 MiB).
- Actions from `init.lua` may ask a question via `rex.ui.input` / `rex.ui.pick`; every connected Rex app shows it and `rex do` waits for an answer. By default waits indefinitely; `--timeout` limits (then stops the action, exit 1).
- Scripts can call other hosts: `rex.servers()` lists host labels, `rex.server(LABEL)` returns the API helpers for that host. `--server` chooses only the server `rex` itself calls.
- Scripts with `rex.on` handlers keep running and handle events one at a time until `rex.stop(CODE)` (exit code CODE, default 0), `--for DURATION`, last heard session destroyed (unless hearing all), or Ctrl-C (130). A failed handler is reported and the script continues (`--fail-fast` exits 1 at the first failure). `rex.session.attach`/`detach` change what it hears. `rex.sleep(SECONDS)` and `rex.wait(EVENT, FILTER, TIMEOUT)` can pause a script.
- `--action NAME` runs the script then runs the action it defines as NAME (try an `init.lua` action before the server reloads it).

| Flag | Description |
| --- | --- |
| `--args JSON` | Arguments as a JSON object (`@FILE`, or `-` for stdin). |
| `-s, --session` | Scope to session. |
| `-b, --block BLOCK` | Apply the action to BLOCK (default: focused block). |
| `--origin ORIGIN` | Report origin as `key`, `palette`, `api`, or `cli` (default `cli`). |
| `-e, --eval CODE` | Run CODE as a Lua script. |
| `-a, --action NAME` | Run the action NAME the script defines. |
| `--all` | Listen for events from every session (including later ones). |
| `--for DURATION` | Stop listening for events after DURATION. |
| `--fail-fast` | Exit at the first `rex.on` handler that fails. |
| `--json` | Print the result as JSON. |

```sh
rex do dev_layout branch=main
rex -C studio do pane.split direction=right
rex do com.superlogical.terminal.reset
rex -C studio do client.tab.goto index=2 --json
rex do ./layout.lua branch=main
rex do - < script.lua
rex do -e 'return rex.call("session.list")' --json
rex do notify.lua --args '{"title":"done"}'
rex do watch.lua --all --for 10m
rex do ~/.config/rex/init.lua --action dev_layout branch=main
```

(The Lua `rex.*` API itself is documented elsewhere; see the Lua/config guide.)

#### `rex send [TEXT]` (= `rex block send`)

Send input to a terminal. Reads stdin when TEXT is omitted. **Does not press Enter** unless TEXT contains a newline; pair
with `rex send-key enter`. Flags: `-b, --block`, `-s, --session`, `-w, --window`.

```sh
rex send 'make test'
rex send -b logs $'\003'
printf 'y\n' | rex send
rex send -s build -w 2 'ls'
```

#### `rex send-key KEY...` (= `rex block send-key`)

Each KEY uses Rex's key-binding syntax; join modifiers with `+` (`ctrl+c`, `shift+left`); a bracketed name such as `[Slash]`
selects a physical key. By default sends a press followed by a release per key. Printable keys are interpreted with a **US
layout** (use `rex send` when exact text matters).

| Flag | Description |
| --- | --- |
| `-b, --block` / `-s, --session` / `-w, --window` | Target. |
| `--action ACTION` | Send one `press`, `release`, or `repeat` per key instead. |

```sh
rex send-key enter
rex send-key ctrl+c
rex send 'make test' && rex send-key enter
rex send-key -b logs ctrl+c
rex send-key shift+left shift+left
rex send-key --action release ctrl+[KeyQ]
```

#### `rex capture` (= `rex block capture`)

Prints a terminal block's screen and scrollback. Without `--block`, uses `REX_BLOCK` if it names a live block, else the
focused block of the default window. Scrollback is about 64 MiB (~100,000 lines of 80-col plain text); oldest lines drop.

| Flag | Description |
| --- | --- |
| `-b, --block BLOCK` / `-s` / `-w` | Target. |
| `--format FORMAT` | `text` (default), `html` (preserves styling), `vt` (preserves control sequences). |
| `--trim` | Remove trailing blank lines. |
| `--unwrap` | Join soft-wrapped lines. |

```sh
rex capture
rex capture -b logs --trim > screen.txt
rex capture --format=html > screen.html
rex capture -s build -w 2
```

#### `rex kill SESSION...` (= `rex session kill`)

Kill sessions.

### 6.2 Forwarding (`rex forward`)

Forward TCP ports through a Rex server (like ssh `-L` / `-R`). Each forward is a **tunnel block** in a session.

| Command | Purpose / key flags |
| --- | --- |
| `rex forward new (-L\|-R) [bind_address:]port:host:hostport...` | Forward ports until interrupted (foreground). `-L, --local` listens here, connects from the server; `-R, --remote` listens on the server, connects from here. Repeatable. `-s, --session`. Prints nothing unless `-v`. Reconnects automatically if the server connection drops; exits when no forwards left; exits 3 if the session is destroyed. Bind default `127.0.0.1`; `*` = all interfaces; port `0` = free port. |
| `rex forward open [flags] (URL \| [host:]port \| BLOCK)` | `-L` for one forward, then open it. Target may be a URL, `host:port`, a port (server's localhost), or a terminal block (forwards the port a program in that terminal listens on; lists them and forwards none if several). Flags: `-b, --bind`, `-p, --port`, `-s, --session`, `--no-open` (print URL only). Opens via `$BROWSER` or the system handler. Runs in foreground. |
| `rex forward share [flags] (URL \| [host:]port)` | `-R` for one forward: expose a port on this machine on the server. Flags: `-b, --bind` (use `'*'` for other machines), `-p, --port`, `-s, --session`. Foreground. |
| `rex forward ls` | List forwards. Flags: `-s`, `-A/--all`, `--json`, `-q`, `--short`. STATE = `active`/`away`/`orphaned`; DIRECTION `client -> server` = `-L`, `server -> client` = `-R`. |
| `rex forward close [FORWARD...]` | Close forwards by closing their tunnel blocks. Flags: `-s`, `--orphaned` (all orphaned in session), `--all` (all in session). |

Caveats: sites that check the Host header or serve https with a cert for their own name may not work through a forward.

### 6.3 Layout

| Command | Purpose / flags |
| --- | --- |
| `rex focus TARGET\|DIRECTION` | Focus a block or window. Directions `left/right/up/down` (by position), `next/prev` (layout order). Stops at the edge; `--wrap` continues from the other side. A positive integer selects a window by position. Flags `-s`, `-w`, `--wrap`. |
| `rex zoom [BLOCK]` | Zoom a block to fill its window (display only; layout unchanged). Toggles; `--on` / `--off` set explicitly. Flags `-b`, `-s`, `-w`. Default block: `REX_BLOCK` if live, else focused. |
| `rex move [BLOCK] DIRECTION ANCHOR` | Move a block next to another. DIRECTION = `right/left/above/below`. Blocks may be in different windows but must be visible and in the same session. `--ratio PCT` (1-99, default 50, share for the moved block), `-s`, `-w`. Default BLOCK: `REX_BLOCK` if visible, else focused. |
| `rex swap BLOCK OTHER` | Swap layout positions of two visible blocks (same session; may be in different windows). `-s`, `-w`. |
| `rex resize [BLOCK]` | Resize a block. (The reference page lists no flags for this command; run `rex help resize`.) |

```sh
rex focus left
rex focus left --wrap
rex focus next --wrap
rex focus 2
rex focus logs
rex focus -s build editor
rex zoom --off
rex zoom -b logs --on
rex move below editor
rex move logs right editor --ratio 30
rex move c2a9f3 above 1bc2a9 -s work
rex swap editor logs
```

### 6.4 Resources: session

| Command | Purpose / flags |
| --- | --- |
| `rex session` | Manage sessions (group command). |
| `rex session new [LABEL] [-- COMMAND...]` | Create a session (flags as `rex new`). |
| `rex session ls` | List sessions (`--json`, `-q`, `--short`). |
| `rex session inspect [SESSION]` | Inspect a session (`--json`). |
| `rex session rename [SESSION] LABEL` | Rename a session. |
| `rex session move [SESSION] (--before S \| --after S \| --index N)` | Reorder sessions. Exactly one of `--before`, `--after`, `--index` (1-based; index past end = last). The order is the one `session ls` prints, and what a numeric target refers to. Default SESSION: `REX_SESSION`, else default session. |
| `rex session kill SESSION...` | Kill sessions. |

```sh
rex session move logs --before work
rex session move 3 --after 1
rex session move --index 1
rex session move build --index 99
```

### 6.5 Resources: window (tab)

| Command | Purpose / flags |
| --- | --- |
| `rex window` | Manage windows (group command). |
| `rex window new [-s SESSION] [LABEL] [-- COMMAND...]` | Create a window in the session; becomes active unless `--focus=false` (but if the session has no active window it becomes active regardless). Flags: `-s`, `-c/--cwd`, `--keep-open`, `--shell`, `--interactive`, `--focus` (default true), `--json`. |
| `rex window ls` | List windows. `-s`, `-A/--all` (every session), `--json`, `-q`, `--short`. |
| `rex window inspect [WINDOW]` | Inspect a window. `-s`, `--json`. |
| `rex window focus [WINDOW\|next\|prev]` | Focus by ID, label, position, or suffix. `-s`, `--wrap` (wrap next/prev at ends). Default: window containing `REX_BLOCK`, else the active window. |
| `rex window move [WINDOW] (--before W \| --after W \| --index N) [-s SESSION]` | Reorder tabs (exactly one position flag; 1-based). |
| `rex window rename [WINDOW] LABEL` | Rename a window. `-s`. |
| `rex window close WINDOW...` | Close windows. `-s`. |

```sh
rex window new
rex window new logs -- tail -f app.log
rex window new logs --focus=false -- tail -f app.log
rex window new -s build tests
rex window move logs --before editor
rex window move 3 --after 1
rex window move -s work build --index 99
```

### 6.6 Resources: block (pane)

| Command | Purpose / flags |
| --- | --- |
| `rex block` | Manage blocks (group command). |
| `rex block new FLAVOR` | Create a block (no flags documented; see `rex block types` for flavors). |
| `rex block ls` | List blocks. `-s`, `-w`, `-A/--all`, `--json`, `-q`, `--short`. |
| `rex block inspect [BLOCK]` | Inspect a block; lists its methods; `--json` shows method schemas. `-s`, `-w`, `--json`. |
| `rex block focus [BLOCK]` | Focus by ID, label, or suffix (default: `REX_BLOCK`, else current block). `-s`, `-w`. |
| `rex block types` | List block types (`--json`). |
| `rex block send [TEXT]` | Same as `rex send`. |
| `rex block send-key KEY...` | Same as `rex send-key`. |
| `rex block capture` | Same as `rex capture`. |
| `rex block zoom [BLOCK]` | Same as `rex zoom`. |
| `rex block move [BLOCK] DIRECTION ANCHOR` | Same as `rex move`. |
| `rex block swap BLOCK OTHER` | Same as `rex swap`. |
| `rex block stream BLOCK [DATA_REF]` | Stream block data (no flags documented). |
| `rex block call METHOD [ARGS]` | Call a block method. ARGS is a JSON object: inline, `@path`, or `-` (stdin). Default block: `REX_BLOCK` if live, else focused. `-b`, `-s`, `-w`. Results are JSON. Discover methods with `rex block inspect` (`--json` for schemas). |
| `rex block rename [BLOCK] LABEL` | Rename a block. `-s`, `-w`. |
| `rex block close BLOCK...` | Close blocks. `-s`, `-w`. |

```sh
rex block call process
rex block call -b c2a9f3 write '{"data":"ls\n"}'
rex block call -b logs format @request.json
echo '{"format":"text","trim":true}' | rex block call format -
```

### 6.7 Resources: client

A client is one program connected to the server (Rex.app, a CLI invocation). Commands that ask the app to do something need
the app running with **Remote Control** enabled in its settings.

| Command | Purpose / flags |
| --- | --- |
| `rex client` | Manage clients (group command). |
| `rex client ls` | List connected clients. CLI clients are hidden unless `--all`. `-s` (clients attached to a session), `--all`, `--json` (full server reply incl. CLI clients), `-q`, `--short`. |
| `rex client inspect [CLIENT]` | Show one client and the actions it offers. CLIENT = ID, label, or suffix; else `-C` / `REX_CLIENT`, else the app client if exactly one is connected. `--json`. |

### 6.8 Automation

| Command | Purpose / flags |
| --- | --- |
| `rex events` | Stream server events (until interrupted or disconnected). Default: session creation/removal/state changes/connectivity for the whole server. `-s SESSION` follows one session including custom events emitted by its blocks; `--all` follows every server event (including clients joining/leaving/changing); `--json` = newline-delimited JSON flushed per event. `--timeout` limits connecting/starting delivery only. |
| `rex wait TARGET` | Wait for a block, window, or session to end. For a terminal block, returns the child's exit status (works with `--keep-open` terminals; does not wait for the block to close). For other targets, succeeds when the resource closes. TARGET: ID, label, suffix, or window's 1-based position. Flags: `-s`, `-w`, `--for DURATION` (give up), `--json` (the payload that ended the wait). |
| `rex api` | Inspect and call the Server API (group). |
| `rex api call METHOD [ARGS]` | Call one API method. ARGS: JSON object inline, `@path`, or `-`. `-s SESSION` attaches to the session and adds `session_id` to ARGS if missing (if present it must match). Without `-s`, a top-level `session_id` in ARGS is used. Results are JSON. |
| `rex api list` | List API methods (separate tables for regular and block-creator methods). `-q` method names only; `--json` full help document. |
| `rex api describe METHOD` | Describe one method (schemas, examples, validation). `--json`. |
| `rex actions` | List actions: with `-C`/`REX_CLIENT`, the client's actions; otherwise server actions (`init.lua` `rex.action`s, then each block type's). ARGS column: `name?` = optional. `--json`. A key binding can name any listed action. |

```sh
rex events
rex events -s build
rex events --all
rex events --json | jq -c 'select(.type == "session_created")'
rex wait c2a9f3
rex wait build
rex wait 2 -s work
rex wait --for 10m $B || echo timed out
rex api call server.status
rex api call -s work session.view | jq '.windows | length'
rex api call session.create @layout.json
echo '{"label":"x"}' | rex api call session.create -
rex api list
rex api describe session.new_split
rex actions
rex -C studio actions
```

For the API method catalogue use `rex api list` / `rex api describe`, or the Server API guide.

### 6.9 Server

| Command | Purpose |
| --- | --- |
| `rex server` | Manage the Rex server (group). |
| `rex server run` | Run a foreground server until stopped (Ctrl+C, SIGTERM, `rex server stop` end it after saving sessions). |
| `rex server start` | Start a persistent server (idempotent; start options apply only when a new server is launched; existing server keeps its config until restarted). |
| `rex server status` | Show status (`--json`). |
| `rex server logs` | Show detached server logs: `--follow`, `-n/--lines N` (default 200), `--all`, `--state-dir DIR`. |
| `rex server stop` | Stop the server (**ends every program in its sessions**). `--if-idle` (only if no sessions and no other clients; else exit 1; needs a recent server, exit 4 otherwise), `--discard` (delete saved sessions after stopping), `--state-dir DIR`. |
| `rex server install [flags] [ssh://[USER@]HOST[:PORT]] [-- SERVER-FLAG...]` | Start your server at boot / keep it running. Linux: enables systemd user `rex.socket` and lingering. Windows: Windows Service (needs admin; asks for password) or `--user` (HKCU Run entry). With an `ssh://` endpoint: installs Rex on a remote Linux machine, sets up its server, adds it to your hosts. Flags: `--user`, `--json`, `--package`, `--label LABEL`, `--channel NAME` (stable/preview/snapshot), `--yes`. |
| `rex server uninstall [ssh://...]` | Undo install. Flags `--user`, `--json`, `--yes`. |
| `rex server tailscale` | Manage the server's Tailscale node (group). |
| `rex server tailscale on` | Serve the API over the tailnet (runtime-only; persist with `--tailscale` start flag). Flags: `--hostname`, `--allow-tailnet-members`, `--auth-key-file FILE` (or `-`; key never on the CLI), `--advertise-tag TAG`, `--control-url URL`, `--json`. |
| `rex server tailscale off` | Stop serving on the tailnet (stays signed in). `--json`. |
| `rex server tailscale logout` | Sign out and stop tailnet serving. `--json`. |
| `rex server tailscale login` | Request a sign-in link. `--json`. |
| `rex server tailscale rename NAME` | Rename the node (one DNS label, 1-63 ASCII letters/digits/hyphens). `--json`. |
| `rex server tailscale pair` | Show a QR code of the tailnet address to pair another device. `--json`. |

`rex server run` and `rex server start` flags (both unless noted):

| Flag | Description |
| --- | --- |
| `--listen ENDPOINT` (run only) | Listen on ENDPOINT (default: local Unix socket, or Windows named pipe). |
| `--extra-listen ENDPOINT` | Also listen on `unix`, `http`, `tailnet`, `tailnet-serve`, or `login-server` ENDPOINT (repeatable; not `tailnet-serve`/`login-server` on Windows). |
| `--socket-mode MODE` | Unix socket perms (owner/group bits; default `0600`; not on Windows). |
| `--allow-anonymous` | Admit anonymous callers on plain TCP listeners (**every connection gets full access**). |
| `--tailnet-allow-identified` | Admit every identified caller via the host's tailscaled (default: node owner). |
| `--tailscaled-socket PATH` | tailscaled LocalAPI socket. |
| `--tailscale-allow-tailnet-members` | Allow any tailnet member permitted by ACLs. |
| `--tailscale`, `--tailscale-hostname NAME` (default `rex`), `--tailscale-control-url URL`, `--tailscale-auth-key-file FILE`, `--tailscale-advertise-tag TAG` | Embedded tsnet node options. |
| `--websocket-origin-pattern PATTERN` | Allow browser WebSockets from a cross-origin pattern (repeatable). |
| `--block-dir DIR`, `--block-plugin-reload` | Discover executable block plugins; reload them on change. |
| `--state-dir DIR` | Persistent state directory. |
| `--restore` | Restore saved sessions (default true). |
| `--config PATH` | Config file (default `REX_CONFIG`, else `rex/init.lua`). |
| `--max-sessions N` (64), `--max-blocks N` (1024), `--max-windows N` (64), `--max-panes N` (64) | Limits; `0` = no limit. |
| `--exit-empty` (run only) | Stop when no sessions or control connections remain. |
| `--log-format text\|json`, `--log-level debug\|info\|warn\|error` | Logging. |
| `--log-max-size SIZE` (start only, default `50MiB`), `--env NAME[=VALUE]` (start only, repeatable), `--json` (start only) | Detached-log cap; pass env to a new server; JSON info. |

Notes: on Unix, SIGHUP saves-and-stops a terminal-attached server, is logged and ignored by a daemon (systemd/launchd/container),
and reopens the log file for a server launched by `rex server start`. For systemd-managed servers use
`journalctl --user -u rex` (personal) or `journalctl -u rex.service` (shared).

### 6.10 Config, keymap, login server, home, hosts, identity

| Command | Purpose / flags |
| --- | --- |
| `rex config` | Work with Rex's config file (`init.lua`; `REX_CONFIG`, else `$XDG_CONFIG_HOME/rex` or `~/.config/rex` on macOS/Linux, `%AppData%\rex` on Windows). |
| `rex config check [PATH]` | Load the config file and report location, key bind/unbind counts, modes, actions, complaints. Exit 1 on any error. `--json`. Checked by this binary only (a different server version may read it differently). |
| `rex config reload` | Make the server re-read the config and tell every client keys may have changed. Local socket only; remote callers refused. Failed read keeps the last good keys. Exit 1 on any error. `--json`. |
| `rex keymap` | Show what each key does as the server resolves it (config bindings over client defaults, under the client's own settings). `--request FILE` (send a `client.keymap` request; `-` = stdin), `--json`. |
| `rex login-server` | Run the multi-account login server (runs as root; maps callers to OS accounts via an accounts file; clients choose an account with `https://ACCOUNT@host:port`). Flags: `--listen`, `--extra-listen`, `--allow-anonymous`, `--tailscaled-socket`, `--accounts FILE`, `--runtime-root DIR`, `--pam` (default true), `--pam-service NAME`, `--log-format`. |
| `rex home` | Show or choose your home server (`--json`). |
| `rex home set ENDPOINT` | Follow ENDPOINT for hosts/shortcuts (verifies reachability first; `--label NAME`; fails while `REX_HOME` is set). |
| `rex home unset` | Follow this machine again. |
| `rex hosts` / `rex hosts list` | List hosts (`--json`). Hosts are kept by your home; this machine's own hosts also count. |
| `rex hosts add LABEL ENDPOINT...` | Add a host, tried at each endpoint in turn. `--icon NAME`. Labels unique case-insensitively. |
| `rex hosts edit LABEL` | Change a host: `--label NEW`, `--endpoint ENDPOINT` (repeatable; replaces all), `--icon NAME` (empty removes). Needs at least one option. |
| `rex hosts remove LABEL` | Remove a host. |
| `rex hosts check [LABEL...]` | Check reachability (all in parallel, up to `--timeout` each). STATUS: `reachable`, `not reachable from here`, `down`. `--json`. |
| `rex whoami` | Show your identity, server, and Rex location (`--json`). |
| `rex version` | Print version info (`--json`). |

Use a host with `-S`: `rex -S studio session ls`. Note: `rex hosts` ignores `--server` / `REX_SERVER`.

### 6.11 Terminal type (terminfo) and completion

| Command | Purpose / flags |
| --- | --- |
| `rex terminfo` | Set up/report Rex's terminal type `xterm-rex`. |
| `rex terminfo status` | Report the TERM a new terminal would get and why (`--json`). |
| `rex terminfo setup` | Install the entry in `~/.terminfo`, an ssh guard, and an `Include` line in `~/.ssh/config`. Flags: `--entry-only`, `--dry-run`, `--system` (needs root; all accounts), `--json`. Needs OpenSSH 7.8+ for the guard. |
| `rex terminfo remove` | Remove the ssh guard (entry stays). `--dry-run`, `--system`, `--json`. |
| `rex terminfo show` | Print terminfo source (e.g. `rex terminfo show \| tic -x -`). |
| `rex terminfo host install DESTINATION [-- SSH_OPTIONS...]` | Install the entry on a remote host over ssh and record it. |
| `rex terminfo host forget HOST` | Forget a recorded host. |
| `rex terminfo host ls` | List recorded hosts (`--json`). |
| `rex completion bash\|zsh\|fish\|powershell\|nu` | Generate shell completion scripts (bash: `source <(rex completion bash)`; zsh: `rex completion zsh > "${fpath[1]}/_rex"`; fish: `> ~/.config/fish/completions/rex.fish`; PowerShell: add to profile; nu: add to `config.nu`). |

### 6.12 Agent skill (`rex skill`)

| Command | Purpose / flags |
| --- | --- |
| `rex skill` | Set up agents to use Rex (group). |
| `rex skill setup` | Install Rex's skill and hook into agents found on this machine (or named). Safe to re-run. Flags: `--agent AGENT` (`claude`, `codex`, `opencode`, `pi`; repeatable), `--project` (current repo instead of account), `--dry-run`, `--force` (replace a non-Rex-installed skill named `rex`), `--session-naming` (agents name the session after their task; setup again keeps the prior choice unless passed), `--json`. |
| `rex skill status` | Report skill/hook install state per agent; changes nothing. `--project`, `--json`. |
| `rex skill remove` | Remove Rex-installed skill/hooks from every known agent (incl. uninstalled ones). `--agent`, `--project`, `--dry-run`, `--json`. |
| `rex skill show` | Print the guide Rex's skill gives agents. |

## 7. Agents: how AI coding tools use Rex

Rex ships a built-in **agent skill** so agents such as Claude Code or Codex can efficiently open tabs, split panes, read a
terminal's screen, control connected Rex apps, and more. Even without the skill, a capable agent can discover the `rex` CLI,
but the skill uses **fewer tokens and less time** and is recommended.

### 7.1 What agents can do

| User asks | Agent does |
| --- | --- |
| "Open nvim with top in a narrow pane on the right." | Opens a tab with the editor focused and gives `top` the right third. |
| "Start the dev server in another tab and tell me when it's ready." | Starts the server without taking focus, then reads its tab until it says it's listening. |
| "Run the tests beside you and fix whatever fails." | Runs tests in a split, waits for finish, reads failures from the screen, then fixes. |
| "Run `\dt` in the psql pane and tell me what's there." | Types the command into psql, presses Return, reads the result. |
| "Switch my Mac to this session and make the text bigger." | Asks the app on that Mac to show the session and increase its font size (client actions). |
| "Close everything you opened." | Closes only the tabs/panes it created. |

Requests that change the app itself (e.g. switching the Mac to a session) need the app **running with Remote Control turned
on** in its settings.

### 7.2 Setup

- **macOS:** run **Install Rex for Agents** from the command palette (Cmd+Shift+P).
- **CLI:** `rex skill setup` finds installed agents and sets up each; safe to re-run when new agents are installed.

```
$ rex skill setup
Claude Code
  skill  created      ~/.claude/skills/rex

Codex, OpenCode, Pi
  skill  created      ~/.agents/skills/rex
...
Start a new agent session inside Rex to use it.
```

It installs two things:

- A **skill** that teaches the agent the `rex` commands and when to use them. It reads its guide from the installed `rex`
  (`rex skill show`), so upgrading Rex updates what the agent knows without re-running setup.
- A **hook** that tells the agent at the start of each session that it is running in Rex and which session/terminal it is in,
  so it does not spend time or tokens finding out. Rex adds the hook to the agent's settings file and leaves the rest untouched.
  Re-running reports `unchanged` for what is current and updates older installs.

Options: see `rex skill setup` in 6.12 (`--agent NAME`, `--dry-run`, `--project`, `--force`, `--session-naming`, `--json`).
Rex finds agents by their config directory (e.g. `~/.claude`) or program on `PATH`; name unfound agents with `--agent`.
Rex honors `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.

### 7.3 Supported agents

| Agent | `--agent` | Skill location | Hook location |
| --- | --- | --- | --- |
| Claude Code | `claude` | `~/.claude/skills/rex` | `~/.claude/settings.json` |
| Codex | `codex` | `~/.agents/skills/rex` | `~/.codex/hooks.json` |
| OpenCode | `opencode` | `~/.agents/skills/rex` | Not supported |
| Pi | `pi` | `~/.agents/skills/rex` | Not supported |

Any other agent that can run commands in a Rex terminal can still use Rex: tell it to run `rex skill show` and follow the
guide it prints.

### 7.4 Approving the hook

- **Codex** asks before running a new or changed hook: approve with `/hooks` in Codex (until then it skips it).
- **Claude Code** runs no hooks at all until you **trust the folder** it starts in.

### 7.5 How it works

An agent runs in a Rex terminal like any other program and has the same `REX_SESSION` / `REX_BLOCK` env vars as the shell,
which tell it which session and terminal it is in. The user may be viewing a different session than the agent is in, so the
agent picks the target from what the user says (see 4.4). Agent started outside Rex: `rex ls`, pick the matching session or ask.

### 7.6 Removing and debugging

`rex skill remove` removes the skill and hooks from every agent Rex knows (only what Rex installed, including older copies
in other directories; other skills/hooks/settings are untouched; `--agent`, `--project`, `--dry-run` work as in setup).
Codex tracks approved hooks by their position in `hooks.json`, so removing/updating Rex's hook may require re-approval
(Rex says so in its output).

`rex skill status` states: `current`, `outdated` (older Rex or edited; `rex skill setup` updates), `missing`, `foreign` (a
`rex` skill Rex did not install; left alone unless `--force`), `unreadable`, `unsupported` (e.g. hook in an agent without hooks).

If an agent does not seem to know it is in Rex: check its session started **after** `rex skill setup` (the hook runs only at
session start); in Codex check `/hooks` approval; in Claude Code check the folder is trusted.

## 8. Common recipes (documented commands only)

Capture IDs with `--json` rather than relying on labels. `$B` below stands for a block ID you captured.

**Inspect where you are**
```sh
rex whoami
rex session inspect
rex block inspect --json
echo "$REX_SESSION $REX_BLOCK $REX_SERVER"
```

**Create a session (optionally with a command, cwd, first-window label)**
```sh
rex new build                                   # labeled session
rex new build -c ~/code/app --window editor -- nvim
rex new build --json                            # capture session ID
rex ls --json                                   # find it later
```

**Open a new tab (window) without stealing focus**
```sh
rex window new logs --focus=false -- tail -f app.log
rex window new -s build tests
```

**Split a pane (direction, ratio, command, no focus change)**
```sh
rex split                                       # shell on the right (50%)
rex split --split=below --ratio 30 -- tail -f app.log
rex split -b editor --split=left --focus=false -- lazygit
rex run --split=right --ratio 33 --label top -- top   # `run` + --split also works
```

**Run a command in its own tab and get its block ID**
```sh
rex run --focus=false --label devserver --json -- npm run dev
```

**Run a command to completion and use its exit status**
```sh
rex run --wait -- go test ./...      # exit status = the program's
rex split --wait -- make
```
Add `--keep-open` so the output stays on screen to read afterward.

**Type into a pane and press Enter**
```sh
rex send -b logs 'make test'
rex send-key -b logs enter
# or include the newline in the text
printf 'make test\n' | rex send -b logs
rex send-key -b logs ctrl+c                      # interrupt
```

**Read output (screen + scrollback)**
```sh
rex capture -b logs --trim                       # plain text
rex capture -b logs --trim --unwrap              # join soft-wrapped lines
rex capture -s build -w 2 --format=html > screen.html
```

**Wait for a command to finish, with a timeout**
```sh
rex wait "$B" --for 10m || echo "timed out or failed"   # exit = child's status
rex wait build                                   # by label
rex wait 2 -s work                               # window 2 ends
```
`rex wait` works with terminals created with `--keep-open` (it waits for the child to exit, not for the block to close).

**Wait for readiness text on screen (poll)** (no dedicated "wait for output" command is documented; poll capture)
```sh
until rex capture -b "$B" | grep -q 'listening'; do sleep 1; done
```

**Run tests beside you, then read failures**
```sh
rex run --split=right --keep-open --label tests --wait -- npm test; rc=$?
rex capture -b tests --trim
```

**Drive an interactive program (e.g. psql)**
```sh
rex send -b psql '\dt'
rex send-key -b psql enter
rex capture -b psql --trim
```

**Rearrange layout**
```sh
rex focus left            # or: right / up / down / next / prev (--wrap)
rex zoom -b logs --on
rex move logs right editor --ratio 30
rex swap editor logs
rex window move 3 --after 1
rex window rename logs
rex block rename "$B" tests
```

**Clean up only what you created**
```sh
rex block close "$B"                # a pane you made
rex window close "$W"               # a tab you made
rex kill build                      # a whole session (ends its programs)
```

**Target another host/session from anywhere**
```sh
rex hosts                           # list hosts
rex -S studio ls
rex -S studio send -s build -w 2 'make test'
```

**Ask the Rex app to do something (needs Remote Control enabled in the app)**
```sh
rex client ls                       # find the client (label/ID)
rex actions -C studio               # see its actions
rex -C studio do client.tab.goto index=2 --json
rex -C studio do pane.split direction=right
```

**React to events**
```sh
rex events -s build --json | jq -c .
rex do watch.lua --all --for 10m    # Lua script with rex.on handlers
```

**Call the raw Server API**
```sh
rex api list -q
rex api describe session.new_split
rex api call -s work session.view | jq '.windows | length'
```

**Port-forward a dev server to your machine**
```sh
rex forward open "$B"               # the port a program in that terminal listens on
rex forward open --no-open 3000
rex forward ls
rex forward close --orphaned
```

**Install the agent skill**
```sh
rex skill setup --dry-run
rex skill setup
rex skill status
```

## 9. Gotchas checklist

- Aliases and `~/.zshrc` content are **not** available in `rex run` / `rex split -- COMMAND` / `rex new -- COMMAND` unless you pass `--interactive` (or `--shell`); `--shell=none` runs the command directly.
- `rex send` does not press Enter by itself; send a trailing newline or follow with `rex send-key enter`.
- `rex send-key` assumes a US keyboard layout for printable keys; use `rex send` for exact text.
- `rex run` makes a new **window** by default; `rex split` makes a **pane** (right by default).
- Ambiguous target => nothing happens, exit 3. Use full IDs in scripts.
- `rex wait` / `--wait` exit codes are the program's, not Rex's 0-4/130 scheme.
- `rex wait` on an already-closed block returns 1.
- `rex server stop` and `rex kill` end every program in the affected sessions.
- `--allow-anonymous` gives every plain-TCP connection full access; avoid it unless intended.
- Client-prefixed actions (`pane.*`, `client.*`) need a client (`-C`/`REX_CLIENT`, or exactly one app connected) and Remote Control on in the app.
- Never pass tailscale auth keys on the command line; use `--auth-key-file` (path or `-`).
- Window numbers are tab-order positions and change when tabs move; sessions' positions follow `rex session ls` order.

## Source pages

- `docs/automate/cli.md` (The CLI: taxonomy, targets, env vars, JSON output, exit codes, PATH)
- `docs/automate/agent-skill.md` (Agents: what agents can do, `rex skill`, supported agents, how it works)
- `docs/reference/cli.md` (CLI Commands: every public command and flag, global options)
