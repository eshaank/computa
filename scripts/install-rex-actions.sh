#!/bin/bash
# Adds Computa's Rex actions to your Rex config, or removes them.
#
#   scripts/install-rex-actions.sh            show the line, ask, then add it
#   scripts/install-rex-actions.sh --yes      add it without asking
#   scripts/install-rex-actions.sh --remove   take it out again
#
# It adds one line to Rex's init.lua that loads rex/computa.lua from this
# repository. The config file is $REX_CONFIG when set, otherwise
# $XDG_CONFIG_HOME/rex/init.lua or ~/.config/rex/init.lua. The file is
# backed up first. Nothing takes effect until you run `rex config reload`.

set -euo pipefail

MARKER="-- computa-actions"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIONS="$REPO/rex/computa.lua"
CONFIG="${REX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/rex/init.lua}"
LINE="dofile(\"$ACTIONS\") $MARKER"

die() {
    echo "install-rex-actions: $1" >&2
    exit 1
}

mode="install"
assume_yes="no"
for arg in "$@"; do
    case "$arg" in
        --yes) assume_yes="yes" ;;
        --remove) mode="remove" ;;
        *) die "unknown argument \"$arg\"; use --yes or --remove" ;;
    esac
done

command -v rex >/dev/null || die "the rex command was not found on PATH"
[ -f "$ACTIONS" ] || die "$ACTIONS is missing"

backup() {
    local copy
    copy="$CONFIG.computa-backup"
    cp "$CONFIG" "$copy" || die "could not back up $CONFIG"
    echo "Backed up $CONFIG to $copy"
}

remove_line() {
    [ -f "$CONFIG" ] || die "$CONFIG does not exist; nothing to remove"
    if ! grep -qF -- "$MARKER" "$CONFIG"; then
        echo "Computa's line is not in $CONFIG; nothing to remove."
        exit 0
    fi
    backup
    local kept
    kept="$(grep -vF -- "$MARKER" "$CONFIG" || true)"
    printf '%s\n' "$kept" > "$CONFIG" || die "could not rewrite $CONFIG"
    echo "Removed Computa's line. Run: rex config reload"
}

install_line() {
    rex config check "$ACTIONS" >/dev/null || die "rex/computa.lua does not load; run: rex config check $ACTIONS"
    if [ -f "$CONFIG" ] && grep -qF -- "$MARKER" "$CONFIG"; then
        echo "Computa's line is already in $CONFIG; nothing to do."
        exit 0
    fi
    echo "This will add one line to $CONFIG:"
    echo
    echo "    $LINE"
    echo
    if [ "$assume_yes" != "yes" ]; then
        read -r -p "Add it? [y/N] " answer
        case "$answer" in
            y | Y | yes) ;;
            *) echo "Nothing changed."; exit 0 ;;
        esac
    fi
    mkdir -p "$(dirname "$CONFIG")" || die "could not create $(dirname "$CONFIG")"
    if [ -f "$CONFIG" ]; then
        backup
    fi
    printf '\n%s\n' "$LINE" >> "$CONFIG" || die "could not write $CONFIG"
    if ! rex config check "$CONFIG"; then
        die "$CONFIG now reports problems (see above); restore the backup or fix them before reloading"
    fi
    echo
    echo "Added. To load the actions, run: rex config reload"
}

if [ "$mode" = "remove" ]; then
    remove_line
else
    install_line
fi
