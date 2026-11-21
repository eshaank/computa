#!/bin/bash
# Runs rex/tests/actions_test.lua in a throwaway Rex session, then removes
# the session. Needs a running Rex server. Your own sessions are not touched.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    echo "test-rex-actions: $1" >&2
    exit 1
}

command -v rex >/dev/null || die "the rex command was not found on PATH"
rex config check "$REPO/rex/computa.lua" >/dev/null || die "rex/computa.lua does not load"

created="$(rex new computa-action-test --json -- sleep 600)" || die "could not create a test session"
session="$(printf '%s' "$created" | sed -n 's/.*"session_id"[^"]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$session" ] || die "could not read the test session's id from: $created"

cleanup() {
    rex kill "$session" >/dev/null 2>&1 || echo "test-rex-actions: could not remove $session; run: rex kill $session" >&2
}
trap cleanup EXIT

rex do -s "$session" "$REPO/rex/tests/actions_test.lua" "repo=$REPO"
