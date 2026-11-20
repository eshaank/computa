# Computa monitor: build plan

Status as of 2026-11-20: phases 0 to 6 are built. Phase 0 is on `main`; phases 1 to 6 are pull
requests 1 to 6, each stacked on the one before. Phase 6 is a draft because it has not run against
the real M1. Nobody has yet seen the app running on screen; each pull request lists what to try.
The "result" sections below say what was checked for each phase.

## Phase 0 result (2026-11-19)

gRPC works for both languages on this Mac, so it stays. It has not been tried through a tunnel to
another machine; that is phase 6.

- The Rust daemon streamed 10 consecutive ticks to the Swift client, one per second.
- `grpcurl` called the same stream using the `.proto` file.
- Daemon: 5 tests pass (one streams over real gRPC), `clippy` and `fmt` are clean.
- App: 6 tests pass, and the build has no warnings.
- The Swift build needs no `protoc` install: the gRPC package ships its own. `brew install
  protobuf` is only needed for the Rust build.
- The first Swift build takes about 3.5 minutes, because it compiles the gRPC libraries. Later
  builds only recompile what changed.
- **Found: `rex forward` is not in the installed Rex** (`0.1.0-preview.14`). The docs describe
  it, but it is on Rex's snapshot channel and has not reached preview. Phase 6 is updated below.

## The short version

- **Two programs.** A Rust **daemon** (`computad`) collects the numbers. A Swift **menu bar app**
  (`Computa`) shows them.
- **RPC between them: yes.** The app talks to the daemon over one typed, streaming RPC API. The same
  API is used for this Mac and for the M1. Only the address changes.
- **Local first.** Phases 0–5 run entirely on this Mac, with no SSH, NetBird or tunnel. The M1 is
  phase 6: the same daemon on another machine, plus a machine switcher in the app.
- **Rex's role.** Rex tells the daemon which processes belong to which terminal session. Lua
  actions in Rex's config do anything that changes the machine (phase 5). In phase 6 the RPC
  connection to the M1 goes through an SSH tunnel: Rex's own if the installed Rex has it by then,
  plain `ssh` otherwise.
- **Total estimate:** roughly 9 hours of my working time across all phases.

## Phase 1 result (2026-11-20)

The daemon reports real numbers. Checked on this Mac (an M4 Pro, 24 GB) under heavy load:

| Check | Daemon | Reference | Target | Result |
|---|---|---|---|---|
| Memory used | 21.28–21.74 GB | `vm_stat`, same formula: 21.17–21.68 GB | within 3% | within 0.5% |
| Swap used | 21558.50 MiB | `vm.swapusage`: 21558.50M | — | exact |
| CPU total | 34.3% | `top`: 31.6% | within 5 points | 2.7 points |
| Startup disk total and available | 971,350,180 / 263,905,716 KiB | `df -k /`: 971,350,180 / 263,905,960 | within 1% | under 0.001% |
| Network, 50 MB download | 53.6 MB | 50.0 MB file | within 10% | 7.3% over |
| Daemon's own CPU | about 0.1% | — | under 1% | pass |
| Daemon's own memory | about 8 MB | — | under 30 MB | pass |

- 34 tests pass. One of them runs the real server and checks facts that must always hold.
- "Disk used" is total minus available, which covers the whole APFS container. `df`'s own "Used"
  column shows only the sealed system volume, so the two differ by design.
- Network totals count wired, Wi-Fi and cellular only. A VPN tunnel such as NetBird's is listed
  with its own rate but left out of the total, because its traffic also crosses the physical
  interface.
- Not exercised: a Mac with no battery, a Mac with one kind of core, and memory pressure at
  normal or critical (this Mac sat at "warning" throughout).

## Phase 2 result (2026-11-20)

The menu bar app exists: popover, Prevent Sleep, a stand-in dashboard window and Preferences.

- Checked by machine: 44 tests pass, including the reconnect loop and Prevent Sleep against the
  real macOS power API. The app's client read live samples from the real daemon. The views were
  rendered offscreen and compared with the reference screenshot.
- Not checked: anything that needs the app on screen. Nobody has seen it running in the menu bar
  yet. The hand-checks are listed in pull request 2.
- The popover adds a figure under each ring, which the reference does not have, so the numbers can
  be compared with the daemon's.

## Phase 3 result (2026-11-20)

The daemon lists processes grouped by app, and the dashboard window shows them with history charts.

| Check | Daemon | Reference | Target | Result |
|---|---|---|---|---|
| Memory, five processes from 11 MB to 8.2 GB | for example 8246.1 MiB | `top`: 8246M | within 5% | within 0.2% |
| CPU of a busy loop | 99.9–100.0% | CPU-time change over 5 s: 99.9% | within 10 points | 0.1 points |
| Chrome group size | 123 | `ps`: 123 | equal | equal |
| Every process accounted for | 628 listed + 247 unreadable = 875 | `ps`: 875 | equal | equal |
| Daemon CPU while a client watches processes | 0.63% | — | under 2% | pass |
| Daemon CPU with no client | 0.13% | — | about 0.1% | pass |

- Daemon: 74 tests. App: 76 tests. The app's client read history and the live process list from
  the real daemon.
- **No memory figure for root's processes.** The plan promised an estimated "System and other
  users" row. It always came out as zero: a process's footprint counts compressed and swapped
  memory at full size, so your own processes alone add up to more than the machine has in use.
  The dashboard shows how many such processes there are, and no figure.
- The "+N matches `ps`" check in the plan under-counts Electron apps, whose helpers rename
  themselves. The comparison above used each process's real path instead.
- Not checked: the dashboard on screen. The hand-checks are listed in pull request 3.

## Phase 4 result (2026-11-20)

The daemon reports CPU and memory per Rex session, tab and pane, and the dashboard has a Sessions
tab. The popover has a "Claude Code" row.

| Check | Observed | Target | Result |
|---|---|---|---|
| Sessions, tabs and panes match Rex | 3 sessions, 12 panes, same ids and order | equal | equal |
| Claude panes found | 8, each with the right working directory | — | pass |
| Pane memory vs `top` over the same processes | 253.8 vs 254.2 MiB; 84.1 vs 84.1 MiB | within 5% | within 0.2% |
| A closed pane disappears | 32–44 ms | under 2 s | pass |
| A new pane appears | about 235 ms | about 2 s | pass |
| Rex unreachable | the stream says why; other calls keep working | — | pass |
| Daemon CPU with a sessions client, `rex` children included | 1.36% | under 2% | pass |

- Daemon: 102 tests, one against a real Rex server. App: 101 tests. The app's client printed the
  real sessions from the real daemon.
- Claude Code started through a wrapper (for example `node cli.js`) is not recognised. Detection
  uses the program name `claude` or a path containing `/claude/versions/`.
- Not checked: installing the daemon as a login item (`just install-daemon` was only run with
  `--dry-run`), recovery when the Rex server itself restarts, and the Sessions tab on screen.

## Phase 5 result (2026-11-20)

The Sessions tab can close a pane and open a process viewer, through two Rex actions written in
Lua.

- Checked by machine:
  - Rex's config checker loads `rex/computa.lua` with both actions.
  - `just test-rex-actions` runs both actions against the real Rex server in a throwaway session:
    7 checks pass.
  - The real `rex` command prints the JSON the app expects, accepts the daemon's session ids, and
    reports a pane that is already gone as an error the app can show.
  - The installer was run against a test config file: it asks first, backs up, adds one line,
    does nothing the second time, and removes the line again.
  - App: 132 tests, including the runner against a stand-in `rex` (exact arguments, errors, and a
    hung command being stopped).
- Not done, on purpose: your real `init.lua` was not changed. Until you run
  `just install-rex-actions` and `rex config reload`, the buttons show "Rex actions not installed".
- Not checked: the buttons in the running app, and the actions as loaded by the Rex server from
  your config (they were run from a script, which uses the same code).

## Phase 6 result (2026-11-20)

The app can watch a daemon on another Mac. **None of it has run against the real M1.** Remote
Login is off on this Mac and the M1 could not be reached, so real `ssh` was never run.

- Built: a machine list in Preferences, a switcher in the popover and dashboard, an SSH tunnel the
  app starts and restarts by itself, app icons fetched from the remote daemon, and Rex actions
  sent with `rex -S <label>`.
- Checked by machine:
  - The real tunnel supervisor, with a stand-in for `ssh` that forwards a port to a real daemon:
    the app's real client received the host, live samples, history and an app icon through it,
    and switching back to This Mac stopped the forwarder.
  - The daemon's icon call returned a correct icon for all 87 apps on this Mac.
  - The exact `ssh` arguments, the retry delays (1, 2, 4, 8, 15 s), and a destination that could
    be read as an ssh option being refused before anything starts.
  - Daemon: 130 tests. App: 170 tests.
- The tunnel uses plain `ssh`, not `rex forward`, which the installed Rex does not have. It sits
  behind one interface, so a `rex forward` version can be added later.
- A crash from phase 3 was found and fixed here: closing the dashboard while it waited between
  history fetches crashed in tests. Pull requests 3 to 5 still contain it; it is fixed from this
  pull request on.

### What to do on the M1

1. On the M1: System Settings → General → Sharing → turn on Remote Login.
2. On this Mac: `ssh-copy-id you@<M1 NetBird address>`. Then
   `ssh -o BatchMode=yes you@<address> true` must succeed without asking for anything. The app
   cannot type a password.
3. On the M1: clone this repository, install Rust and protobuf (see the end of this plan), and run
   `just install-daemon`.
4. In Computa on this Mac: Preferences → Add Machine. Name it, give `you@<address>` as the SSH
   destination, and leave the daemon port at 7300. Add a Rex host label only if `rex -S <label>`
   already works from this Mac.
5. Pick the M1 in the popover's machine menu. Expect "Connecting…", then the M1's numbers within
   about 2 seconds.
6. Disconnect NetBird. Expect "unreachable" within about 45 seconds, and recovery by itself after
   reconnecting.

The two open questions from the plan are still open: whether the M1's Rex server keeps running
without Rex.app open, and whether `rex -S` works over its NetBird address.

## RPC: what it is here and what it is not

RPC is the language the app and daemon speak. It is not how the bytes travel. For the M1, the bytes
travel through an SSH tunnel on NetBird, and the RPC runs inside it.

| | This Mac (phases 0–5) | M1 (phase 6) |
|---|---|---|
| Daemon listens on | `127.0.0.1:7300` | `127.0.0.1:7300` on the M1 |
| App connects to | `127.0.0.1:7300` | a local port that an SSH tunnel carries to the M1 |
| API | identical | identical |

**RPC: gRPC with one `.proto` file** (`tonic` in Rust, `grpc-swift` in Swift). Confirmed working
in phase 0.

- It has streaming built in, which the live graphs need.
- The `.proto` file generates the data types for both languages, so they cannot drift apart.

**The daemon's API is read-only.** Any program on the machine can reach a `127.0.0.1` port, so the
API only reports numbers. Anything that changes a Rex session (close a pane, open a tab) stays a
Rex action, which is already access-controlled.

### API outline

| Call | Kind | Returns |
|---|---|---|
| `GetHost` | request/response | Host name, model, core layout, total memory, OS and daemon versions |
| `WatchSystem(interval)` | stream | CPU (total and per core), memory, swap, disks, network, battery |
| `GetHistory(window)` | request/response | Stored samples, to fill the charts when a window opens |
| `WatchProcesses(interval)` | stream | Processes grouped by app, with CPU and memory |
| `WatchSessions(interval)` | stream | Rex sessions → windows → panes, with CPU and memory for each |

## What was checked on this Mac

- **Rex reports the processes in each pane.** Calling the terminal's `process` method on this pane
  (Rex `0.1.0-preview.14`) returned the pane's root process, the foreground process and its
  ancestors, each with a process ID. Three details affect the design:
  - The pane's root process is `login`, owned by root. A daemon running as the user cannot read
    that one process's usage. I expect it can still list everything started under it, because
    parent process IDs are readable without root. That is not yet checked; it is the first check
    of phase 3.
  - Claude's process name is its version number (`2.1.328`). It must be recognised by `argv0`
    (`claude`) or by its path, not by name.
  - The foreground process comes with its working directory, so a session row can show the project.
- **Tools present:** Swift 6.3.3, Xcode 26.6, macOS 27.0.1, `grpcurl`, Rust 1.95 (`cargo` is in
  `~/.cargo/bin`), `protoc` 36.2.

## Assumed unless you object

1. **Daemon runs as your user, not root.** Consequence: it cannot read memory or CPU for processes
   owned by root. The totals stay exact, because they come from the kernel. The process list
   shows how many such processes there are, with no usage figure (see the phase 3 result).
2. **Memory per process is physical footprint,** the number Activity Monitor shows, not RSS. RSS
   can be sent as a second field if you want it.
3. **History:** the last hour at one sample per second, kept in memory. Nothing is written to disk.
4. **Update rate:** every second while the popover or dashboard is open. Every 5 seconds for the
   menu bar icon otherwise. The process list is only sampled while a window is showing it.
5. **Menu bar icon:** a small glyph plus CPU percentage.
6. **Names (confirmed):** project `computa`, daemon `computad`, app `Computa`, port `7300`.
7. **Not in this plan:** GPU, power draw, temperatures, per-process network usage, CI runners.

## Repository layout

```
computa/
├── proto/computa/v1/monitor.proto     the API contract, shared by both programs
├── daemon/                            Rust
│   ├── src/
│   │   ├── main.rs                    startup, config, logging, panic hook
│   │   ├── sampler/                   cpu.rs, memory.rs, disk.rs, network.rs, battery.rs,
│   │   │                              process.rs, grouping.rs
│   │   ├── history.rs                 one-hour ring buffer
│   │   ├── rex/                       client.rs (runs the rex CLI), sessions.rs (pane → processes)
│   │   └── rpc/                       server.rs, convert.rs
│   └── tests/                         starts the daemon and calls the API
├── app/                               Swift package
│   ├── Sources/ComputaCore/           RPC client, view models, formatting (testable, no UI)
│   ├── Sources/Computa/               Theme, MenuBar, Popover, Dashboard
│   └── Tests/ComputaCoreTests/
├── rex/computa.lua                    Rex actions (phase 5)
├── scripts/                           build-app.sh, install-daemon.sh
├── project-docs/                      this plan, later decisions
└── CLAUDE.md, .gitignore
```

The app is a Swift package, not an Xcode project, so it builds and tests from the command line.
`scripts/build-app.sh` wraps the binary into `Computa.app`.

## Phases

Estimates are my working time and are rough.

### Phase 0: RPC trial (about 45 minutes)

- You install Rust and `protoc` (commands below).
- `git init`, `.gitignore`, project `CLAUDE.md`.
- A daemon that streams one made-up number per second. A Swift command-line client that prints it.
- **Done when:** the Swift client prints 10 consecutive values from the Rust daemon, and
  `grpcurl -proto proto/computa/v1/monitor.proto` can call the service.
- **If it fails:** switch to JSON over WebSocket and note the reason in `project-docs/`.

### Phase 1: system metrics in the daemon (about 1.5 hours)

| Metric | Source |
|---|---|
| CPU total and per core; which cores are performance or efficiency | `host_processor_info`; core layout read at startup from `sysctl hw.perflevel*` |
| Memory used, wired, compressed, swap, pressure level | `host_statistics64`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` |
| Disk capacity and read/write rate | `statfs`, IOKit block storage statistics |
| Network rate per interface | `sysctl NET_RT_IFLIST2` (64-bit counters) |
| Battery and power adapter | IOKit power sources |

Uses the `sysinfo` crate where it gives the right number and direct system calls where it does not.

- **Done when,** compared over the same 10 seconds:
  - memory used is within 3% of Activity Monitor
  - CPU total is within 5 percentage points of `top`
  - disk used is within 1% of `df`
  - network rate is within 10% of a download of known size
  - the daemon itself averages under 1% CPU and under 30 MB of memory

### Phase 2: menu bar app and popover (about 1.5 hours)

- Menu bar item, popover with three rings (CPU, MEM, DISK), network up/down rates, battery,
  uptime, and an "Open Dashboard" button. Preferences and Quit along the bottom.
- The theme and glow, as described under "Look" below.
- A clear "daemon not running" state, and automatic reconnect.
- A **Prevent Sleep** toggle that keeps the Mac running the menu bar app awake. It is built into
  the app (a macOS power assertion), so it needs neither Rex nor the daemon, and it is released
  when the app quits. It starts off each time the app launches.
- **Done when:** the rings match the daemon's numbers to the percent, they update every second
  while open, and stopping then restarting the daemon recovers within 5 seconds with no relaunch.

### Phase 3: processes and the dashboard window (about 2 hours)

- First check: as the user, the daemon can list every process with its parent, including those
  under a root-owned `login`.
- Daemon: per-process CPU and memory, using `proc_pid_rusage`. Memory is `phys_footprint`, the
  number Activity Monitor shows. On Apple Silicon the CPU times need converting from Mach time
  units, a known trap.
- Grouping by app: a process belongs to the outermost `.app` in its path, otherwise to its parent's
  group. This gives rows like "Google Chrome +113".
- App: dashboard window with tabs CPU | Mem | Net | Disk, an hour-long bar chart, process search,
  and an expandable grouped list with app icons.
- **Done when:** for five processes you pick, memory is within 5% of Activity Monitor, and for
  three apps the "+N" count matches a `ps` count of processes whose path is inside that app.

### Phase 4: Rex sessions tab (about 1.5 hours)

- First check: `rex events --all --json` really delivers `process_changed` and pane added/removed
  events on this Mac. So far that is only known from the docs. If it does not, the map refreshes
  on a timer only.
- Daemon keeps a map of pane → root process ID. It refreshes the map from `rex events --all --json`
  (one long-running stream) plus a full refresh every 30 seconds. It does not call Rex every second.
- Every second, the daemon walks the process tree it already has and adds up CPU and memory for
  each pane, then each window, then each session.
- A pane running Claude is labelled as such, with its working directory.
- Under launchd there is no `REX_SERVER` variable and only a minimal `PATH`. The daemon's config
  file therefore stores the full path to `rex` and to the server socket, written by the install
  script.
- If Rex is not running, the tab says so and the other tabs keep working.
- **Done when:** this pane appears as a Claude session with the right working directory, its memory
  is within 5% of adding up `ps` for the same process tree by hand, and closing a pane removes its
  row within 2 seconds.
- Ends with `scripts/install-daemon.sh`, which installs the daemon as a login item (LaunchAgent).

### Phase 5: Rex actions from the dashboard (about 45 minutes)

This is the Lua part. Actions are defined in Rex's `init.lua`, run on the Rex server's machine, and
are called by the app with `rex do <action>`.

- `computa_open_top`: opens `btop` (or `top`) in a new Rex tab. A button in the dashboard.
- `computa_close_pane`: closes a pane from the Sessions tab, after a confirmation in the app.
- The actions live in `rex/computa.lua` in this repo. `just install-rex-actions` adds one line to
  your `init.lua` and shows it first. Then `rex config reload`.
- Prevent Sleep is not a Rex action. The owner asked for it on the client Mac only, so it moved
  into the app in phase 2.
- **Done when:** the close action removes the pane's row within 2 seconds, and the process viewer
  opens in a new tab.

### Phase 6: the M1 (about 1 hour of my time, plus setup on the M1)

Two checks come first, because the docs do not answer them:

1. Does the Rex server on the M1 keep running without Rex.app open?
2. Does `rex -S m1` work over SSH on the M1's NetBird address?

Then:

- Install the daemon on the M1 with the same script.
- The app starts and supervises the tunnel. Which command depends on what Rex offers by then:
  - If the installed Rex has `rex forward`: `rex -S m1 forward new -L <port>:127.0.0.1:7300`.
  - Otherwise plain SSH over NetBird: `ssh -N -L <port>:127.0.0.1:7300 you@<netbird-ip>`. It gives
    the same result and the same SSH login check, and works today.
- First check of this phase: gRPC streams correctly through the tunnel.
- Machine switcher in the popover and dashboard.
- The phase 5 actions installed in the M1's `init.lua`, called with `rex -S m1 do <action>`.
- App icons for remote processes: a new `GetAppIcon` call, since the app cannot read icons from
  another machine's disk.
- **Done when:** switching machines shows the M1's numbers within 2 seconds, and disconnecting
  NetBird shows "unreachable" and recovers without a relaunch.

## Look

Built from the three screenshots you sent. If they drop out of my context before the UI work, I
will ask for them again and not rebuild them from memory.

- **Popover:** laid out like your first screenshot, with our rows in place of the toggles.
- **Dashboard:** laid out like your second screenshot: segmented tabs, bar chart with pill-shaped
  axis labels, search field, grouped list.
- **Colours** (Whitby Bay, your third screenshot):

| Use | Colour |
|---|---|
| Window background | `#272A38` |
| Panels | `#20222E` |
| Selection, tracks | `#434861` |
| Text | `#F7F7EE` |
| Dim text | `#66759F` |
| CPU | green `#4DF08A` |
| Memory | purple `#B696F7`, lighter `#D0B0FB` |
| Disk | yellow `#F5F28A` |
| Network | cyan `#90ECF6` |
| Sessions | pink `#FF7ED1` |
| Warning | red `#FF5D57` |

- **Glow:** a soft shadow in the metric's own colour behind rings and chart bars.

## Testing

- **Rust unit tests:** rate calculations, time unit conversion, app grouping and process tree
  walking, all on fixed sample data.
- **Rust integration test:** starts the daemon on a free port and checks facts that must hold: CPU
  between 0 and 100, memory used not above total, per-core values consistent with the total.
- **Swift tests:** view models and number formatting.
- **Checks against Activity Monitor** are the "done when" lines above.

**Who runs the checks matters.** My commands run in a sandbox that hides other processes, blocks
the Rex socket and may refuse to open ports. A daemon started from my shell would report wrong or
empty numbers. So the daemon must be started by you (`! cargo run` in the prompt, or in another Rex
pane), and I will say so each time instead of reporting a sandboxed run as a pass. The same goes
for the app: my sandbox cannot launch apps, so you open `Computa.app`.

## How this fits your global CLAUDE.md

| Rule | What happens here |
|---|---|
| All new files in TypeScript | **Exception:** Rust daemon and Swift app, as you chose. Recorded in the project `CLAUDE.md`. |
| `tsconfig.json` | Not applicable. |
| `.gitignore`, project `CLAUDE.md` | Created in phase 0. |
| `.env`, `.env.example` | No secrets exist yet. Settings live in a config file. I will add the pair when the first secret appears. |
| `.dockerignore` | No Docker in this project. Skipped. |
| `src/`, `tests/` | Become `daemon/src`, `daemon/tests`, `app/Sources`, `app/Tests`. |
| Files under 300 lines, functions under 50 | Applies. The module layout above is split for this. |
| No swallowed errors | Applies. Errors are logged with context. A panic hook stands in for `unhandledRejection`. |
| Central database wrapper | Not applicable. No database. |
| No linter warnings | `cargo clippy` with warnings as errors; Swift builds without warnings. |

## Setting up another machine to build this

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
brew install protobuf
```
