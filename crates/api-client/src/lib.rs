//! WASM-safe typed HTTP client and DTOs for the TradoCraft REST API.
//!
//! Designed to compile for both native targets and `wasm32-unknown-unknown`
//! without `sqlx`, `tokio`, or `axum`.

pub mod auth;
pub mod client;
pub mod customers;
pub mod error;
pub mod products;

pub use auth::{
    Auth, Company, EnvKind, EnvironmentInfo, Me, MeModule, Membership, PublicProvider, Session,
    ShortcutBinding, UserPreferences,
};
pub use client::Client;
pub use customers::{Customer, CustomerPage, ListCustomersParams};
pub use error::{ApiError, ErrorBody};
pub use products::{ListProductsParams, Product, ProductPage};
