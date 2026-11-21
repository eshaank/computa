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

# Check Rust lints and formatting
lint:
    cd daemon && cargo clippy --all-targets -- -D warnings
    cd daemon && cargo fmt --check
