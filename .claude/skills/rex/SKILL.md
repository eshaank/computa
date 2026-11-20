---
name: rex
description: Complete reference for Rex (superlogical.com), the terminal "multiplexer for all work" — sessions/windows/blocks, the rex CLI, the Server API, Lua config/scripts/events, custom actions & UI, the Program Status Protocol (OSC 7501), Mac/iOS actions & settings, and server install/modes/remote access. Use whenever building, scripting, or integrating an app with Rex, or when asked what Rex can do.
---

# Rex — feature map for app builders

Rex is a terminal multiplexer with a **server** (owns sessions and terminals), **clients** (macOS app, iOS app,
Windows app, the `rex` CLI, and any app you build), a **Lua** config/scripting layer, and a self-describing
**Server API**. The CLI and Lua APIs are both derived from the Server API.

Docs captured 2026-11-19 from https://www.superlogical.com/rex/docs (beta). Rex changes quickly. When a detail
matters, check the live server (`rex api describe <method>`, `rex --help`) or the live docs.

## Core model (read first)

| Concept | Meaning | ID form |
|---|---|---|
| Server | `rex` process holding state; personal / shared / login modes | socket in `REX_SERVER` |
| Session | Top-level workspace | `session:<uuid>` |
| Window | A tab within a session (CLI: "window") | `window:<uuid>` / 1-based position |
| Block | A pane; has a *flavor* (e.g. terminal `com.superlogical.terminal`) | `block:<uuid>` |
| Client | A connected app/CLI; app actions need Remote Control enabled | `-C <label>` |
| Host | Another Rex server you connect to (SSH, Tailscale…) | `-S <label>` |
| Action | Named command (`client.*`, `pane.*`, `session.*`, or custom no-dot names) | — |

Inside a Rex terminal, `REX_SERVER`, `REX_SESSION` and `REX_BLOCK` are set. Bare `rex` commands target the
current pane.

## What's available → where to read

| Need | Read |
|---|---|
| Drive Rex from a program: every server method, params, errors, events/sync, auth, transport | `references/server-api.md` |
| Shell automation: every `rex` command/flag, targeting rules, exit codes, recipes, agent setup | `references/cli.md` |
| Lua API: `rex do` scripts, `rex.session.*`, `rex.call`, `rex.block.call`, layouts, `rex.exec`, timers, JSON | `references/lua-api.md` |
| Event catalogue (session/terminal/server events + payloads), `rex.on`/`rex.wait`, `rex events`, shell patterns | `references/events-and-shell.md` |
| `init.lua` config, key bindings/sequences/modes, custom actions, `rex.ui.input`/`pick` prompts | `references/customize.md` |
| Make *your program* report state to Rex (idle/working/done/blocked/error, progress, message) via OSC 7501 | `references/program-status.md` |
| All built-in Mac (228) and iOS (109) actions, and the settings that map to `client.setting.*` actions | `references/actions-and-settings.md` |
| Installing servers (Linux/FreeBSD/Windows), server modes, remote access, upgrading, privacy, Community MCP | `references/server-and-deployment.md` |

The verbatim source pages are in `docs/` (same layout as the site, e.g. `docs/reference/api.md`). Grep them for exact
wording. They are the source of truth if a guide and a page disagree.

## Highest-value facts for integrating an app

- **Discover the API at runtime:** `rex api list`, `rex api describe <method>` (JSON Schema in/out + examples),
  `rex api call <method> '<json>'`, `help.all`, `GET /api/help`. The docs do **not** fully specify the WebSocket
  wire framing. Get it from the live server, or use `rex api call` / `rex do` as a stable boundary.
- **Build layouts atomically** from `{block:{flavor,options,label}}` / `{split:{direction,before,after,ratio}}`
  trees. Use `target.resolve` to map labels and short IDs to full IDs.
- **Terminal I/O:** read with block method `com.superlogical.terminal.format` (CLI `rex capture`). Write with
  `block.event` (bypasses Lua bindings) or `client.key`. Use `data.connect` → WebSocket `/api/data` to stream.
- **State sync:** `session.attach` / `attach_all` / `bootstrap`. Apply the snapshot, then events with a higher `seq`.
  A client that falls more than 8 MiB behind is disconnected.
- **Auth:** there are no tokens. Rex trusts the socket/named-pipe peer or Tailscale identity. Some methods are
  local-only (403 over the network).
- **App ↔ client:** `client.perform` asks Rex.app to run an action. `client_prompt_requested` + `client.reply`
  answer Lua `rex.ui` prompts.
- **Status from your program:** emit `ESC ] 7501 ; state=working:progress=40:msg=<b64> ST`. Rex shows it in the
  session picker and tab headers, and raises `terminal.program_status_changed`.
- **CLI exit codes:** 0 ok, 1 fail, 2 usage, 3 target not found or ambiguous, 4 server unreachable, 130 interrupted.
  Capture IDs from `--json` instead of relying on labels.
- **Config** lives on the server machine (`~/.config/rex/init.lua` or `$REX_CONFIG`). Reload manually with
  `rex config reload`; it is not file-watched.

## Documented but maybe not installed

The docs cover Rex's snapshot channel too, and the "Snapshot" tags are lost in the markdown copies.
A documented command can be missing from the installed Rex. Known case: `rex forward` (all
subcommands) is not in `0.1.0-preview.14`. Run `rex --help` or `rex api list -q` on the target
machine before relying on a command or method.

## Not documented yet

The **Block Plugins** and **Resources and Limits** pages appear in the sidebar but are unpublished (404). Don't
assume a plugin API exists for custom block flavors. Ask the user or check the live docs.

## Relation to the built-in `rex` skill

`rex skill setup` installs Rex's own CLI-usage skill at `~/.claude/skills/rex`, and `rex skill show` prints it.
That skill is about operating Rex from an agent's terminal. This project skill is the full feature reference for
building on Rex. Use both.
