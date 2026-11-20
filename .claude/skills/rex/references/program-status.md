# Program Status Protocol (OSC 7501)

> **When to read this:** you are making a CLI/TUI/agent/script that should tell the terminal (Rex or any supporting terminal)
> whether it is idle, working, blocked on the user, done, or failed; or you are reading those states back
> (Lua events, Server API events) in an app that integrates with Rex.
> It is a generic terminal escape sequence; the program only reports state, the terminal decides presentation.

## 1. What it is

A one-way escape sequence from program to terminal. The program that knows its state reports it; the terminal keeps a
current picture of every program running in it. It deliberately says nothing about presentation (no "notification", "badge",
"focus" terminology). It is not Rex-specific, though Rex uses it richly. Current draft revision: **0.4** (2026-10-10).

Complete minimal example (Terraform waiting for approval; `msg` decodes to `Apply 3 to add, 1 to change, 0 to destroy?`):

```
ESC ] 7501 ; state=blocked:kind=permission:app=terraform:msg=QXBwbHkgMyB0byBhZGQsIDEgdG8gY2hhbmdlLCAwIHRvIGRlc3Ryb3k/ ESC \
```

## 2. Byte-level conventions

| Name | Bytes |
| --- | --- |
| `ESC` | `0x1B` |
| `OSC` | `ESC ]` = `0x1B 0x5D` |
| `ST` | `ESC \` = `0x1B 0x5C`, **or** `BEL` = `0x07` |

RFC 2119/8174 keywords (MUST, SHOULD, MAY) apply only in capitals in the spec.

- **Terminal** = one window/tab/split/pane attached to one pty. Rules apply per terminal.
- **Report** = one sequence sent by a program. **Record** = what the terminal stores.

## 3. Syntax (grammar)

```
OSC 7501 ; pairs ST        report
OSC 7501 ; ? ST            feature detection

pairs    := pair (":" pair)*
pair     := key "=" value
key      := [a-z]+
value    := [A-Za-z0-9_.,+/=-]*
```

- Body = `key=value` pairs separated by `:` only. Value charset excludes `:` and `;`, so **no escaping is needed**.
- Whitespace around keys/values is stripped.
- A **malformed pair** (no `=`, empty key, byte outside value set) is **skipped**; the rest of the report is still processed.
- **Unknown keys MUST be ignored** (this is the extension mechanism).
- **Repeated key: last value wins.**
- Free-text values (`msg`, `title`) are **standard base64 of UTF-8** text (alphabet `A-Za-z0-9+/`, padding `=` optional). Decoded text MUST NOT contain control characters (`U+0000-U+001F`, `U+007F`, `U+0080-U+009F`), including newline and tab. Single-line only.
- A report is **discarded whole** (nothing applied) if it exceeds a limit (section 8), its base64 does not decode, or decoded text contains a control character.

## 4. Records and ids

A terminal holds a **set of records**, one per `id`. Each record holds exactly the keys of the **last report** for that id.

```
id      := segment ("/" segment)*
segment := [A-Za-z0-9_.+-]{1,32}
```

- No `id` = the **root record**. A program that only reports its own state uses the root record and can ignore the rest.
- **Each report replaces its record completely.** A key absent from the report is absent afterwards. So repeat `app`, `title`, etc. in every report for a record.
- A report whose `id` violates the grammar is **ignored** (not redirected to root).
- `/` creates parent/child: `build/test` is a child of `build`; `build` is a child of root. A parent need not exist. Used for **clearing** (a clear removes the subtree) and **`app` inheritance**; terminals MAY use it for grouping; it has no other meaning.
- Root and child records coexist: a program can be `idle` at its prompt while a worker record is `blocked`. The terminal chooses which to display.
- Records belong to the **terminal, not the screen**: primary/alternate screen switching has no effect. Full reset `RIS` removes all records; soft reset `DECSTR` does not.

## 5. States

`state` is **required**. A report with no `state`, or an unrecognized one, is ignored entirely (so a future state never degrades to `idle` on an old terminal).

| `state` | Meaning | Lifetime |
| --- | --- | --- |
| `idle` | At rest, waiting for the user's next instruction. | Until replaced or cleared. Terminal MAY drop on process exit / new prompt. |
| `working` | Running. May carry `progress`. | Until replaced, cleared, process exit, or next shell prompt. |
| `done` | Finished a piece of work; result ready and the user has not seen it yet. | Until replaced or cleared. **Survives** process exit and shell prompt. |
| `blocked` | Cannot continue until the user acts. `kind` says what, `msg` says why. May carry `progress`. | Same as `working` (dropped on exit / new prompt). |
| `error` | Failed and stopped. | Same as `done` (survives). |
| `clear` | Not a state: removes the addressed record **and every record beneath it**. With **no `id`**, removes **every** record on the terminal. | n/a |

Guidance:

- When the user **interrupts or cancels**, report `idle`.
- A program that **exits as soon as it finishes SHOULD report `done` or `error` right before exiting** so a record remains for the user to find.
- **Lifetime** is tied to events the terminal already sees. There is **no heartbeat**; terminals MUST NOT require re-sending. On process exit or a new shell prompt (OSC 133 `A`), the terminal MUST drop `working` and `blocked` records and MAY drop `idle`. `done`/`error` survive both; the terminal decides when to stop showing them (e.g. user returns to the terminal and presses a key).

## 6. Keys

| Key | Value | Notes |
| --- | --- | --- |
| `state` | `idle` / `working` / `done` / `blocked` / `error` / `clear` | **Required.** Unrecognized -> whole report ignored. |
| `id` | path (section 4) | Absent = root record. |
| `kind` | `permission` / `question` / `auth` | Only with `blocked`; ignored otherwise. `permission` = approval to do something; `question` = user must type an answer; `auth` = login, token, or credential. Unrecognized -> treated as absent. |
| `progress` | integer `0`-`100` | Only with `working` or `blocked`; ignored otherwise. **Absent = indeterminate** (busy, no percentage). Anything else treated as absent. |
| `app` | `[A-Za-z0-9_.+-]{1,32}` | Stable program identifier (e.g. `cargo`, `terraform`, `claude-code`) for grouping/filtering/icons. **Not a label** (that is `title`). A record without `app` **inherits from the nearest ancestor** that has one. Invalid value treated as absent. |
| `title` | base64 UTF-8 | Short human label for a record; for programs reporting several records. Root's label is normally the window title. |
| `msg` | base64 UTF-8 | One human-readable line: what the record is doing, waiting for, or finished. Terminals MAY shorten it and MUST NOT read meaning into it. |

## 7. Feature detection (optional)

```
program  -> OSC 7501 ; ? ST
terminal -> OSC 7501 ; ? : states=idle,working,done,blocked,error : kinds=permission,question,auth ST
```

- Detection is **optional**. Terminals MUST ignore unknown OSCs, so a program MAY just send reports blind (useful if it cannot read replies).
- A supporting terminal MUST reply with `?`; it MAY add `states` (comma list it accepts, not counting `clear`) and `kinds`.
- Reply **without** `states` = exactly `idle,working,done,blocked,error`. **Without** `kinds` = exactly `permission,question,auth`. These defaults are fixed forever; new states/kinds appear only by being listed. A program wanting a newer state checks the list and falls back to one present. Programs MUST ignore reply pairs they do not understand.
- No reply within a program-chosen time = unsupported. To avoid waiting, send **primary device attributes (`CSI c`)** right after the query: every terminal answers it, so if that reply arrives first, the protocol is unsupported.

## 8. Limits (hard caps; a violating report is discarded whole)

Check every pair before touching stored records. Terminals MAY pick lower limits.

| Item | Limit |
| --- | --- |
| Whole sequence, `OSC` through `ST` | **4096 bytes** (largest legal report < 3300) |
| Key length | 16 bytes |
| `msg` | 2732 bytes encoded, **2048 decoded** (check encoded size before decoding) |
| `title` | 256 bytes encoded, **192 decoded** |
| `app` | 32 bytes |
| `id` | 128 bytes total, 32 per segment, **8 levels** deep |
| Records per terminal | **256** (terminals MUST support at least 64). Creating past the cap evicts the **least recently updated** record. |

## 9. Security model

All report content is untrusted.

- Terminals MUST refuse reports whose decoded `msg`/`title` contain control characters, MUST NOT treat them as markup, SHOULD disarm bidi overrides and invisible formatting characters when displayed outside the grid.
- The **only** bytes a terminal writes back are the feature-detection reply (contains nothing from any report). There is **no way to read records back via the escape sequence**.
- UI derived from a record SHOULD say which terminal it came from (prevents spoofing across terminals).
- Terminals SHOULD rate-limit external effects (desktop notifications, sounds).

## 10. Examples

Base64 shown decoded in trailing comments.

### One program (root record; repeat `app` every time)

```
OSC 7501 ; state=working:app=brew:msg=SW5zdGFsbGluZyB1cGRhdGVz ST                                  # Installing updates
OSC 7501 ; state=blocked:kind=auth:app=brew:msg=UGFzc3dvcmQgcmVxdWlyZWQgdG8gaW5zdGFsbCB1cGRhdGVz ST  # Password required to install updates
OSC 7501 ; state=working:app=brew:msg=SW5zdGFsbGluZyB1cGRhdGVz ST                                  # Installing updates
OSC 7501 ; state=done:app=brew:msg=VXBncmFkZWQgMTIgcGFja2FnZXM= ST                                 # Upgraded 12 packages
```

The `done` record survives the shell prompt that follows.

### Several records (children inherit `app` from root)

```
OSC 7501 ; state=working:app=deploy:msg=RGVwbG95aW5nIHYyLjQuMQ== ST                                               # Deploying v2.4.1
OSC 7501 ; state=working:id=us-east:title=VVMgRWFzdA==:progress=40:msg=UHVzaGluZyBpbWFnZQ== ST                    # US East / Pushing image
OSC 7501 ; state=blocked:kind=permission:id=eu-west:title=RVUgV2VzdA==:msg=QXBwcm92ZSBkZXBsb3kgdG8gZXUtd2VzdCAocHJvZHVjdGlvbik/ ST  # EU West / Approve deploy to eu-west (production)?
OSC 7501 ; state=done:id=us-east:title=VVMgRWFzdA==:msg=SGVhbHRoeQ== ST                                           # US East / Healthy
OSC 7501 ; state=clear:id=us-east ST
OSC 7501 ; state=clear:id=eu-west ST
OSC 7501 ; state=done:app=deploy:msg=RGVwbG95ZWQgdG8gMyByZWdpb25z ST                                              # Deployed to 3 regions
```

While `eu-west` is blocked the root still says `working`; both are true and the terminal chooses what to show.

### Shell function (bash/zsh)

```sh
status() {
  printf '\e]7501;state=%s:msg=%s\e\\' "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')"
}
status working "Syncing photos"
rsync -a ~/Photos backup:/photos && status done "Photos synced" || status error "rsync failed"
```

(`base64` output must have newlines stripped; the value charset has no whitespace. Padding `=` is allowed.)

### TypeScript helper (derived from the grammar and limits above)

```ts
const b64 = (s: string) => Buffer.from(s, "utf8").toString("base64");
const CTRL = /[\u0000-\u001f\u007f-\u009f]/;

export type State = "idle" | "working" | "done" | "blocked" | "error";
export interface Report {
  state: State;
  id?: string;            // [A-Za-z0-9_.+-]{1,32} segments joined by "/", <=128 bytes, <=8 levels
  kind?: "permission" | "question" | "auth"; // blocked only
  progress?: number;      // 0..100, working/blocked only
  app?: string;           // [A-Za-z0-9_.+-]{1,32}
  title?: string;         // decoded <=192 bytes, no control chars
  msg?: string;           // decoded <=2048 bytes, no control chars
}

export function osc7501(r: Report | { state: "clear"; id?: string }): string {
  const pairs: string[] = [`state=${r.state}`];
  const a = r as Report;
  if (a.id) pairs.push(`id=${a.id}`);
  if (a.kind) pairs.push(`kind=${a.kind}`);
  if (a.progress !== undefined) pairs.push(`progress=${Math.round(a.progress)}`);
  if (a.app) pairs.push(`app=${a.app}`);
  for (const [k, v] of [["title", a.title], ["msg", a.msg]] as const) {
    if (v === undefined) continue;
    if (CTRL.test(v)) throw new Error(`${k} contains a control character`);
    pairs.push(`${k}=${b64(v)}`);
  }
  const seq = `\x1b]7501;${pairs.join(":")}\x1b\\`;
  if (Buffer.byteLength(seq) > 4096) throw new Error("report exceeds 4096 bytes");
  return seq;
}

// process.stdout.write(osc7501({ state: "working", app: "mytool", msg: "Building", progress: 40 }));
```

Remember: always re-send `app`/`title` in every report of a record (replace semantics), and send `done`/`error` before exiting.

## 11. How Rex displays and exposes it

Rex shows the **current active status** in:

- **Session picker**: sessions with completed (`done`) or blocked tasks show an indicator.
- **Tab headers** of **unfocused** tabs: an in-progress spinner for working, and a variety of symbols for blocked states.
- **Lua**: scripts can react to the `terminal.program_status_changed` event (fields `id`, `record`, `reason`), and `terminal.program_status_removed` (fields `ids`, `reason`). Terminal events arrive as `block_event` (`creator_name` `com.superlogical.terminal`, `name` `program_status_changed`) on the Server API event stream and in `rex events --json`; see `server-api.md` section 5.
- Planned (not yet shipped, per the docs): push notifications to the mobile apps, a unified priority inbox view, and more.

For an integrating app: subscribe (`session.attach` or `attach_all` with `event_scope: "all"`, since terminal events are `block_event`s) and handle `program_status_changed`/`program_status_removed`. The exact shape of `record` is not specified in these docs; inspect a live event with `rex events -s SESSION --json`.

## 12. Relationship to other sequences (why not those)

| Sequence | Difference |
| --- | --- |
| OSC 9;4 (progress) | Only busy/percent/error; no "waiting on user", no message/identity; shares number 9 with iTerm2 notifications (garbled output risk). May be sent alongside. Terminals MAY map it to the root record; since reports replace records, a terminal SHOULD stop mapping OSC 9;4 once it has received an OSC 7501 report (until next full reset). |
| OSC 9 / 99 / 777 (notifications) | One-time events, no persistent current state; imply interrupting the user. A terminal MAY emit a notification when a record changes. |
| OSC 133 (shell integration) | Emitted by the shell, so can only say a command runs/finished with exit code, not what the program is doing. Prompt start (`A`) drops `working`/`blocked` records. |
| OSC 0/2 (title) | Unstructured string; overloaded with glyphs, not machine-readable. |
| OSC 21337 (iTerm2), OSC 9999 (Orca) | Earlier work on the same idea; presentation-oriented or JSON; judged misaligned by the author. |

## 13. Implementation checklist for a program

1. Pick `app` (stable id) and decide whether you need child `id`s (parallel workers) or just the root record.
2. On start of work: `working` (+ `progress` if known, + `msg`).
3. When you need the user: `blocked` + `kind` + `msg` (what is being asked).
4. When the user answers/continues: back to `working`.
5. When the user cancels/interrupts: `idle`.
6. On completion: `done` (or `error`) **before** exiting.
7. Always repeat `app`/`title` per report; base64 `msg`/`title`; keep them single-line and under the limits.
8. Optional: query `OSC 7501 ; ? ST` (+ `CSI c` fallback) to detect support; otherwise send blind.
9. Write to the terminal's tty (stdout/tty), not into piped output; inside tmux/multiplexers pass-through may be required (not covered by the spec).

## Source pages

- `docs/build/program-status.md`
- `docs/reference/events.md` (terminal event names/fields)
- `docs/automate/server-api.md` (how events are consumed; see also `docs/reference/api.md`)
