# Rex server: platforms, installation, modes, remote access, upgrading, privacy

> **When to read this:** you are installing, running, exposing, upgrading, or auditing a Rex *server* (Linux, FreeBSD, Windows), or an app needs to reach one remotely.
> Covers platform availability, per-OS install, server modes, socket/config/log paths, remote-access listeners, upgrade procedure, Windows specifics, privacy, and the Community MCP.
> For CLI verbs, Lua config, or the Server API itself, read the other guides; this file is deployment only.

Caveat on sources: the install-command *tabs* (apt/dnf/pacman/etc. one-liners, Windows download links, Community MCP install snippet) are rendered client-side on the website and are **absent** from the docs. Where a command is not in the docs, this file says so rather than guessing.

---

## 1. Platform availability matrix (beta)

| Platform | Role | Availability | Notes |
| --- | --- | --- | --- |
| macOS | Client app (Rex for Mac) | All testers | Runs its own local server over a Unix socket; no network listeners/Tailscale by default |
| Linux | **Server only** | All testers | x86-64, ARM64 |
| FreeBSD | **Server only** | All testers | 14.0+, x86-64, ARM64 |
| iOS | Client app | Enrolled testers (Discord) | Updated via App Store/TestFlight |
| Windows | Client app + server | Enrolled testers (Discord) | 10 1809+, x86-64, ARM64 |
| Linux client | - | Exists, **not in testing yet** | - |

- Everything is "in testing". Install commands for Linux/FreeBSD/Windows are shown on the website only after logging in with Discord.
- Rex is "multiplexer server + CLI in one binary": `rex` is both server and CLI (`/usr/bin/rex`, `/usr/local/bin/rex`, `rex.exe`).

## 2. Channels (all platforms)

| Channel | Gets | Windows WinGet package |
| --- | --- | --- |
| `stable` | Tagged releases (**none right now**) | `Superlogical.RexServer` |
| `preview` | Tagged previews of next release | `Superlogical.RexServer.Preview` |
| `snapshot` | Frequent, likely-unstable builds | `Superlogical.RexServer.Snapshot` |

- Linux/FreeBSD install script defaults to `stable`; with no stable release it falls back to `preview` and says so.
- Windows install commands use `preview`; `winget install Superlogical.RexServer` fails until the first stable release (WinGet treats an empty channel as a nonexistent package).
- snapshot -> preview/stable = upgrade. preview/stable -> snapshot = **downgrade** (snapshot versions sort below releases) and must be requested explicitly (section 9).

---

## 3. Linux install

### Requirements

| Item | Supported |
| --- | --- |
| Arch | x86-64, ARM64 |
| libc | glibc >= 2.26 (Amazon Linux 2, Ubuntu 18.04, Debian 10, RHEL 8, or newer) or musl on Alpine >= 3.21 |
| Init | systemd, or OpenRC on Alpine (needed for shared/login servers; the `rex` command itself runs without either) |
| Packages | `.deb`, `.rpm` (Fedora, RHEL + rebuilds, openSUSE), `.pkg.tar.zst` (Arch + derivatives), `.apk` (Alpine), Nix |

Alpine package is the musl build, dynamically linked (Rex loads PAM at runtime, so not static). On other musl distros use `--tarball` (it picks the musl build on musl).

### Install script

`install.sh` adds the Rex repo to apt/dnf/zypper/pacman/apk and installs package `rex`; re-running upgrades. On NixOS/others without a repo it explains options and exits. Dry run: add `-s -- --dry-run` after `sh`.

| Option | Effect |
| --- | --- |
| `--channel NAME` | `stable` / `preview` / `snapshot` |
| `--tarball` | Binary only to `/usr/local/bin`; no services. glibc >= 2.26 or musl |
| `--dry-run` | Print every command without running |

```sh
# only command shown verbatim in the docs (binary only, no services):
curl -fsSL https://pkgs.superlogical.com/rex/install.sh | sh -s -- --tarball
# options always go after `sh -s --`
```

(The plain-install one-liner and per-distro tab commands are in the logged-in website tabs, not in the docs.)

### Quickstart (personal server over SSH)

```sh
# 1. install Rex (above)
# 2. start personal server at boot + keep running while logged out (no sudo; run as the connecting user). Skip on non-systemd (Alpine):
rex server install
# 3. verify SSH key login and that SSH finds rex:
ssh alice@build.example.com rex version
# 4. from the client:
rex -S ssh://alice@build.example.com ls
```
Mac app: **Add Remote Host...** -> `ssh://alice@build.example.com`. Without step 2, the server the first connection starts runs until machine restart.

### Package contents (Linux)

| Path / unit | What |
| --- | --- |
| `/usr/bin/rex` | Server + CLI |
| `rex.service` / `rex.socket` | Shared server / on-demand start. Not enabled |
| `rex-login-server.service` / `.socket` | Login server / on-demand start. Not enabled |
| `rex` user+group | Locked system account, home `/var/lib/rex` |
| `/etc/rex/accounts.jsonc` | Login-server accounts; ships **empty = admits nobody** |
| `/etc/pam.d/rex-login-server` | Login-server PAM policy (per distro) |
| `xterm-rex` terminfo | Rex terminal type |
| `/etc/ssh/ssh_config.d/50-rex.conf` | Falls back to `xterm-256color` on ssh from Rex to hosts lacking `xterm-rex` |
| Alpine: `/etc/init.d/rex`, `/etc/init.d/rex-login-server` | OpenRC scripts; your edits go in `/etc/conf.d/rex[-login-server]` (never shipped) |
| Arch: `/usr/lib/sysusers.d/rex.conf`, `/usr/lib/tmpfiles.d/rex.conf` | Create account / home |

Enable exactly one of the four units to run a server.

### SSH fallback vs OpenSSH version

| OpenSSH | Result |
| --- | --- |
| >= 8.7 | Sends `xterm-256color` to hosts without `xterm-rex` |
| 7.8-8.6 | Reads fallback but still sends `xterm-rex` (RHEL 8 = 8.0) |
| < 7.8 | ssh **rejects the config; every ssh command fails** (Amazon Linux 2 = 7.4, Ubuntu 18.04 = 7.6) |

`rex terminfo setup [--system]` checks the version; on ssh < 7.8 it installs terminfo only, skips fallback, exit status 1. Check config parses: `ssh -G example.com >/dev/null && echo ok`.

### Distro gotchas

| Distro | Gotcha |
| --- | --- |
| Debian/Ubuntu | Unrelated apt package also called `rex` ((R)?ex, Perl). Rex repo is pinned above it. If `rex -v` prints `(R)?ex`, run `apt-cache policy rex`, fix prefs, re-run script. Ubuntu 18.04: ssh_config has no `Include`; **do not add one** for `ssh_config.d` (breaks ssh for all accounts) |
| Fedora | Unrelated `Rex` package owns `/usr/bin/rex`: `sudo dnf remove Rex` first |
| Amazon Linux 2 | EOL 2026-06-30; script installs **binary only** to `/usr/local/bin` (like `--tarball`), no services/login server. Use `rex server start` for a personal server. Update = re-run script. AL2023 uses the repo like Fedora |
| Arch (+ `ID_LIKE=arch`: Manjaro, EndeavourOS, CachyOS, Garuda) | Install runs `pacman -Syu` (script adds `--needed`). SteamOS unsupported (read-only root). Repo lists newest version only; older: `sudo pacman -U https://pkgs.superlogical.com/rex/arch/snapshot/x86_64/rex-VERSION-1-x86_64.pkg.tar.zst`. AUR `rex-bin` conflicts: `sudo pacman -R rex-bin` first and `sudo systemctl disable --now rex.service rex.socket rex-login-server.service rex-login-server.socket` |
| Omarchy | `pacman -Syu` is blocked; script handles it. Manual: run Arch steps without `sudo pacman -Syu rex`, then `omarchy update` + `sudo pacman -S --needed rex`. `omarchy refresh pacman` / `omarchy channel set` drop the Rex repo (re-run script) |
| Alpine | No sudo (run as root); OpenRC; `apk add openrc` in containers; on musl `who`/`last` don't list Rex sessions (`lastlog` ok) |
| Nix/NixOS | See below |

Channel switch (edit channel name in repo file, then refresh): apt `Suites:` in `/etc/apt/sources.list.d/rex.sources`; dnf/zypper `name`+`baseurl` in `/etc/yum.repos.d/rex.repo`; pacman `Server` in `/etc/pacman.d/rex.conf`; Alpine `/etc/apk/repositories.d/rex.list` (script) or Rex line in `/etc/apk/repositories` (manual), then `apk update`.

### systemd -> Alpine OpenRC translation

| systemd | Alpine |
| --- | --- |
| `sudo systemctl enable --now rex.service` | `rc-update add rex` then `rc-service rex start` |
| `sudo systemctl enable --now rex-login-server.service` | `rc-update add rex-login-server` then `rc-service rex-login-server start` |
| `sudo systemctl reload rex-login-server.service` | `rc-service rex-login-server reload` |
| `sudo systemctl disable --now rex.service` | `rc-service rex stop` then `rc-update del rex` |
| `sudo systemctl edit rex.service` | set `command_args` in `/etc/conf.d/rex` |
| `journalctl -u rex.service -f` | `tail -f /var/log/rex/server.log` |
| `journalctl -u rex-login-server.service` | `cat /var/log/rex-login-server.log` |
| `sudo usermod --append --groups rex alice` | `addgroup alice rex` |

No socket activation on Alpine (use services). `/etc/conf.d/rex` is a shell script read by OpenRC; `command_args` there **replaces** the server command line (omit `/usr/bin/rex`).

### Nix / NixOS

- Flake per channel: `https://pkgs.superlogical.com/rex/nix/<channel>.tar.gz` (release binary, x86-64 + ARM64 Linux). Older Nix: `nix profile install` = `nix profile add`.
- Try: `nix run https://pkgs.superlogical.com/rex/nix/snapshot.tar.gz -- --help`. `flake.lock` pins exact release; update with `nix flake update rex`.
- **NixOS module** `rex.nixosModules.default` (two modes, cannot both be on):

| Option | Effect |
| --- | --- |
| `services.rex.enable` | Shared server as `rex`, socket `/run/rex/server.sock`; `rex` group may connect |
| `services.rex.loginServer.enable` | Root login server -> per-account servers; `/run/rex/login-server.sock` |
| `services.rex.socketActivation`, `services.rex.loginServer.socketActivation` | Start on first connect (needs mode `enable`; shared one needs a Unix `socketPath`). Module's services *require* their sockets (stopping socket stops server) |
| `services.rex.loginServer.accounts.<name>.principals`, `.defaults`, `.accountsFile` | Writes `/etc/rex/accounts.jsonc` (doesn't create users; use `users.users`). `accountsFile` preserves `defaults` order |
| `services.rex.tailscale.enable` (+`hostname`,`authKeyFile`,`advertiseTags`) | Built-in Tailscale |
| `services.rex.tailscaleServe.enable`, `services.rex.loginServer.tailscaleServe.enable` | Tailscale Serve (host needs Tailscale logged in, tailnet HTTPS on) |
| `services.rex.allowAnonymous` (+`openFirewall`,`port`), `services.rex.loginServer.allowAnonymous` | Plain HTTP |

Either mode installs `rex` for all users, terminfo, and SSH fallback in `/etc/ssh/ssh_config`. Toggling options restarts running server at next `nixos-rebuild switch` (ends shared sessions). Minimal:

```nix
{ inputs.rex.url = "https://pkgs.superlogical.com/rex/nix/snapshot.tar.gz";
  # modules = [ rex.nixosModules.default { services.rex.enable = true;
  #   users.users.alice = { isNormalUser = true; extraGroups = [ "rex" ]; }; } ];
}
```
```nix
services.rex.loginServer = { enable = true;
  accounts.alice.principals = [ "tailscale:alice@example.com" ];
  tailscaleServe.enable = true; };
```

- **home-manager module** `rex.homeManagerModules.default` (alias `rex.homeModules.default`); any Linux with Nix+systemd:

| Option | Effect |
| --- | --- |
| `programs.rex.enable` | Installs rex, `xterm-rex` to `~/.terminfo`, SSH fallback in `~/.ssh/config` (needs `programs.ssh.enable = true`); `programs.rex.config` writes `~/.config/rex/init.lua`; `programs.rex.sshGuard = false` for ssh < 7.8 |
| `services.rex.enable` | Personal server as systemd **user** service `rex` (log: `journalctl --user -u rex`; restart: `systemctl --user start rex`) |
| `services.rex.tailscale.enable` | Built-in Tailscale (`authKeyFile` needs systemd >= 250). Other opts (`extraListen`, `blockDirs`, `maxSessions`) in `home-manager-module.nix` |

Starts at login/stops at logout (ends sessions); run `loginctl enable-linger` once to run at boot. On macOS enable only `programs.rex` (`services.rex` errors). Shared/login servers need root: use NixOS module or packages.

---

## 4. FreeBSD install

| Item | Value |
| --- | --- |
| Release / arch | FreeBSD >= 14.0 (one package covers 14+), x86-64, ARM64 |
| Deps | None (base system only) |
| Services | rc.d (shared + login). `rex` itself runs without them |
| Package | `.pkg` from Rex repo; `pkg upgrade` updates it |

- Install script takes the same options as Linux (`--channel`, `--tarball`, `--dry-run`; after `sh -s --`). No `sudo`/`curl` by default: run as root; downloads use `fetch`. The pkg tab begins `umask 022` (make files world-readable regardless of root's umask). If a channel has no FreeBSD package yet, the script installs binary only to `/usr/local/bin` with no services; re-run later to switch to the package.
- pkg trusts the repo by key fingerprint at `/usr/local/etc/pkg/fingerprints/rex`; re-run the script if the key changes.
- Channel switch: edit channel in `url` line of `/usr/local/etc/pkg/repos/rex.conf`, then `pkg update -r rex`.
- Quickstart: install, `ssh alice@build.example.com rex version`, `rex -S ssh://alice@build.example.com ls`. The first connection starts the personal server; it keeps running after logout until stopped or reboot.
- `pkg info -D rex` re-shows setup notes.

### Package contents

| Path | What |
| --- | --- |
| `/usr/local/bin/rex` | Server + CLI |
| `/usr/local/etc/rc.d/rex` | Shared server (not enabled) |
| `/usr/local/etc/rc.d/rex-login-server` | Login server (not enabled) |
| `rex` user+group | Locked; **uid/gid 729** or next free; home `/var/db/rex` |
| `/usr/local/etc/rex/accounts.jsonc` | Login accounts (ships empty) |
| `/usr/local/etc/pam.d/rex-login-server` | PAM policy (**replaced on every upgrade**) |
| `xterm-rex` | Terminfo in `/usr/local/share/terminfo` |

No SSH-fallback file (FreeBSD `ssh_config` reads no other files). Run as root `rex terminfo setup --system` (adds a marked `Include` to `/etc/ssh/ssh_config`; undo `rex terminfo remove --system`) or `rex terminfo setup` for your account only.

### systemd -> FreeBSD translation

| systemd | FreeBSD |
| --- | --- |
| `systemctl enable --now rex.service` | `sysrc rex_enable=YES` then `service rex start` |
| `systemctl enable --now rex-login-server.service` | `sysrc rex_login_server_enable=YES` then `service rex-login-server start` |
| `systemctl reload rex-login-server.service` | `service rex-login-server reload` |
| `systemctl restart rex.service` | `service rex restart` |
| `systemctl disable --now rex.service` | `service rex stop` then `sysrc rex_enable=NO` |
| `systemctl edit rex.service` | `sysrc rex_flags=...` (see below) |
| `journalctl -u rex.service` | `grep ' rex\[' /var/log/messages` |
| `journalctl -u rex-login-server.service` | `grep ' rex-login-server\[' /var/log/messages` |
| `usermod --append --groups rex alice` | `pw groupmod rex -m alice` |
| `usermod --shell /bin/bash rex` | `pw usermod rex -s /bin/sh` |

| Linux path | FreeBSD path |
| --- | --- |
| `/usr/bin/rex` | `/usr/local/bin/rex` |
| `/run/rex` | `/var/run/rex` |
| `/var/lib/rex` | `/var/db/rex` |
| `/etc/rex/accounts.jsonc` | `/usr/local/etc/rex/accounts.jsonc` |
| `/etc/pam.d/rex-login-server` | `/usr/local/etc/pam.d/rex-login-server` |
| `/etc/nologin` | `/var/run/nologin` |
| `/run/user/<uid>/rex` | `~/.local/state/rex/run` |

No socket activation. Services log to syslog (`/var/log/messages`); per-account servers under the login server log to `/var/run/rex/accounts/<account>/server.log`. A service restarts a dead server after 5 s; only `service rex stop` stops it for good. `service rex start` can return a moment before the server accepts connections.

### rc.conf settings (set with `sysrc`, then restart; upgrades never touch `/etc/rc.conf`)

| Setting | Default | Effect |
| --- | --- | --- |
| `rex_flags` | none | Extra options for `rex server run` (**appended**, unlike systemd `ExecStart` which replaces; omit the four built-in options) |
| `rex_umask` | `0007` | Mask for server + children |
| `rex_user` / `rex_group` | `rex` / `rex` | Account running the server / group that may use the socket |
| `rex_runtime_dir` | `/var/run/rex` | Socket directory |
| `rex_state_dir` | `/var/db/rex` | Server data |
| `rex_login_server_flags` | none | Extra options for `rex login-server` |
| `rex_login_server_accounts` | `/usr/local/etc/rex/accounts.jsonc` | Accounts file |
| `rex_login_server_runtime_dir` | `/var/run/rex` | Login socket + account server dirs |

```sh
sysrc rex_flags="--max-sessions 128" && service rex restart
sysrc rex_user=alice rex_group=alice && service rex restart   # run shared server as alice; service chowns old dirs; sessions persist
```

---

## 5. Server modes (Linux + FreeBSD)

| | Personal | Shared | Login |
| --- | --- | --- | --- |
| For | Just you | A few people who trust each other with one account | Several people, each as themselves |
| Runs as | Your account | `rex` system account | root, then hands off to a server per person's account |
| Started by | Any `rex` command, or `rex server start` | `rex.service`, or `rex.socket` on demand | `rex-login-server.service`, or `rex-login-server.socket` on demand |
| Default socket | `$XDG_RUNTIME_DIR/rex` (usually `/run/user/<uid>/rex`; FreeBSD & container fallback `~/.local/state/rex/run`; override `REX_RUNTIME_DIR`) | `/run/rex/server.sock` (FreeBSD `/var/run/rex/server.sock`) | `/run/rex/login-server.sock` (root only) |
| State/data | `~/.local/state/rex` (or `$XDG_STATE_HOME/rex`) | `/var/lib/rex` (FreeBSD `/var/db/rex`) | each account's own |
| Config | `~/.config/rex/init.lua` | `/var/lib/rex/.config/rex/init.lua` (FreeBSD `/var/db/rex/.config/rex/init.lua`) | each account's own |
| Auth | OS account | Membership in `rex` group (socket mode 0660) | Caller identity (Tailscale login, local uid, ...) vs `accounts.jsonc`; no passwords/keys |
| Sessions on package upgrade | Survive | **End** | Survive (account servers keep old version until sessions end) |
| Socket activation | n/a | systemd only | systemd only |

Rules:
- Shared and login **cannot run together** (both use `/run/rex`; starting one stops both units of the other; on Alpine/FreeBSD each refuses to start while the other runs). Personal servers coexist with either. Under login mode, your personal server *is* the server the login server connects you to (with systemd-logind), so local and remote see the same sessions.
- Every mode listens **only on local Unix sockets** by default. Network access: section 7.
- Windows has only personal servers (section 8).

### Personal server

```sh
rex ls                       # auto-starts a server if none; auto-started one exits ~10 s after last session AND last connection close
rex server start             # persistent; no-op if one is running (options like --max-sessions apply only to a NEW server)
rex server status
rex server logs --follow     # only for servers started by `rex server start`
rex server stop              # ends every session
rex -S PATH server start     # own server at another socket path (you need write access to its dir)
```
- `rex` auto-starts only for sockets in its runtime dir (or `REX_RUNTIME_DIR`); with any other `-S` it starts nothing and says how.
- `REX_AUTOSTART=0` disables autostart (also over SSH).
- Linux: personal server's socket goes away at logout and **kills running sessions** unless `loginctl enable-linger` (or `rex server install`).

### Shared server

Access to it **is** access to `rex` account: members can see/type into every session; every program runs as `rex`. Not sandboxed on purpose (the `rex` account is the boundary).

```sh
sudo usermod --shell /bin/bash rex          # REQUIRED: shipped shell is nologin; terminals exit immediately otherwise
#   Alpine: apk add shadow; usermod --shell /bin/sh rex     FreeBSD: pw usermod rex -s /bin/sh
sudo usermod --append --groups rex alice    # applies on next login
sudo systemctl enable --now rex.service     # or rex.socket (not both)
```
Account stays locked (no password).

Using it (others' `rex` default to their own personal server):
```sh
rex -S /run/rex/server.sock ls
export REX_SERVER=/run/rex/server.sock      # FreeBSD: /var/run/rex/server.sock; inside the shared server's own terminals it's already the default
```
`rex` never auto-starts a personal server at the shared socket. Non-members get a permission error. Reload config: `sudo $EDITOR /var/lib/rex/.config/rex/init.lua && rex -S /run/rex/server.sock config reload` (any group member can reload; only root can edit).

Socket activation (`rex.socket`): systemd creates `/run/rex/server.sock`; first connection (including `rex server status`) starts `rex.service` with same command line; **server then keeps running** (controls start time, not lifetime). Check without starting: `systemctl status rex.service rex.socket` (socket shows "active (listening)").
```sh
sudo systemctl stop rex.socket rex.service         # stop AND keep stopped (stopping service alone lasts until next connect; stopping only socket leaves unreachable server; don't use `rex server stop`)
sudo systemctl disable --now rex.socket rex.service && sudo systemctl enable --now rex.service   # to always-on (ends sessions)
sudo systemctl disable --now rex.service && sudo systemctl enable --now rex.socket               # back (stop service first)
```

Customizing (upgrades replace units; use drop-ins). Keep all four original options; `ExecStart=` blank line clears first:
```ini
# sudo systemctl edit rex.service
[Service]
ExecStart=
ExecStart=/usr/bin/rex server run --listen /run/rex/server.sock \
  --state-dir /var/lib/rex --socket-mode 0660 --log-format text \
  --max-sessions 128
```
Alpine: `command_args="server run --listen ... --max-sessions 128"` in `/etc/conf.d/rex`. FreeBSD: `rex_flags`. Other flags: `--block-dir` (block plugin dir), `--config PATH`, `--log-format json|text`, `--extra-listen`. Full list: `rex server run --help`.

Customizing the socket (`sudo systemctl edit rex.socket`): every `ListenStream=` needs a matching `--listen`/`--extra-listen` in the service, else server refuses to start and clients hang to `--timeout` (default 10 s). Move socket: stop both units first, set
```ini
[Socket]
ListenStream=
ListenStream=/run/rex/rex.sock
```
and same path in `ExecStart --listen`; `sudo systemctl start rex.socket`; clients `rex -S /run/rex/rex.sock`. Server keeps the socket unit's `SocketMode=` and ignores `--socket-mode`; refuses modes letting all users connect (e.g. `0666`); use `0660` or narrower (`0600` locks out the group). Only stream sockets; no `Accept=yes`; TCP `ListenStream=` needs matching `--extra-listen` + `--allow-anonymous` and an IP (not hostname). Apply later socket changes by stop-both/start-socket (`restart rex.socket` fails while server runs).

Logs: `journalctl -u rex.service -f` (Alpine `/var/log/rex/server.log`; FreeBSD syslog). Text by default; `--log-format json`. `rex server logs` does **not** show service-run servers.

### Login server

Root service. On connect: identify caller -> look up `/etc/rex/accounts.jsonc` -> pick account -> open PAM login session -> start (or reuse) a Rex server as that account -> hand over connection. Account servers survive login-server stop/restart/upgrade.

```sh
sudo $EDITOR /etc/rex/accounts.jsonc               # FreeBSD: /usr/local/etc/rex/accounts.jsonc
sudo systemctl enable --now rex-login-server.service   # or .socket for on-demand
sudo systemctl reload rex-login-server.service     # after edits; keeps still-allowed connections, closes revoked ones, accounts' servers untouched
journalctl -u rex-login-server.service             # "account policy reloaded" / "account policy reload failed; previous policy retained"
```

**No passwords or keys**; identity is only by how you connect (Tailscale login, local uid). A full auth system (incl. SSH keys) is planned; use Tailscale until then.

`accounts.jsonc` (JSON with comments + trailing commas):
```jsonc
{
  "version": 1,
  "accounts": {
    "alice": { "principals": ["tailscale:alice@example.com"] },
    "root":  { "principals": ["tailscale:alice@example.com"] },
  },
  "defaults": { "tailscale:alice@example.com": "alice" },
}
```

| Principal | Matches |
| --- | --- |
| `tailscale:alice@example.com` | A person (Tailscale login) |
| `tailscale:tag:ci` | Device with that tag |
| `tailscale:*` | Any person on tailnet |
| `tailscale:tag:*` | Any tagged device |
| `peer:1000` | Local user by uid |
| `identified` | Any identifiable caller |
| `anonymous` | Unidentifiable callers (e.g. plain TCP listener) |

- Tagged devices never match a person login or `tailscale:*`.
- Special account `"*"`: callers may use any regular account (uid >= 1000) whether listed or not; root and system accounts must be named. `anonymous` can't be under `"*"`; anonymous callers can **never** use root.
- `defaults` only picks; caller must still be allowed. Ties: most specific wins (login/uid > tag > Tailscale wildcard > `identified` > `anonymous`), then first in file. No matching default: a caller with exactly one allowed account gets it; else client must name one.
- Choose account in the address (only `https://`/`http://`, so a network listener is required): `rex -S root@build.example.ts.net ls`, `https://root@build.example.ts.net` in Add Remote Host.

On-demand (`rex-login-server.socket`): same semantics as shared; only root can use the socket; before first connect `reload` fails (nothing to do: file is read at start). Bad/missing accounts file -> server exits with `loading accounts file:`..., retried after 5 s; clients wait to `--timeout`. Stop-and-keep-stopped: `sudo systemctl stop rex-login-server.socket rex-login-server.service`. Socket customization = same as shared; Tailscale-Serve start-on-request see section 7.

PAM: used each time an account server starts (locked/expired accounts, rlimits, env, systemd-logind session). No password prompts. While `/etc/nologin` exists only root may log in; shells `nologin`/`false` always refused. Skip PAM with `--pam=false` (Rex then checks `/etc/shadow` + `/etc/nologin`): systemd drop-in on the service; Alpine `command_args="login-server --listen unix:///run/rex/login-server.sock --accounts /etc/rex/accounts.jsonc --runtime-root /run/rex --log-format text --pam-service rex-login-server --pam=false"`; FreeBSD `sysrc rex_login_server_flags="--pam=false"` (checks `/etc/master.passwd` + `/var/run/nologin`).

FreeBSD PAM: copy to `/etc/pam.d` (OpenPAM reads it first; must be root-owned) and edit there:
```sh
install -o root -g wheel -m 0644 /usr/local/etc/pam.d/rex-login-server /etc/pam.d/rex-login-server
```
Policy mirrors sshd (`pw lock` refused, `/etc/login.access`, `/var/run/nologin`); `/etc/login.conf` classes applied (rlimits).

### Switching between shared and login

```sh
# systemd
sudo systemctl disable --now rex.service rex.socket
sudo systemctl enable --now rex-login-server.service     # or .socket
# Alpine: rc-service rex stop; rc-update del rex; rc-update add rex-login-server; rc-service rex-login-server start
# FreeBSD: service rex stop; sysrc rex_enable=NO; sysrc rex_login_server_enable=YES; service rex-login-server start
```
Shared -> login ends all shared sessions. Login -> shared leaves account servers running; with no systemd-logind (Alpine, FreeBSD) or `--pam=false`, their sockets live in `/run/rex/accounts` and `rex.service`/`rex.socket` refuse to start while it exists (FreeBSD: only while `/var/run/rex/accounts` holds a socket). Once not needed: `sudo rm -rf /run/rex` (FreeBSD `/var/run/rex`) then `sudo systemctl start rex.service` (or `rex.socket`; Alpine `rc-service rex start`; FreeBSD `service rex start`). A refused start can still stop login units; restart them if backing out.

---

## 6. Environment variables seen in these docs

| Var | Meaning |
| --- | --- |
| `REX_SERVER` | Default server address/socket for every `rex` command (same as `-S`/`--server`) |
| `REX_AUTOSTART=0` | Never auto-start a server (also over SSH) |
| `REX_RUNTIME_DIR` | Override socket/runtime dir for personal server (on Windows suffixes pipe name) |
| `XDG_RUNTIME_DIR`, `XDG_STATE_HOME` | Locate socket / state |

---

## 7. Remote access

Linux/FreeBSD servers listen on local Unix sockets only; Windows on a named pipe only the account owner can open. Rex trusts a caller solely by how they connect (no keys/passwords yet), hence cautious defaults. **A connection can do anything the server can (start programs as its account).** Recommended path: SSH.

| Listener | Needs | Works with | Identifies callers |
| --- | --- | --- | --- |
| SSH | SSH access to machine | Personal, shared | Yes |
| Built-in Tailscale | Tailscale account | Personal, shared | Yes |
| Tailscale Serve | Tailscale on machine | Shared, login | Yes |
| Tailnet address | Tailscale on machine | Shared, login | Yes |
| Plain HTTP | `--allow-anonymous` | Every mode | No |
| Another VPN | `--allow-anonymous` | Every mode | No |

### Address forms / adding hosts

```sh
rex -S ssh://alice@build.example.com ls
rex hosts add build ssh://alice@build.example.com
rex -S https://build.example.ts.net ls
rex hosts add build https://build.example.ts.net && rex -S build ls
rex -S http://10.0.0.5:7297 ls
```
- SSH form: `ssh://[USER@]HOST[:PORT][/SOCKET]`. Without `/SOCKET` it finds (or starts) that SSH user's personal server. Uses your system `ssh` (your keys/agents/config). `rex` must be on PATH for SSH sessions, or in `~/.local/bin` (checked explicitly).
- Bare hostname tries `https` :443, then `https` :7297, then `http` :7297.
- `https://USER@host` selects a login-server account.
- Mac app: **Add Remote Host...**. **`rex hosts` is CLI-only today** (doesn't sync to GUI client or other machines).
- `rex client ls` on a server lists connected clients; `principal` column shows identity.

### SSH

Nothing listens on the network but sshd. Linux personal server dies at logout without linger: `loginctl enable-linger`.

### Built-in Tailscale (`--tailscale`)

Server joins tailnet as its own device (no Tailscale install needed).
```sh
rex server start --tailscale
```
- First run needs sign-in: link in `rex server status` and server log. Headless: `--tailscale-auth-key-file FILE` (or `-` = stdin; needed once, login persisted).
- Device name `rex` unless `--tailscale-hostname`; address `https://rex.<tailnet>.ts.net`. Tailnet needs MagicDNS + HTTPS certs.
- Tagged device: `--tailscale-advertise-tag tag:NAME` **plus** `--tailscale-allow-tailnet-members` (tagged = no owner).

### Tailscale Serve (shared + login servers)

Drop-in (`sudo systemctl edit rex.service`) adds a `tailnet-serve://` listener:
```ini
[Unit]
After=tailscaled.service
Requires=tailscaled.service

[Service]
ExecStart=
ExecStart=/usr/bin/rex server run --listen /run/rex/server.sock \
  --state-dir /var/lib/rex --socket-mode 0660 --log-format text \
  --extra-listen tailnet-serve:///run/rex/serve.sock
```
Login server `ExecStart`:
```ini
ExecStart=/usr/bin/rex login-server --listen unix:///run/rex/login-server.sock \
  --accounts /etc/rex/accounts.jsonc --runtime-root /run/rex --log-format text \
  --pam-service rex-login-server --extra-listen tailnet-serve:///run/rex/serve.sock
```
Then: `sudo tailscale serve --bg --https=443 unix:/run/rex/serve.sock` (FreeBSD `unix:/var/run/rex/serve.sock`; address `https://build.<tailnet>.ts.net`).
- Alpine: same `command_args` (no `/usr/bin/rex`) + `rc_need="tailscale"` in `/etc/conf.d/rex[-login-server]`. FreeBSD: `sysrc rex_flags="--extra-listen tailnet-serve:///var/run/rex/serve.sock"; service rex restart`.
- **Use `tailnet-serve://`, never `unix://`, for the Serve socket**: `unix://` starts silently but treats every tailnet caller as the tailscaled account (usually root).
- Serve doesn't identify tagged devices -> CI runners can't connect this way; use a tailnet address.
- Socket-activated: also add `[Socket] ListenStream=/run/rex/serve.sock` via `systemctl edit rex.socket` (or `rex-login-server.socket`), keep `--extra-listen` in the service, then `sudo systemctl stop rex.socket rex.service && sudo systemctl start rex.socket`. Otherwise a Serve request can't start the server.

### Tailnet address

Add `--extra-listen tailnet://:7297` (port required). Plain HTTP encrypted by Tailscale at `http://build.<tailnet>.ts.net:7297`; uses machine's own Tailscale to identify callers.

### Who can connect

Personal/shared: by default only the Tailscale owner of the machine (or the Rex device for built-in Tailscale). To widen:

| Listener | Option | Lets in |
| --- | --- | --- |
| Built-in Tailscale | `--tailscale-allow-tailnet-members` | Anyone on tailnet your ACLs allow |
| Serve / tailnet address | `--tailnet-allow-identified` | Anyone Tailscale can identify |

Tagged machines need one of these. Login server admits everyone Tailscale can identify; its accounts file decides accounts.

### Plain HTTP and other VPNs

```sh
rex server start --extra-listen :7297 --allow-anonymous
rex server start --extra-listen http://10.0.0.5:7297 --allow-anonymous    # WireGuard/ZeroTier/NetBird etc.
```
- Rex refuses a plain HTTP listener without `--allow-anonymous`. **Every connection then has full access**; only on networks you fully control. Login server: anonymous callers get only accounts with `anonymous` principal, never root.
- Use the VPN IP; `:7297` with no host binds all interfaces.
- A server that can't bind an address doesn't start at all (not even its Unix socket) so put these flags on the service command line (not `rex server start`, which doesn't persist or alter running server). systemd/FreeBSD retry every 5 s.
- Some devices run one VPN at a time: enabling Tailscale can disconnect Rex.
- Default port convention in examples: **7297**.

---

## 8. Windows

Rex Windows (server + app) is for enrolled testers. **Every server is a personal server running as your account**; Server Modes / Shared / Login pages do not apply.

### Install

| Item | Value |
| --- | --- |
| Release/arch | Windows 10 1809+; x86-64, ARM64 |
| Packages | WinGet (recommended), MSI (x86-64 download; ARM64 uses WinGet(MSI) or zip), Zip |
| Signing | **Unsigned** during testing: expect "unknown publisher" warnings |

All installs put `rex.exe` on PATH but **do not start a server or install a Service**; do `rex server install` yourself. New terminal required for PATH. Adding the WinGet source needs **Run as administrator** (WinGet source name: `rex`; exact add-source command is in the website tab, not the docs).

```powershell
msiexec /i rex-windows-amd64.msi /qn          # silent MSI (admin); add INSTALLDIR="D:\Tools\Rex Server" to relocate
winget uninstall --id Superlogical.RexServer.Preview --source rex
```

| Package | Location | PATH |
| --- | --- | --- |
| WinGet | `%LocalAppData%\Microsoft\WinGet\Packages\Superlogical.RexServer.Preview_*` | user |
| MSI | `%ProgramFiles%\Rex Server` (all accounts) | system |
| Zip | where you extract | you add it (user PATH) |

Files: `rex.exe`, `OpenConsole.exe` (Windows Terminal console host), `LICENSE-OpenConsole.txt`.

Remove: `rex server uninstall` (admin if a Service exists) **before** removing the package (else Service points at a missing exe) -> `rex server stop` -> `winget uninstall ...` (zip: normal, non-admin terminal) / MSI via Add or Remove Programs / zip delete folder + remove from PATH. Config `%AppData%\rex\init.lua` and state/logs `%LocalAppData%\rex` remain (delete for full removal). To switch channels: remove, then install the other with `--source rex`.

### Quickstart (SSH from a Mac)

```powershell
# admin terminal
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service sshd -StartupType Automatic
Start-Service sshd
# admin account keys live here (and must be admin/SYSTEM-only):
Add-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAA... alice@mac"
icacls.exe C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant Administrators:F /grant SYSTEM:F
# standard account: ~\.ssh\authorized_keys
```
Then on Mac: `rex -S ssh://alice@pc ls`. SSH firewall rule allows **Private** networks only.

### Server lifetimes

| Started by | Starts | Keeps running | Admin? |
| --- | --- | --- | --- |
| Any `rex` command | when run | until ~10 s after last client | No |
| `ssh://` connection | on connect | until stopped | No |
| `rex server start` | now | until stopped or sign out | No |
| `rex server install --user` | each sign-in | until sign out | No |
| `rex server install` | at boot, as Windows Service | until shutdown, signed in or not | Yes |

Guidance: local-only use -> let `rex` autostart; remote use -> `rex server install`; no admin -> `--user`. `REX_AUTOSTART=0` disables autostart.

### Windows Service (`rex server install`, admin terminal)

- Creates service `RexServer-<SID>` ("Rex Server (PC\alice)"), **Automatic (Delayed Start)**, runs `"<path>\rex.exe" server run <flags>`, **as your account (not LocalSystem)**. Also: grants "log on as a service", registers Event Log source "Rex Server", deletes any sign-in entry.
- If an idle server is running it's replaced by the service; if it has sessions/clients it keeps running and the service starts next boot.
- Idempotent; keeps flags; re-run after moving `rex.exe` (e.g. WinGet zip <-> MSI).
- `sc.exe start|stop RexServer-<SID>` (admin). Stop gives server 15 s to save sessions. While service is stopped, a `rex` command may start its own server and `sc.exe start` then fails (set `REX_AUTOSTART=0`).
- `rex server uninstall`: stops+deletes service (ends all programs), unregisters Event Log source (unless another account's service uses it), deletes sign-in entry. Needs admin once a Service exists. "Log on as a service" right remains (remove in `secpol.msc` > Local Policies > User Rights Assignment).
- Sign-in mode `rex server install --user`: registry value "Rex Server" in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` running `rex server start <flags>`; also starts a server now; can't coexist with the Service (fails while a Service exists); respects disabling in Task Manager/Settings > Apps > Startup.

### Server flags (persist across restarts)

Put after `--`:
```powershell
rex server install -- --tailscale
rex server install --user -- --extra-listen tailnet://:7297
```
| Command | Flags |
| --- | --- |
| `rex server install` | keeps existing |
| `rex server install -- --tailscale` | replaces |
| `rex server install --` | removes |

Refused flags: `--listen` (CLI finds the server by its named pipe; use `--extra-listen`), `--exit-empty` (Service would stop when idle and not restart till boot), `--tailscale-auth-key-file -` (no stdin; use a file path). Running servers keep old flags until restarted; `rex server start` doesn't read the sign-in entry (stop + `rex server install --user`, or sign in again). `rex server tailscale on` and runtime changes last only until server stops.

### Runtime facts

| Topic | Fact |
| --- | --- |
| Endpoint | Named pipe `\\.\pipe\rex-<SID>` (suffix added when `REX_RUNTIME_DIR` set); only your account can open it |
| Admin rights | Servers started by the Service, `rex server start`, or any `rex` command run with a **reduced token (no admin)** even from an elevated terminal; startup fails if the reduced token can't be made. Exception: `rex server run` in an elevated terminal keeps full admin |
| Logs | `rex server logs [--follow]` (works for the Service too); files in `%LocalAppData%\rex\servers`, truncated before 50 MiB |
| Event Viewer | Application log, source "Rex Server": 1 starting, 2 running, 3 stop requested, 4 stopped (all Info); 5 stopped with error (Error) |
| Default shell | First of `pwsh.exe`, `powershell.exe` on server PATH, else `%ComSpec%`; no setting. Other shell: `rex new -- cmd.exe` |
| Terminal env | `TERM=xterm-256color`; `rex terminfo setup` refused. Closing a terminal ends all its processes |
| Env allowlist | Servers from `rex`/`start`/sign-in pass only: usual Windows vars (`USERPROFILE`, `APPDATA`, `ProgramFiles`...), toolchain vars (`JAVA_HOME`, `GOPATH`...), `PATH`, `REX_*`, `XDG_*`, `LC_*`, proxy vars. Extra: `rex server start --env NAME --env OTHER=value` (new server only; persist via `rex server install --user -- --env NAME`). Service gets system+user env at service start and **refuses `--env`** |
| Stop/restart | `rex server stop` ends all programs; layouts saved and `rex ls` lists them after restart, but programs don't come back |

### Not available on Windows

| Feature | Windows alternative |
| --- | --- |
| Shared/login servers | Each account runs its own |
| Socket activation | Any `rex` command starts server |
| `--socket-mode` | Pipe is owner-only |
| `tailnet-serve://`, `login-server://` listeners | Built-in Tailscale: `rex server install -- --tailscale` |
| `tailnet://` with userspace `tailscaled` | `tailscaled` with its normal network adapter |
| `rex terminfo setup` | `TERM=xterm-256color` |
| `rex server install ssh://` to a Windows PC | Install Rex on PC, reach via `ssh://` |
| `SIGHUP` log reopen | `rex server logs` + 50 MiB limit |

Remote-access listeners on Windows: SSH works (OpenSSH Server); built-in Tailscale works (`--tailscale`; auth key as a **file**, e.g. `rex server install -- --tailscale --tailscale-auth-key-file C:\Users\alice\ts-key.txt`); plain HTTP / other VPN works with `--extra-listen` + `--allow-anonymous`; Tailscale Serve refused.

### Windows firewall

- First time a server you started listens on a TCP port Windows asks "allow public and private networks?" - choose **Allow**. **Cancel leaves it blocked**: Windows adds Block rules "Rex Server" immediately and keeps them; later starts don't ask; connections time out. Fix: Windows Security > Firewall & network protection > Allow an app through firewall, or admin: `Remove-NetFirewallRule -DisplayName "Rex Server"`.
- **Service never prompts** (no one signed in): allow ahead of time (admin):
```powershell
New-NetFirewallRule -DisplayName "Rex Server" -Direction Inbound `
  -Program "C:\Program Files\Rex Server\rex.exe" -Action Allow
```
For the WinGet zip use `(Get-Command rex).Source`. A Block rule for the same path wins: delete first. Rules are per `rex.exe` path: re-allow after switching channel or WinGet zip <-> MSI (MSI upgrades keep folder and rules).

---

## 9. Upgrading

Use the package manager you installed with (re-running `install.sh` is safe; it detects the manager; **pass the same `--channel`** or it resets to the default channel). Linux: package + install.sh restart running services automatically. FreeBSD and Windows: **nothing restarts automatically**.

| Installed with | Upgrade |
| --- | --- |
| Debian/Ubuntu | `sudo apt-get update && sudo apt-get install --only-upgrade rex` |
| Fedora/RHEL | `sudo dnf upgrade --refresh rex` |
| openSUSE | `sudo zypper update rex` |
| Arch | `sudo pacman -Syu` |
| Omarchy | `omarchy update` |
| Alpine | `apk update && apk add -u rex` |
| FreeBSD | `pkg upgrade -r rex rex` |
| Nix profile | `nix profile upgrade --regex '.*superlogical.*'` |
| NixOS | `nix flake update rex && sudo nixos-rebuild switch --flake .` (flake.lock = hold) |
| install script / `--tarball` / Amazon Linux 2 | re-run script (with same options/channel) |
| Windows WinGet | `winget upgrade --id Superlogical.RexServer.Preview --source rex` (**stop server first** else "Access is denied") |
| Windows MSI / Zip | run new MSI / stop server then extract zip over old |

### What restarts

Package restarts running Rex services (leaves stopped ones stopped; nothing in containers without running init; FreeBSD never). **Never restarts `rex.socket`/`rex-login-server.socket`** (unit changes apply after stop both + start socket, or reboot).

| Server | On upgrade | Sessions | New version |
| --- | --- | --- | --- |
| Shared | Restarts | **End** | Right away |
| Login server | Restarts | Survive | Right away |
| Account servers | Keep running | Survive | When their sessions end (idle ~10 s after last session + client; `rex server stop` as that user to switch sooner, systemd-logind machines) |
| Personal | Keeps running | Survive | When it stops (autostarted idles out; `rex server start` one: `rex server stop && rex server start`) |

Check: `rex version` (installed) vs `version:` line of `rex server status` (running); mismatch = old server still running.

### FreeBSD
```sh
service rex restart              # ends shared sessions
service rex-login-server restart # account servers + sessions survive
```
Downgrade: `pkg delete rex && pkg install -r rex rex-VERSION` (delete stops both services; `VERSION` like `0.0.1792508098.g07b896`; `pkg info rex`).

### Windows restart by start method

| Started by | To run new version |
| --- | --- |
| Any `rex` command | Nothing (idles out) |
| `rex server start` | `rex server stop`, `rex server start` |
| `rex server install --user` | `rex server stop`, `rex server install --user` (or sign in again) |
| `rex server install` | `rex server stop`, `sc.exe start RexServer-<SID>` (admin) |

Restart ends all programs in sessions (layouts saved, programs don't return).

### Holding an upgrade

| Manager | Hold | Release |
| --- | --- | --- |
| apt | `sudo apt-mark hold rex` | `sudo apt-mark unhold rex` |
| dnf | `sudo dnf versionlock add rex` (RHEL: `dnf install 'dnf-command(versionlock)'`) | `sudo dnf versionlock delete rex` |
| zypper | `sudo zypper addlock rex` | `sudo zypper removelock rex` |
| pacman | `IgnorePkg = rex` under `[options]` in `/etc/pacman.conf` | remove line |
| apk | `apk add rex=VERSION` (e.g. `0.1.0-r0`; `apk info -e -v rex`) | `apk add -u rex` |
| pkg | `pkg lock rex` | `pkg unlock rex` |
| WinGet | `winget pin add --id Superlogical.RexServer.Preview --source rex` | `winget pin remove --id ... --source rex` (list: `winget pin list --source rex`; `--source rex` mandatory) |

### Keeping your changes

Kept across upgrades: `/etc/rex/accounts.jsonc`, `/etc/pam.d/rex-login-server`, drop-ins for the four units, Alpine `/etc/conf.d/rex[-login-server]`, FreeBSD `/etc/rc.conf`. **Replaced:** the four units, `/etc/init.d` scripts, FreeBSD `/usr/local/etc/rc.d` scripts, **FreeBSD PAM policy in `/usr/local/etc/pam.d`**, and (dnf/zypper) `/etc/ssh/ssh_config.d/50-rex.conf` (yours saved `.rpmsave`). Changed-by-both config: yours kept, new saved as `.dpkg-dist` (apt, prompts; install script doesn't), `.rpmnew` (dnf/zypper), `.apk-new` (apk), `.sample` (pkg; accounts file only).

### Client/server version skew

Mac app and server need not match; newer client lacking server feature says e.g. `this server is too old for rex client ls; it needs Rex 0.1.0 or later`. Too far apart: refused, message ends `update the server` / `update the client`.

### Downgrade (e.g. to snapshot)

| Manager | List | Downgrade |
| --- | --- | --- |
| apt | `apt-cache madison rex` | `sudo apt-get install --allow-downgrades rex=VERSION` |
| dnf | `dnf list --showduplicates rex` | `sudo dnf downgrade rex-VERSION` |
| zypper | `zypper search -s -x rex` | `sudo zypper install --oldpackage rex-VERSION` |
| pacman | one version only | `sudo pacman -U URL` |
| apk | `apk search -a -x rex` | `apk add rex=VERSION` |
| pkg | `pkg search -r rex rex` | delete + install (above) |

Downgrade restarts services like upgrade. Data is safe: a version meeting newer-format data refuses to use it rather than overwrite.

### Changing install method

One copy only: `--tarball` binary in `/usr/local/bin` shadows package `/usr/bin/rex` (check `which -a rex`). Tarball -> package: install package then `sudo rm /usr/local/bin/rex`. Package -> tarball/Nix: remove first (`sudo apt-get remove rex` / `sudo dnf remove rex` / `sudo zypper remove rex` / `sudo pacman -R rex` / `apk del rex` / `pkg delete rex`). Removing stops+disables services (ends shared sessions; AUR `rex-bin` doesn't, stop manually); keeps `/var/lib/rex` + `rex` account (FreeBSD `/var/db/rex`, rc.conf). Install script, tab commands share the same repo; on Alpine the script uses `/etc/apk/repositories.d/rex.list`, the tab uses `/etc/apk/repositories` (keep only one).

---

## 10. Privacy and telemetry

**Rex collects no telemetry**: no usage analytics, no own crash reporting, no account or license checks. With default settings the Rex server and `rex` CLI make **no outbound connections**. (Docs caveat: beta, page may lag; report errors in the beta Discord.) Programs run inside Rex are not covered.

| Connection | When | Where |
| --- | --- | --- |
| Update check | Rex for Mac at launch and daily (cannot be turned off) | Superlogical update server (Sparkle; UA like `Rex Beta/0.1.0 Sparkle/2.9.6`; sends only IP + UA; downloads only if you choose) |
| Remote servers | Only ones you add (Mac, iOS, CLI via `--server`, `REX_SERVER`, `rex home`, `rex hosts`); no network discovery | Servers you add |
| iOS crash/analytics | Only if "Share With App Developers" on (Apple relays to Superlogical) or TestFlight build (always) | Apple -> Superlogical; generic data only, no server list/names/layouts/terminal contents; download counts always reported by Apple |
| Package updates | Linux/WinGet/Nix only when you run the package manager (WinGet only with `--source rex`) | Superlogical package repo/WinGet source/Nix flake host; sends IP + UA only |
| Tailscale (built-in) | Only if enabled | Tailscale coordination, relays/peers, your router (UPnP/NAT-PMP/PCP), Let's Encrypt; device uploads Tailscale logs/client metrics (+ flow logs if your admin enables); none to Superlogical |

- Server never self-checks for updates. iOS app never self-updates.
- Rex for Mac runs a local server over a Unix socket, started with no network listeners or Tailscale.
- WinGet source declares product codes/names/publishers unsupported, so installed-program info isn't leaked; it answers from the release list and doesn't record searches.
- Tailscale Serve / tailnet address: Rex only asks your machine's existing Tailscale daemon over its local socket who is connecting; no connections of its own.

---

## 11. Community MCP (beta)

- Exposes to agents: Rex docs, the changelog (release notes for every version, from Discord `#changelog`), and current + archived Rex Beta Discord discussions (community + Superlogical team commentary, design reasoning buried in threads).
- Auth: **Discord OAuth**; you must be a member of the Rex Beta Discord server.
- **Name the MCP server `superlogical`, not `rex`**, to avoid collisions with Rex skills, instructions, and the CLI.
- The server URL and per-client install snippet are in website tabs not captured in the docs: do not invent a URL; get it from `https://www.superlogical.com/rex/docs/beta/community-mcp`.

---

## 12. Quick decision guide for app builders

| Goal | Do |
| --- | --- |
| Local dev against Rex on same machine | Nothing: any `rex` command autostarts a personal server (`REX_AUTOSTART=0` to forbid) |
| Reach one remote Linux/BSD box | Install Rex there, `rex server install` (Linux, systemd), connect `ssh://user@host` |
| Reach a Windows PC | Install, `rex server install` (admin) or `--user`, enable OpenSSH Server, `ssh://user@pc` |
| Headless/CI, tagged tailnet devices | Built-in Tailscale `--tailscale --tailscale-advertise-tag tag:X --tailscale-allow-tailnet-members` or `tailnet://:7297 --tailnet-allow-identified` |
| Multi-user host, separate OS identities | Login server + Tailscale Serve + `accounts.jsonc` |
| Multi-user, trusted, shared sessions | Shared server (`rex` account; remember `usermod --shell`) |
| Private VPN | `--extra-listen http://<vpn-ip>:7297 --allow-anonymous` on the service command line |

---

## Source pages

- `docs/installation.md`
- `docs/linux/installation.md`
- `docs/freebsd/installation.md`
- `docs/windows/installation.md`
- `docs/windows/running.md`
- `docs/linux/server-modes.md`
- `docs/linux/shared-server.md`
- `docs/linux/login-server.md`
- `docs/linux/remote-access.md`
- `docs/linux/upgrading.md`
- `docs/reference/privacy.md`
- `docs/beta/community-mcp.md`
