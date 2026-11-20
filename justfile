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

# Print ticks from a running daemon; arguments: [host:port] [count]
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
