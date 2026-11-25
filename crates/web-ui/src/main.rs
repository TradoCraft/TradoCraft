#[cfg(target_arch = "wasm32")]
fn main() {
    tradocraft_web_ui::mount_app();
}

#[cfg(not(target_arch = "wasm32"))]
fn main() {
    // Native stub so `cargo check --workspace` and `cargo clippy --all-targets` succeed.
}
