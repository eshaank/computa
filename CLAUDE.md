# Computa

A macOS menu bar monitor built on Rex. Plan and phase status: `project-docs/monitor-plan.md`.

## The two programs

| Program | Language | Folder | Job |
|---|---|---|---|
| `computad` (the daemon) | Rust | `daemon/` | Collects system numbers and serves them over gRPC on `127.0.0.1:7300` |
| `Computa` (the menu bar app) | Swift | `app/` | Shows them |

The API between them is `proto/computa/v1/monitor.proto`. Both sides generate their types from it
at build time. Change the API there, never in generated code.

Say "daemon", not "agent", for `computad`. "Agent" means an AI coding agent in this project.

## Exception to the global TypeScript rule

This project is Rust and Swift by the owner's choice. The global "all new files must be
TypeScript" rule and `tsconfig.json` do not apply here. The other global rules do.

## Commands

The `justfile` wraps the common ones: `just build`, `just run` (the daemon), `just probe`,
`just test`, `just lint`. It adds `~/.cargo/bin` to `PATH` itself. The underlying commands:

```sh
# Daemon
cd daemon
cargo run                                   # listens on 127.0.0.1:7300; COMPUTAD_LISTEN overrides
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt --check

# App
cd app
swift build
swift test
swift run computa-probe [host:port] [count]   # prints ticks from a running daemon
```

## Rules specific to this project

- **The daemon's API is read-only.** Any program on the machine can reach a localhost port. Anything
  that changes the machine is a Rex action in `rex/computa.lua`, not a daemon call.
- **The daemon listens on `127.0.0.1` only.** Remote access goes through `rex forward`.
- **Rex reference:** the `rex` skill in `.claude/skills/rex/`. Check it before using any Rex
  command, method or event.
- **Files stay under 300 lines, functions under 50.** Split modules before they reach the limit.
- **No swallowed errors.** Log with context (`tracing` in Rust), then return the error.

## Testing inside Claude Code's sandbox

Claude's shell sandbox hides other processes, blocks the Rex socket, refuses to open ports and
breaks `swift build`. So:

- **Cargo inside the sandbox** needs `PATH="$HOME/.cargo/bin:$PATH"` and
  `CARGO_HOME="$TMPDIR/cargo-home"`, because `~/.cargo` is not writable there. Building, `clippy`,
  `fmt` and the unit tests work this way.
- **Tests that open a port** (`daemon/tests/`) fail in the sandbox with "Operation not permitted".
  Run them outside it, or set `sandbox.network.allowLocalBinding: true` in the Claude Code
  settings.
- **`swift build` and `swift test`** only work as plain commands outside the sandbox. Inside, the
  package checkouts and the build planner both fail.
- **Writes to `.git`** are blocked in the sandbox, so git commands that change the repository run
  outside it.
- **Numbers from a daemon started inside the sandbox are wrong.** The owner starts the daemon and
  the app when checking a phase's "done when" criteria.

## Rex version caveat

The Rex docs describe some features that are only on Rex's snapshot channel. `rex forward` is one:
it is not in `0.1.0-preview.14`. Check `rex --help` on the machine before relying on a command.
