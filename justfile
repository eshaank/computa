# Computa task runner. Run `just` to list the recipes.

# Cargo installs to ~/.cargo/bin, which is not on PATH in every shell.
export PATH := env_var('HOME') + "/.cargo/bin:" + env_var('PATH')

# List the recipes
default:
    @just --list

# Build the daemon and the app
build:
    cd daemon && cargo build
    cd app && swift build

# Run the daemon on 127.0.0.1:7300 (Ctrl-C stops it)
run:
    cd daemon && cargo run

# Install the daemon as a login item (add --dry-run to see the steps first)
install-daemon *args:
    scripts/install-daemon.sh {{args}}

# Remove the daemon's login item and its installed copy
uninstall-daemon:
    scripts/install-daemon.sh --uninstall

# Add Computa's Rex actions to your Rex config; it shows the line and asks first
install-rex-actions *args:
    scripts/install-rex-actions.sh {{args}}

# Try the Rex actions in a throwaway Rex session (needs Rex running)
test-rex-actions:
    scripts/test-rex-actions.sh

# Build Computa.app into app/.build/ (a release build, a few minutes when cold)
app:
    scripts/build-app.sh

# Build Computa.app and open it in the menu bar
open-app: app
    open app/.build/Computa.app

# Render the app's views to PNG files in app/.build/snapshots/
snapshots:
    cd app && swift run computa-snapshot

# Print what a running daemon reports; arguments: [host:port] [count]
probe *args:
    cd app && swift run computa-probe {{args}}

# Run every test in both programs
test:
    cd daemon && cargo test
    cd app && swift test

# Run the app's tests as a release build, the way Computa.app is built (several minutes)
test-release:
    cd app && swift test -c release -Xswiftc -enable-testing

# Check Rust lints and formatting
lint:
    cd daemon && cargo clippy --all-targets -- -D warnings
    cd daemon && cargo fmt --check
