//! Generates the Rust types and service traits from the shared `.proto` file.

const PROTO_ROOT: &str = "../proto";
const MONITOR_PROTO: &str = "../proto/computa/v1/monitor.proto";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-changed={MONITOR_PROTO}");
    tonic_prost_build::configure().compile_protos(&[MONITOR_PROTO], &[PROTO_ROOT])?;
    Ok(())
}
