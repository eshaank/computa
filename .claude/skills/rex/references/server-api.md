# Rex Server API

> **When to read this:** you are writing code (an app, script, bot, agent tool) that talks to a Rex server:
> creating/arranging sessions, windows and blocks, sending input, reading terminal screens, or subscribing to events.
> It is the method index for the whole control API plus transport/ID/error/event conventions.

## 0. What the docs do and do not specify (read first)

The Rex docs describe the API at the **method level** (name, arguments, behavior, error codes). They do **not** publish:

- the raw wire framing (request/response envelope JSON, message ids),
- the exact socket file names / port numbers,
- most **result** schemas (api.md documents arguments and prose; results are described only in passing).

Do not guess these. The server documents itself, always matching its own version:

| Need | Do this |
| --- | --- |
| Exact args/result schema of a method | `rex api describe <method>` (add `--json` for `input_schema`, `output_schema`, `request_example`, `response_example`, `validation_notes`) |
| Every method + schemas, machine-readable | `rex api list --json` (use to generate bindings / validate scripts) |
| Same document over HTTP | `GET /api/help` on the server (same as `help.all` plus an `http` field); `/llms.txt` renders it as Markdown |
| Same document over the API | `help.all` (all methods + `block_types`), `session.help` (one session's methods) |

**Recommended integration strategy for a new app:**

1. Prototype every call with `rex api call` and read real output (`rex api describe` first).
2. For the app itself, either (a) shell out to `rex api call ... | jq` (fully documented, works over any transport the CLI supports, including SSH and Tailscale), or (b) speak the server's native protocol directly after reading `GET /api/help` / `help.all` from a live server to learn the http/ws framing. Option (a) is the only path whose behavior is fully specified in these docs.
3. Never hardcode a method list: call `rex api list --json` or `help.all` at startup and check for `method_not_found` (older servers).

## 1. Transport and connecting

What the docs state:

| Topic | Fact |
| --- | --- |
| Linux / FreeBSD default | Server listens **only on Unix sockets** on the local machine. Personal server socket dir: `$XDG_RUNTIME_DIR/rex` (usually `/run/user/<uid>/rex`); fallback `~/.local/state/rex/run` (FreeBSD, containers). `REX_RUNTIME_DIR` overrides the dir. Shared/login servers use `/run/rex` (FreeBSD `/var/run/rex`). |
| Windows default | Listens only on a **named pipe** only the account owner can open. |
| macOS | Docs only say `server.apple.*` methods are accepted over the local Unix socket. Exact path not documented; try `rex server status`. |
| Network listeners (opt-in) | SSH (`ssh://[USER@]HOST[:PORT][/SOCKET]`, recommended), built-in Tailscale (`server.tailscale.*`), Tailscale Serve (`tailnet-serve://`, never `unix://`), tailnet address, plain HTTP (needs `--allow-anonymous`, no identity), other VPN. |
| HTTP surface | `GET /api/help` (API doc JSON), `/llms.txt` (Markdown), WebSocket `/api/data` (block data streams, see section 6). Docs refer to the API being reachable over HTTP (`Over HTTP, GET /api/help`) and to 403 for local-only methods over TCP/Tailscale; request framing is not documented. |
| Autostart | `rex` CLI commands autostart your personal server (only for the default socket dir). `REX_AUTOSTART=0` disables. `rex server start` is idempotent. `rex -S PATH server start` for a custom socket. |

### Choosing a server from the CLI / env

| Option / env | Meaning |
| --- | --- |
| `-S`, `--server` | Server by host label (`rex hosts`) or address (`ssh://...`, a socket path, etc.). `REX_SERVER` sets the default. |
| `REX_SESSION` | Set in every Rex terminal: ID of the session the terminal belongs to. |
| `REX_BLOCK` | Set in every Rex terminal: ID of the terminal's own block. |
| `REX_SERVER` | Set in every Rex terminal: address of the server running it. |
| `REX_CLIENT` | Default for `-C` (client target). |

### Authentication / identity

- There is **no token or password auth** today. Rex "trusts a caller based only on how they connect": Unix socket peer credentials (`peer` kind: uid/gid/pid), Windows named-pipe SID (`windows_peer`), Tailscale identity (`tailscale`: user_id, login_name, node, tags), or `anonymous` (plain HTTP / VPN with `--allow-anonymous`).
- A full auth system (including SSH keys) is "planned".
- `server.whoami` returns the `principal` the server assigned to your connection. It is informational: **do not use it for your own authorization decisions**.
- Some methods are **local-only**: over TCP/Tailscale they fail with **status 403** (see tags in the index: `LOCAL`).
- Method availability can vary by channel: items marked Snapshot in the docs are not yet in preview.

### Minimal client (CLI-backed, fully documented behavior)

`rex api call [-s SESSION] [-S SERVER] METHOD [JSON | @file | -]`. Output is JSON (single line when piped). Failure prints `Error: ... (status=<http> code=<code>)` and exits nonzero. `-s` auto-fills `session_id`; **other IDs are never auto-filled**; `rex api call` does **not** default to `$REX_SESSION` (pass `-s "$REX_SESSION"`).

```ts
// rexClient.ts - thin typed wrapper over `rex api call`
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const run = promisify(execFile);

export class RexError extends Error {
  constructor(msg: string, public code?: string, public status?: number) { super(msg); }
}

export async function rexCall<T = unknown>(
  method: string,
  args: Record<string, unknown> = {},
  opts: { server?: string; sessionFlag?: string } = {},
): Promise<T> {
  const argv = ["api", "call"];
  if (opts.server) argv.unshift("-S", opts.server);
  if (opts.sessionFlag) argv.push("-s", opts.sessionFlag); // only fills session_id
  argv.push(method, JSON.stringify(args));
  try {
    const { stdout } = await run("rex", argv, { maxBuffer: 64 * 1024 * 1024 });
    return (stdout.trim() ? JSON.parse(stdout) : null) as T;
  } catch (e: any) {
    const text = String(e.stderr ?? e.message);
    const m = /status=(\d+)\s+code=([a-z_]+)/.exec(text);
    console.error(`rex ${method} failed:`, text); // log with context, then rethrow
    throw new RexError(text, m?.[2], m ? Number(m[1]) : undefined);
  }
}

// usage
const sessions = await rexCall("session.list");
const s = await rexCall<any>("session.create", { label: "work" });
// independent calls: use Promise.all
const [ver, who] = await Promise.all([rexCall("server.version"), rexCall("server.whoami")]);
```

Event streaming from a process: `rex events --json` (one JSON object per line; see section 5) is the documented way to subscribe without writing the native protocol. Scope flags: none = session lifecycle, `-s SESSION` = everything in one session incl. terminal events, `--all` = everything incl. clients.

### Native protocol notes that ARE documented

- A connection sends a **`hello`** message that may carry a `client` field (`kind`, `name`, `version`, `platform`, `label`). `kind` values seen: `app`, `other` (unknown kinds count as `other`); a client that reports no kind matches no `kinds` filter. Over-long `label` (>64 bytes) is trimmed, invalid label dropped, `name`/`version` capped at 256 bytes.
- Responses to `session.attach`, `session.attach_all`, `session.bootstrap` carry a **`seq`**; events carry a `seq` too (see section 5).
- Errors carry a numeric **`status`** (HTTP-like) and a string **`code`** (section 4).
- Data connections: WebSocket to `/api/data`, first message is a **HELLO** with a ticket from `data.connect`; the server answers with **REJECT** reasons (hex, e.g. `0x01`, `0x07`) or closes with WS status **1008** (section 6).

## 2. IDs and targets

| Kind | Format | Notes |
| --- | --- | --- |
| Session | `session:<uuid>` | e.g. `session:01a1...` (the docs elide the uuid). |
| Block | `block:<uuid>` | A block = a pane (terminal, etc.). May be **detached** (running, not in any window). |
| Window | has an ID (`window_id`), prefix not shown in docs | UI calls them tabs. Default label `Window 89abcdef` = last 8 hex of ID. |
| Layer | `layer_id` | The window's tiled layout is a layer of `kind: "tiled"`; extra layers are floating. |
| Split | split ID (accepted as `anchor_id` in `session.new_split`) | IDs of untouched splits are stable across edits. |
| Client | client ID (`client_id`) | Short IDs, window positions and labels resolve via `target.resolve`. |
| Host | host `id` (chosen by the device) | See `hosts.*`. |
| Call | `call_id` | Correlates `client_*_requested` events with `client.reply`. |

- **Short ID**: last 6 hex digits of an ID (e.g. `12bef5`); `target.resolve` accepts 4 to 32 hex digits as the end of an ID.
- **Labels**: sessions/blocks/windows up to **128 chars**, clients up to **64 bytes**; no control characters; trimmed. Empty label restores the default (session: server-chosen like `quiet-meadow`; window `Window 89abcdef`; block `Block 89abcdef`).
- **Window position** is 1-based (`1` = first tab). Only windows have positions.
- Resolution order in `target.resolve`: full ID, label (case-insensitive), window position, end of ID. A window labelled `2` beats position 2.
- Treat IDs as opaque strings; never construct them.

## 3. Conceptual model and layout objects

- **Session** contains ordered **windows** (tabs). One window is **active**. Each window has a layout of **blocks** (panes) in a tree of splits plus optional **floating layers** (z-ordered, with `bounds`).
- **Layout node** (used by `session.create`/`new_window`/`new_split`/`new_layer`): either
  `{ "block": { "flavor": "com.superlogical.terminal.shell", "options": {...}, "label": "..." } }`
  or `{ "split": { "direction": "horizontal"|"vertical", "before": <node>, "after": <node>, "ratio": 0.5 } }`.
  `horizontal` = `before` left of `after`; `vertical` = `before` on top. `ratio` in (0,1) is the `before` share (default 0.5). Layout creation is **atomic** (all or nothing).
- **Flavor**: block kind string (e.g. `com.superlogical.terminal.shell`). List with `block_creator.list`; `options` must match the flavor's `options_schema`.
- **Bounds**: `[x, y, w, h]` fractions of the window width/height from top-left; `w,h > 0`; must fit inside the window.
- **Revision**: `session.view.revision` starts at 0 and increments per view change; see section 5 for sync.
- **Ownership**: when clients want different things for a block (e.g. terminal size) it follows its owner (`session.own_block`).
- **Block methods**: each creator provides its own methods (e.g. `com.superlogical.terminal.format`, `.write`, `.pwd`, `.title`, `.reset`). Call via `block.method` (`method` = short name) or by full name with `session_id`, `block_id`, `args`. Use `help.all` -> `block_types` for each method's `args_schema`/`output_schema`.

## 4. Errors

Format: HTTP-like `status` plus `code`, plus a human message. CLI shows `Error: <message> (status=400 code=bad_request)`. Lua: failed call returns `nil, message`.

| Code | Meaning (as used in the docs) |
| --- | --- |
| `bad_request` | Wrong/missing/conflicting arguments, schema violation (unknown args are errors: `additionalProperties:false`), bad bounds/ratio, bad label. status 400. |
| `method_not_found` | Server has no such method (server older than docs) or block has no such block-method. |
| `session_not_found` | `session_id` names no session. |
| `not_found` | A block/window/layer/client/call/flavor/etc. not in the session or unknown. |
| `conflict` | State forbids it: connection not attached to the session, no windows/focused block, limit reached (sessions/windows/blocks), kind mismatch (wrong creator for full-name block method), config reloaded mid-action, server in use (`server.stop if_idle`), hosts file corrupt, name collision. |
| `timeout` | Action/prompt/perform did not finish in time. |
| `not_supported` | Feature unavailable (no state dir for hosts, built-in Tailscale unavailable, embedded server cannot stop, client lacks the action). |
| `refused` | A client declined a `client.perform`. |
| `client_unavailable` | Target client reconnecting, has 16 queued requests, or disconnected. |
| `too_large` | `hosts.put` would exceed the 1 MiB hosts file. |
| `internal` | Generic failure code a client may reply with. |
| (HTTP) status `403` | Local-only method called over TCP/Tailscale. |

Gotchas: misspelled argument names are errors, not ignored (`"lable"` -> `bad_request`). A failing `rex.call` in Lua does not throw; check the second return value. For `session.bootstrap`, after any failure **close the connection and open a new one**.

## 5. Subscriptions, events, and staying in sync

### Subscribing

| Call | Effect |
| --- | --- |
| `session.attach {session_id}` | Receive **all** that session's events (incl. `block_event`) and a current `view`. Makes the connection a session client (listed by `session.list_clients`, may own blocks, may call `data.connect`). Idempotent (same `client_id`, fresh `view`). |
| `session.attach_all {event_scope}` | Receive server-wide events and the session list; does not join any session (no ownership, no `data.connect`). `event_scope`: `session` (all sessions' events except `block_event`, plus `session_created`/`session_destroyed`/`session_moved`/`tailscale_status_changed`) or `all` (also `block_event` and client events). |
| `session.bootstrap {event_scope, ...}` | One-call setup for a new connection: attach_all + list sessions + attach (+ optional data tickets). Send as the **first request**. |
| `session.detach {session_id}` | Stop attachment (connection and other subscriptions continue). |

### Ordering rule (important)

Events are subscribed **before** the snapshot is read. Apply the snapshot (`view` / session list / bootstrap result) first, then apply every event whose `seq` is **greater than the response's `seq`**, even if it arrived before the response. `seq` has no gaps. If a connection falls **more than 8 MiB** of events behind, the server **closes it** (no skipping); reconnect and re-snapshot.

### Keeping a view current

`session_view_changed` carries only `revision` (not the view) and may arrive out of revision order. Keep the view with the highest revision; call `session.view` only when an event's revision exceeds the held one. `window_created`, `window_closed`, `window_label_changed`, `active_window_changed`, `session_label_changed` arrive **before** the `session_view_changed` for the same change.

### Event catalog

Envelope (as printed by `rex events --json`, one object per line):

```json
{"type":"session_created","payload":{"session":{"session_id":"session:01a1...","label":"work"}}}
{"type":"session_event","payload":{"session_id":"session:01a1...","event":{"type":"block_event","payload":{
  "block_id":"block:01a1...","creator_name":"com.superlogical.terminal","name":"child_exited",
  "payload":{"exit_code":2,"error":"exit status 2"}}}}}
```

Session events are wrapped in `session_event` (adds `session_id`); block/terminal events are wrapped again in `block_event` (`block_id`, `creator_name`, `name`, `payload`). Lua strips both wrappers.

**Session events**

| Event | Fields |
| --- | --- |
| `window_created` | `window_id`, `label` |
| `window_closed` | `window_id` |
| `window_label_changed` | `window_id`, `label` |
| `active_window_changed` | `window_id` |
| `block_created` / `block_closed` | `block_id` |
| `session_label_changed` | `label` |
| `session_view_changed` | `revision` |
| `client_connected` | `client_id`, `principal`, `connected_at` |
| `client_disconnected` | `client_id`, `principal` |
| `client_connection_changed` | `client_id`, `principal`, `connection_state` (`lost` while reconnect grace of 60 s) |
| `creator_changed` | (none) block kinds the session can create changed |
| `block_owner_changed` | block ownership changed (from own/disown/detach) |

**Terminal events** (arrive as `block_event`, name without creator; full prefix `com.superlogical.terminal.`)

| Event | Fields |
| --- | --- |
| `child_exited` | `exit_code`, `error` (if nonzero). Only the terminal's top program (usually the shell), not each command. |
| `pwd_changed` | `pwd` (a `file://host/path` URL, only for shells set up to report), `owner` {pid,name} |
| `title_changed` | `title`, `owner` |
| `bell` | (none) |
| `process_changed` | `generation`, `foreground` (name, cwd, pid, ...; may be nil), `ancestors` |
| `desktop_notification` | `title`, `body` |
| `progress_report` | `state`, `progress` |
| `clipboard_written` | `text` |
| `program_status_changed` | `id`, `record`, `reason` (OSC 7501, see program-status.md) |
| `program_status_removed` | `ids`, `reason` |

**Server events**

| Event | Fields |
| --- | --- |
| `session_created` | `session` {`session_id`, `label`} |
| `session_destroyed` | `session_id` (last event for that session; a `client_script_events_dropped` may still follow) |
| `session_moved` | `session_id`, `before_session_id` |
| `client_joined` / `client_changed` | `client` {`client_id`, `info` {`kind`,`name`,`platform`,`version`}, `principal`, `connected_at`} |
| `client_left` | `client_id` |
| `client_performed` | outcome of a `client.perform` (scope `all`) |
| `client_script_events_dropped` | (scope `all`) |
| `keymap_changed` | `generation`, `hash` (config reloaded) |
| `hosts_changed` | `hash` |
| `tailscale_status_changed` | (status object) only to connections that called `attach_all`/`bootstrap` |

**Client-directed request events** (answer each with `client.reply`): `client_call_requested`, `client_perform_requested`, `client_prompt_requested`, and `client_prompt_ended` (close the prompt; `reason`). Always reply to every `call_id`, even on failure.

Unknown events/fields: never fail on them; ignore what you do not recognize.

## 6. Data streams (terminal output)

1. Attach with `session.attach` or `session.bootstrap` (not just `attach_all`; otherwise `conflict`).
2. `data.connect {session_id, block_id, data_ref_id: "terminal", subprotocol?: "rex.data.terminal.v1"}` -> one-time **ticket** and `expires_in_ms`.
3. Open WebSocket to `/api/data` and send the ticket in the **HELLO** message. A ticket works **once**, even if the handshake fails.
4. Failures: another user presenting the ticket -> REJECT `0x01` (same as unknown ticket; ticket is burned); wrong subprotocol (when `subprotocol` was set) -> REJECT `0x07`; unknown `data_ref_id` or unsupported subprotocol (when not set) -> WebSocket close **1008** after handshake.
5. `session.bootstrap {data_tickets: [...]}` can issue tickets for visible blocks up front (max 8 kinds).

To just read the current screen without streaming, use block method `com.superlogical.terminal.format` (e.g. `{"trim": true}` -> `.content`).

## 7. Method index (complete)

Legend: **R** required, `?` optional. `session_id` (R) is required on nearly all `session.*` methods and on `block.*`; the connection must usually be **attached** (`session.attach`/`bootstrap`/`attach_all`) or the call fails `conflict`. Tags: `LOCAL` = Unix socket/named pipe only (403 otherwise); `ATTACH` = needs `session.attach`/`bootstrap` (not just `attach_all`). `rex api describe <m>` gives the exact result schema; results below list only what the docs mention.

### 7.1 block

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `block.close` | `session_id` R; exactly one of `block_id` / `window_id`; `keep_last?` (bool) | Emits `block_closed` (+`window_closed` if last). Both/neither ids -> `bad_request`. Waits for earlier focus-changing requests on the connection. | Close a block and end its program. `window_id` closes that window's focused block. |
| `block.event` | `session_id` R, `block_id` R, `event` R (`{type, payload}`) | Returns once block received it. Only `key`, `paste`, `mouse`, `wheel`, `focus` allowed. `paste` payload `{"text"}`; `focus` payload `{"action":"in"|"out"}`. | Send raw input event to a block (bypasses Lua key bindings). Serialized in order with `client.key`. |
| `block.method` | `session_id` R, `block_id` R, `method` R (short name), `args?` | Block method's own result (`output_schema` from `help.all`). Not ordered with `client.key`; may run concurrently. Full-name form `com.superlogical.terminal.write` also works (wrong creator -> `conflict`). | Call a method a block provides (read screen, write, ...). |

### 7.2 block_creator

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `block_creator.list` | none | Creators sorted by `name`, each with flavors (`flavor`, `options_schema`), `api.methods`, `actions`. | Discover block kinds you can create and the methods each provides. |

### 7.3 client

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `client.action` | `action` R; `args?` (object); `origin?` (`key`/`palette`/`api` default; `script` -> `bad_request`); `session_id?`; `block_id?` (needs session_id); `servers?` [{name,id}]; `server?` | Dotless name = Lua config action (`rex.action`); dotted = block action/method. Block actions take no `args`. Config actions time out at 30 s. Client-own actions (e.g. `pane.split`) -> `not_found`. | Perform a config-file or block action as this client; serialized with `client.key`. |
| `client.inspect` | `client_id` R | Client details + `actions` it offers. `not_found` if gone. | Describe any connected client. |
| `client.key` | `session_id` R, `key` R, `block_id?`, `prefix?` (list of earlier keys in sequence) | `handled` (bool). Key goes to Lua bindings first (5 s limit), then to block. Needs attach. | Send a key giving Lua bindings first chance. |
| `client.keymap` | `actions?`, `server_actions?` (`all`/`configured`/`none`), `defaults?`, `overrides?` (layers); no `client_id`/`bindings` | `bindings`, `actions`, `modes`, `warnings`, `config` {instance_id, hash, generation}. Cacheable while request, `config.instance_id`, `config.hash` unchanged. | Resolve effective keymap for this client (layered: defaults < config file < `client.set_script` < overrides). |
| `client.list` | `session_id?`, `kinds?` | Clients in connect order incl. CLI; lost connections linger 60 s with `connection_state:"lost"`. | List connected clients. For live updates use `attach_all` scope `all`. |
| `client.perform` | `client_id` R, `action` R (<=256 B), `args?`, `origin?`, `session_id?`, `block_id?`, `timeout_ms?` (default 10000, max 30000) | Server sends target `client_perform_requested`; waits for `client.reply`. Errors: `bad_request`, `not_found`, `not_supported`, `refused`, `client_unavailable` (16 queued max), `timeout`. | Ask another client (e.g. Rex.app) to do one of its own actions. |
| `client.reply` | `call_id` R; exactly one of `result?` / `error?` ({code,message}) | Not queued behind `client.key`/`client.action`. Unknown/expired `call_id` -> `not_found`. Prompt answers: `{text}`, `{ids}`, `{cancelled:true}`. `error.code`: `not_supported`/`refused`/`internal`. Message cut at 4096 B. | Answer `client_call_requested`, `client_perform_requested`, `client_prompt_requested`. |
| `client.set_label` | `label` R (<=64 B, empty clears) | Fires `client_changed` (scope `all`). No `client_id` allowed. | Name this client. |
| `client.set_script` | `scripts` R (list of Lua sources, empty unloads) | `diagnostics`. Replaces earlier scripts; errors/5 s limit -> `bad_request`. Does not emit `keymap_changed`: re-call `client.keymap`. | Load Lua scripts for this client. |

### 7.4 data

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `data.connect` | `session_id` R, `block_id` R, `data_ref_id` R (e.g. `terminal`), `subprotocol?` (e.g. `rex.data.terminal.v1`) | One-time ticket + `expires_in_ms`. Needs `ATTACH`. | Get ticket for a streaming WebSocket (`/api/data`) to a block (terminal output). |

### 7.5 focus_history

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `focus_history.reverse` | `session_id?`, `not_session_id?`, `window_id?`, `not_window_id?`, `cursor?` | Returns a new `cursor` (pass back to continue). Per calling principal. | Step back through earlier focus changes. |

### 7.6 help

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `help.all` | none | `methods` (args, result, examples, notes) and `block_types` (creators, flavors, block methods with `args_schema`/`output_schema`). Also `GET /api/help`, `/llms.txt`. | Self-describe every server method. |
| `session.help` | `session_id` R | Same shape as `help.all` + `http`, limited to session methods and usable block types. | Self-describe one session's methods. Most clients use `help.all`. |

### 7.7 hosts (list of other Rex servers, shared across your devices)

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `hosts.list` | none | `hosts` (stored as-is incl. unknown fields; declared ones have `source` like `init.lua:4`), `diagnostics`. `conflict` if store file broken. | List hosts. |
| `hosts.put` | `host` R (`id?`, `label` R <=64 chars unique case-insensitively, `endpoints` R non-empty, no unix sockets/pipes) | Stored host. Idempotent. Server sets `updated_at`, drops `source`; **preserve unknown fields** on round-trip. Emits `hosts_changed`. `not_supported` w/o state dir; `too_large` >1 MiB. | Add/replace a host (by `id`; also overrides declared host and revives a removed one). |
| `hosts.remove` | `id` R | `removed` (bool); missing id is not an error. Emits `hosts_changed` only on change. | Remove/hide a host. |

### 7.8 server

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `server.version` | none | `rex_version`, `platform` (e.g. `darwin_arm64`), `api_revision`, `api_min_revision` (missing = 0), build info. | Version + build; use for feature gating. |
| `server.status` | none | identity (`host_id`: equal only if servers share files), session count, `instance_id`, `config` {generation, hash}, `tailscale`. | Server overview. Compare `config.hash`+`instance_id` to cached keymap. |
| `server.whoami` | none | `principal` by kind: `peer`{uid,gid,pid?}, `windows_peer`{sid,pid?}, `tailscale`{user_id,login_name,node,tags?}, `anonymous`; plus server account. | How the server identified you. Informational only. |
| `server.config_reload` `LOCAL` | none | `diagnostics`, `generation`. Bad Lua keeps last good config. Emits `keymap_changed` (and `hosts_changed` if hosts changed). | Reload `init.lua`. |
| `server.stop` `LOCAL` | `if_idle?` | Replies, then shuts down (close the connection after reading reply). `if_idle` -> `conflict` if in use. Without it, all sessions' programs end. `not_supported` for embedded servers. | Stop the server. |
| `server.apple.grant_file_access` `LOCAL` | `files` R (<=256; each `path` + `token`) | Per-file `readable`/`denied`/other `access`. Relative path = `denied`. Lasts until server exit. | Mac app: let server read dropped/pasted files. |
| `server.apple.privacy_status` `LOCAL` | none | `responsible_path`, `services` each with `status` (unknown values = `unknown`). Empty off macOS. | macOS privacy permissions the server (and its programs) hold. |
| `server.tailscale.enable` `LOCAL` | `allow_tailnet_members` R (bool); `hostname?`; `auth_key?` (never logged/saved/returned); `advertise_tags?` (needs `allow_tailnet_members:true`); `control_url?` | Status: `state` (`needs_login`, `disabled`, ...), `auth_url`, `dns_name`, `https.state` (`available` = reachable), `error`. Returns before connected. Already on: only applies `allow_tailnet_members`. | Turn on built-in Tailscale. |
| `server.tailscale.disable` `LOCAL` | none | Current status. Keeps sign-in. Closes tailnet connections. | Turn off built-in Tailscale. |
| `server.tailscale.login` `LOCAL` | none | Starts sign-in; link in `auth_url` (maybe later via `tailscale_status_changed`). `conflict` if off. | Request sign-in URL. |
| `server.tailscale.logout` `LOCAL` | none | Signs out and turns off. No-op if off. | Sign out of Tailscale. |
| `server.tailscale.rename` `LOCAL` | `hostname` R (1-63 ASCII letters/digits/hyphen, no leading/trailing hyphen) | `dns_name` may lag; `tailscale_status_changed` follows. `conflict` if off. | Rename tailnet device. |

### 7.9 session: lifecycle and listing

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `session.list` | none | Sessions in creation order (until `session.move`). | List sessions. |
| `session.create` | `label?` (<=128), `initial_windows?` (list of window specs with layouts) | Emits `session_created` only when all windows ready; all-or-nothing. Blocks start **unowned**. Does **not** attach. `conflict` at session cap; `not_found` bad flavor. | Create a session (optionally with windows). |
| `session.destroy` | `session_id` R | Closes all windows/blocks (hangs up programs). Returns when closed. Needs attach. | Destroy a session. |
| `session.attach` `ATTACH` | `session_id` R | `client_id`, `view`, `seq`. Idempotent. | Join a session: events + snapshot. |
| `session.attach_all` | `event_scope` R (`session`/`all`) | Session list snapshot + `seq`. Call again to change scope. | Subscribe to the whole server without joining. |
| `session.bootstrap` | `event_scope` R; `preferred_session_id?`; `attach_session_ids?` (overrides preferred; `[]` attaches none); `data_tickets?` (<=8) | `selected_session` (null if none; only when `attach_session_ids` omitted), `attached_sessions` (when `attach_session_ids` set), session list, `seq`, data tickets. First request on a connection. On failure open a new connection. | One-shot connection setup. |
| `session.detach` | `session_id` R | No-op if not attached. Owned blocks pass on; same `client_id` on re-attach. | Leave a session. |
| `session.list_clients` | `session_id` R | Clients attached via `attach`/`bootstrap` only. | List session members (see `client.list` for all). |
| `session.move` | `session_id` R, `before_session_id?` (omit = end) | Emits `session_moved`. Needs attach. Self-reference -> `bad_request`. | Reorder sessions. |
| `session.set_label` | `session_id` R, `label?` (<=128; empty restores original) | Emits `session_label_changed` then `session_view_changed`. | Rename a session. |
| `session.view` | `session_id` R | `revision`, `windows` (ordered), layers (kind `tiled`/floating, `state`, `bounds`), blocks, active window, focus, owners. Structure only (not content). Only placed blocks. | Snapshot of the whole layout. |
| `session.list_blocks` | `session_id` R | Blocks sorted by `block_id`, each with `placement` (`detached` included). Unknown placement = treat like `detached`. | List all blocks including detached. |
| `session.describe_block` | `session_id` R, `block_id` R | Block details + `api` (methods, events, actions as in `block_creator.list`). `not_found` if closing. | Inspect one block. |

### 7.10 session: windows

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `session.new_window` | `session_id` R, `layout` R, `window_label?` (<=128), `focus?` (default **true**) | `block_ids` (first has focus). Atomic. `conflict` at window/block limits. | Create a window (tab) with blocks. |
| `session.close_window` | `session_id` R, `window_id?` (omit = active) | Returns when blocks closed; next window becomes active. `conflict` if none. Second close -> `not_found`. | Close a window and its blocks. |
| `session.focus_window` | `session_id` R, `window_id` R | Focus its last-focused block. | Make a window active. |
| `session.focus_next_window` / `session.focus_previous_window` | `session_id` R, `wrap?` (default false) | Order = `windows` order in `session.view`. | Cycle windows. |
| `session.move_window` | `session_id` R, `window_id` R, `before_window_id?` (omit = end) | Self -> `bad_request`. | Reorder tabs. |
| `session.set_window_label` | `session_id` R, `window_id` R, `label?` (<=128; empty -> `Window 89abcdef`) | Emits `window_label_changed` then `session_view_changed`. | Rename a window. |

### 7.11 session: blocks and splits

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `session.new_split` | `session_id` R; `direction` R; `side` R (`before`/`after`); `layout` R; `anchor_id?` (block or split id); `window_id?` (only if no `anchor_id`); `ratio?` (0.5); `focus?` (false) | Splits focused block of `window_id`/active window if no anchor. Ends any zoom. Atomic. `bad_request` if both anchor and window. | Create blocks beside an existing block/split. |
| `session.new_block` | `session_id` R, `flavor` R, `options?`, `label?` (<=128, default flavor short name) | Block starts **detached**, caller becomes owner if attached. `conflict` at block cap. | Create a running block not shown in any window. |
| `session.move_block` | `session_id` R, `block_id` R, `anchor_block_id` R; `direction?` (horizontal), `side?` (after), `ratio?` (0.5) | Moves/places (also detached blocks) beside anchor; may cross windows; ends zoom; empties close layers/windows. `conflict` if anchor window full. | Move block or place a detached one. |
| `session.detach_block` | `session_id` R, `block_id` R | Block keeps running; may close emptied window/layer. Idempotent. | Pop a block out of its window. |
| `session.swap_blocks` | `session_id` R, `block_id` R, `other_block_id` R | Both must be placed. Splits/IDs unchanged. Same id -> `bad_request`. | Swap two blocks' positions. |
| `session.set_block_label` | `session_id` R, `block_id` R (required despite schema looking optional), `label?` (<=128; empty -> `Block 89abcdef`) | `revision`. Detached block: no event, revision unchanged. | Relabel a block. |
| `session.resize_pane` | `session_id` R, `direction` R, `before_block_id` R, `after_block_id` R, `ratio` R (0<r<1, no default) | Finds innermost split in `direction` separating the two blocks. Always bumps `revision`. Different windows/layers -> `bad_request`. | Move a split border. |
| `session.zoom_block` | `session_id` R, `block_id?` (focuses it), `window_id?` (only without `block_id`), `zoom?` (omit = toggle) | Zoom is display-only; ends when focus moves. | Zoom a block to fill its window. |
| `session.own_block` `ATTACH` | `session_id` R, `block_ids?` (omit/empty = all), `mode?` (`take` default / `request`) | `blocks` (owner each). Emits `block_owner_changed` (+`session_view_changed`). Bad id -> `bad_request`, nothing changes. | Claim blocks (block follows owner's size). |
| `session.disown_block` `ATTACH` | `session_id` R, `block_ids?` (omit/empty = all) | `blocks` (owner each). Passes to next client in line. | Release claim on blocks. |

### 7.12 session: focus

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `session.focus_block` | `session_id` R, `block_id` R | Must be placed. Makes window active; ends zoom if focus changes. | Focus a block. |
| `session.focus_direction` | `session_id` R, `direction` R (left/right/up/down), `wrap?` (default false; **older servers always wrap**) | No-op success if nothing that way. Includes floating layers by screen position. `conflict` no windows. | Spatial focus move. |
| `session.focus_next_pane` / `session.focus_previous_pane` | `session_id` R, `wrap?` (false) | Layout order: tiled (before then after), then floating back-to-front. | Cycle panes in active window. |

### 7.13 session: floating layers

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `session.new_layer` | `session_id` R, `bounds` R, `layout` R, `window_id?` (active), `focus?` (false) | New layer at front. Atomic. | Create blocks in a new floating layer. |
| `session.float_block` | `session_id` R, `block_id` R (in layout, not already floating), `bounds` R | Focus/active window unchanged; ends zoom. May leave tiled layer empty (keeps `layer_id`). | Float an existing block. |
| `session.close_layer` | `session_id` R, `layer_id` R (floating only; tiled -> `bad_request`) | Closes its blocks, returns when closed. | Close a floating layer. |
| `session.raise_layer` | `session_id` R, `layer_id` R, `relative_layer_id?` (place just above; same window, not tiled) | No-op if in place. | Bring layer forward. |
| `session.lower_layer` | `session_id` R, `layer_id` R, `relative_layer_id?` | Never goes behind the tiled layout. | Send layer back. |
| `session.resize_layer` | `session_id` R, `layer_id` R, `bounds` R | Focus/order unchanged. | Move/resize a floating layer. |
| `session.set_layer_state` | `session_id` R, `layer_id` R, `state` R (`normal`/`minimized`), `focus?` (needs `normal`) | `focus:true` also raises, focuses, activates window in one revision. Minimizing tiled layer or last visible panes -> `bad_request`. Minimized layers keep running; `state` omitted when normal. | Minimize/restore (and optionally focus) a layer. |

### 7.14 target

| Method | Params | Result / notes | Purpose |
| --- | --- | --- | --- |
| `target.resolve` | `kinds` R (`session`/`window`/`block`/`client`; each once; `client` alone), `queries` R (>=1; full ID, label, window position, ID suffix, or `""` for default), `context?` ({session_id, block_id, client_id}), `scope?` ({session}/{window}; not with kind `session`) | `results[]` one per query, in order: `status` (`not_found`, `ambiguous`, or a match status; check `rex api describe target.resolve`), `candidates` (each with `kind`, `where`), `reason`. Empty query = default (`context.block_id`, else focused block, etc.). | Map human names to IDs. |
| `target.complete` | `kinds` R, `prefix` R, `context?`, `scope?` | `completions` grouped by kind: labels, then window positions, then short IDs; `where` e.g. `Rex.app 1.6.0` for clients. Control chars in prefix -> `bad_request`. | Tab completion. |

## 8. Common recipes

```sh
# list, create, arrange
rex api call session.list
rex api call session.create '{"label":"work","initial_windows":[{"window_label":"main","layout":{"block":{"flavor":"com.superlogical.terminal.shell"}}}]}'
rex api call -s work session.new_split '{"direction":"horizontal","side":"after","layout":{"block":{"flavor":"com.superlogical.terminal.shell","label":"logs"}}}'
rex api call -s work session.view | jq '.windows | length'

# run a command in a block, then read the screen
rex api call -s work com.superlogical.terminal.write  '{"block_id":"block:...","args":{...}}'    # args per `rex api describe`
rex api call -s work com.superlogical.terminal.format '{"block_id":"block:...","args":{"trim":true}}'
rex api call -s work block.event '{"block_id":"block:...","event":{"type":"paste","payload":{"text":"ls\n"}}}'
```

(The `initial_windows` window-spec shape is not spelled out in api.md. Confirm with `rex api describe session.create`.)

From Lua: `rex.call("server.version")`; `rex.session.view{}` (helpers exist for every `session.*` method that acts on an existing session, auto-filling `session_id`; `session.list`/`session.create` have none, use `rex.call`); `rex.block.call("com.superlogical.terminal", "format", {trim=true}).content`.

## 9. Gotchas checklist

- Arguments are one JSON object; unknown keys fail with `bad_request`.
- `rex api call` fills only `session_id` (via `-s`); every `block_id`/`window_id` must be explicit.
- Most `session.*` calls need the connection attached; `data.connect`, `own_block`, `disown_block` need `attach`/`bootstrap` specifically.
- `session.create` neither attaches you nor gives you block ownership.
- `session.new_window` defaults `focus: true`; `new_split`/`new_layer` default `focus: false`.
- `session.set_block_label` requires `block_id` though the schema marks only `session_id` required.
- Order: `client.key`, `client.action`, `block.event`, and focus/layout-changing methods are serialized per connection; `block.method` is **not**, so await earlier replies yourself.
- `block.event` bypasses Lua key bindings; `client.key` goes through them.
- Event sync: apply snapshot, then events with higher `seq`; fall >8 MiB behind and you are disconnected.
- `session_view_changed` has only `revision`; refetch with `session.view` when higher.
- Layout creation is atomic: either every block starts or none.
- Zoom ends on layout changes and focus moves.
- `pwd` from terminal is a `file://` URL.
- `server.stop`, `server.config_reload`, `server.tailscale.*`, `server.apple.*` work only on local socket/pipe.
- Never log or persist Tailscale `auth_key`.
- Host records can carry unknown fields: send back exactly what `hosts.list` gave you (plus edits).
- Older servers: check `server.version` `api_revision`/`api_min_revision`; handle `method_not_found`.

## Source pages

- `docs/automate/server-api.md`
- `docs/reference/api.md`
- `docs/reference/events.md` (event catalog and `rex events --json` envelope)
- `docs/automate/cli.md` (env vars, `-S`, targets)
- `docs/linux/remote-access.md`, `docs/linux/server-modes.md` (listeners, socket locations)
