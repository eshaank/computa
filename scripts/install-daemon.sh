#!/usr/bin/env bash
# Installs computad as a login item (a LaunchAgent) for the current user.
#
#   scripts/install-daemon.sh             build, install, load, and check it answers
#   scripts/install-daemon.sh --dry-run   print every step and the plist; change nothing
#   scripts/install-daemon.sh --uninstall unload it and remove the plist and binary
#
# --dry-run also works with --uninstall. Logs are kept on uninstall.
set -euo pipefail

LABEL="app.computa.computad"
PORT=7300
ADDR="127.0.0.1:${PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${HOME}/Library/Application Support/Computa/bin"
BIN="${BIN_DIR}/computad"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST="${PLIST_DIR}/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/Computa"
LOG="${LOG_DIR}/computad.log"
REX_KNOWN="${HOME}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
DOMAIN="gui/$(id -u)"

DRY_RUN=0
UNINSTALL=0
TMP_PLIST=""
trap 'if [ -n "$TMP_PLIST" ]; then rm -f "$TMP_PLIST"; fi' EXIT

die() { echo "error: $*" >&2; exit 1; }
say() { echo "==> $*"; }

# Runs a command, or only prints it in a dry run.
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] would run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --uninstall) UNINSTALL=1 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; die "unknown option: $1" ;;
        esac
        shift
    done
}

# The full path of rex, or nothing. Same order as the daemon, minus PATH
# entries launchd will not have.
find_rex() {
    if [ -n "${COMPUTAD_REX:-}" ]; then
        [ -x "$COMPUTAD_REX" ] || die "COMPUTAD_REX is set to '$COMPUTAD_REX', which is not an executable file"
        echo "$COMPUTAD_REX"
    elif command -v rex >/dev/null 2>&1; then
        command -v rex
    elif [ -x "$REX_KNOWN" ]; then
        echo "$REX_KNOWN"
    fi
}

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Writes the LaunchAgent plist to $1. $2 is the path of rex, or empty.
write_plist() {
    local out="$1" rex="$2" env_block=""
    if [ -n "$rex" ]; then
        env_block="    <key>EnvironmentVariables</key>
    <dict>
        <key>COMPUTAD_REX</key>
        <string>$(xml_escape "$rex")</string>
    </dict>
"
    fi
    cat > "$out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(xml_escape "$BIN")</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
${env_block}    <key>StandardOutPath</key>
    <string>$(xml_escape "$LOG")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "$LOG")</string>
</dict>
</plist>
EOF
}

is_loaded() {
    launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1
}

# The pid listening on the port, or nothing.
listener_pid() {
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
}

# Refuses to go on if something other than a previous copy of this daemon
# is listening on the port.
check_port() {
    local pid exe
    pid="$(listener_pid)"
    if [ -z "$pid" ]; then
        say "Port ${PORT} is free."
        return
    fi
    exe="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    if [ "$exe" = "$BIN" ]; then
        say "Port ${PORT} is held by a previous copy of this daemon (pid ${pid}); it will be replaced."
        return
    fi
    local msg="something else is listening on ${ADDR}: pid ${pid} (${exe:-unknown program}).
       Stop it first (if it is 'cargo run' or 'just run' of computad, press Ctrl-C there), then run this again."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] a real install would stop here: ${msg}" >&2
        return
    fi
    die "$msg"
}

unload() {
    if ! is_loaded; then
        say "No loaded copy of ${LABEL} to unload."
        return
    fi
    say "Unloading the loaded copy of ${LABEL}."
    if ! run launchctl bootout "${DOMAIN}/${LABEL}"; then
        die "launchctl bootout ${DOMAIN}/${LABEL} failed. Check 'launchctl print ${DOMAIN}/${LABEL}', then try again."
    fi
    [ "$DRY_RUN" -eq 1 ] && return
    # bootout returns before the service is fully gone; bootstrap fails until it is.
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        is_loaded || return 0
        sleep 1
    done
    die "${LABEL} was still loaded 10 s after bootout. Check 'launchctl print ${DOMAIN}/${LABEL}'."
}

build_and_copy() {
    say "Building the release daemon."
    # Cargo installs to ~/.cargo/bin, which is not on PATH in every shell.
    PATH="${HOME}/.cargo/bin:${PATH}"
    command -v cargo >/dev/null 2>&1 \
        || die "cargo was not found. Install Rust from https://rustup.rs and try again."
    run cargo build --release --manifest-path "${REPO}/daemon/Cargo.toml" \
        || die "cargo build --release failed; see the errors above."
    say "Copying the daemon to ${BIN}."
    run mkdir -p "$BIN_DIR" "$LOG_DIR" || die "could not create ${BIN_DIR} or ${LOG_DIR}"
    run install -m 755 "${REPO}/daemon/target/release/computad" "$BIN" \
        || die "could not copy the daemon to ${BIN}"
}

# Writes, lints and places the plist. In a dry run it lints a temp copy.
place_plist() {
    local rex
    rex="$(find_rex)"
    if [ -n "$rex" ]; then
        say "Found rex at: ${rex}"
    else
        say "rex was not found; the daemon will report Rex as unreachable until COMPUTAD_REX is set."
    fi
    TMP_PLIST="$(mktemp -t computad-plist)" || die "could not create a temporary file"
    write_plist "$TMP_PLIST" "$rex"
    plutil -lint "$TMP_PLIST" || die "the generated plist is not valid (see above)"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "The plist that would be written to ${PLIST}:"
        cat "$TMP_PLIST"
    fi
    run mkdir -p "$PLIST_DIR" || die "could not create ${PLIST_DIR}"
    run install -m 644 "$TMP_PLIST" "$PLIST" || die "could not write ${PLIST}"
}

# Waits for the installed daemon to listen, and asks it for GetHost when
# grpcurl is available.
confirm_running() {
    local pid="" _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pid="$(listener_pid)"
        [ -n "$pid" ] && break
        sleep 1
    done
    [ -n "$pid" ] || die "the daemon is not listening on ${ADDR} after 10 s. See ${LOG}."
    [ "$(ps -o comm= -p "$pid")" = "$BIN" ] \
        || die "pid ${pid} is listening on ${ADDR}, but it is not ${BIN}. See ${LOG}."
    if command -v grpcurl >/dev/null 2>&1; then
        grpcurl -plaintext -import-path "${REPO}/proto" -proto computa/v1/monitor.proto \
            -max-time 5 "$ADDR" computa.v1.Monitor/GetHost >/dev/null \
            || die "the daemon is listening but did not answer GetHost. See ${LOG}."
        say "The daemon answers on ${ADDR} (pid ${pid}, GetHost OK)."
    else
        say "The daemon is listening on ${ADDR} (pid ${pid}). Install grpcurl for a fuller check."
    fi
}

install_daemon() {
    check_port
    build_and_copy
    place_plist
    unload
    say "Loading ${LABEL}."
    run launchctl bootstrap "$DOMAIN" "$PLIST" \
        || die "launchctl bootstrap ${DOMAIN} ${PLIST} failed. Check ${LOG} and 'launchctl print ${DOMAIN}/${LABEL}'."
    if [ "$DRY_RUN" -eq 1 ]; then
        say "[dry-run] would wait for ${BIN} to listen on ${ADDR} and call GetHost."
        say "Dry run finished; nothing was changed."
    else
        confirm_running
        say "Installed. It starts at login and restarts if it stops. Logs: ${LOG}"
    fi
}

uninstall_daemon() {
    unload
    if [ -e "$PLIST" ]; then
        run rm -f "$PLIST" || die "could not remove ${PLIST}"
    else
        say "No plist at ${PLIST}."
    fi
    if [ -e "$BIN" ]; then
        run rm -f "$BIN" || die "could not remove ${BIN}"
    else
        say "No binary at ${BIN}."
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        say "Dry run finished; nothing was changed."
    else
        say "Uninstalled. Logs are kept in ${LOG_DIR}."
    fi
}

main() {
    parse_args "$@"
    [ "$(uname -s)" = "Darwin" ] || die "this script installs a macOS LaunchAgent; run it on a Mac."
    if [ "$UNINSTALL" -eq 1 ]; then
        uninstall_daemon
    else
        install_daemon
    fi
}

main "$@"
