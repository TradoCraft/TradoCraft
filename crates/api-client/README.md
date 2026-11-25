# `tradocraft-api-client`

WASM-safe typed HTTP client and DTOs for the TradoCraft REST API, shared across
the Rust web UI (`wasm32-unknown-unknown`) and native Rust callers.

## Constraints

- Compiles on both native targets and `wasm32-unknown-unknown`.
- No `sqlx`, `tokio`, or `axum` dependencies.
- Uses `reqwest` (`rustls-tls` on native, browser `fetch` on `wasm32-unknown-unknown`)
  behind [`Client`](src/client.rs).
- Uses `rust_decimal` with `serde-with-str` (without `db-postgres`), matching the
  string-encoded decimal representation in `api/openapi.json`.

## Vertical slice covered

- **Auth / session & environment:**
  - `GET /api/v1/auth/providers` (`Client::auth_providers` -> `Vec<PublicProvider>`)
  - `GET /api/v1/meta/environment` (`Client::environment` -> `EnvironmentInfo`)
  - `GET /api/v1/me` (`Client::me`, `Client::sign_in` -> `Me`)
  - `GET` / `PUT /api/v1/me/preferences` (`Client::get_preferences`, `Client::put_preferences` -> `UserPreferences`)
  - Headers matching the backend (`crates/core/src/auth.rs`) and Flutter client
    (`app/lib/app/session.dart`): `X-Dev-User`, `Authorization: Bearer <token>`,
    and `X-Company-Id`.
- **Products:**
  - `GET /api/v1/products` (`Client::list_products` -> `ProductPage`)
- **Customers:**
  - `GET /api/v1/customers` (`Client::list_customers` -> `CustomerPage`)

## Codegen evaluation: `progenitor` vs hand-written

Hand-written DTOs verified against `api/openapi.json` were chosen for this slice:

1. **Offline / environment availability:** `cargo-progenitor` and network access to
   fetch/evaluate external codegen crates were not available in the build sandbox,
   whereas `reqwest` 0.12 and all DTO dependencies (`serde`, `uuid`, `chrono`,
   `rust_decimal`, `thiserror`) are already in `Cargo.lock`.
2. **OpenAPI 3.1 compatibility:** `utoipa` generates `api/openapi.json` as OpenAPI
   **3.1.0**, using `"type": ["string", "null"]` for nullable fields. `progenitor`
   targets OpenAPI 3.0.x (`openapiv3`) and would require an OpenAPI 3.1-to-3.0
   pre-processing pass before generation.
3. **Domain fidelity:** Hand-written types let us use `rust_decimal::Decimal`
   (matching the backend) instead of plain `String` fields and keep the crate small
   for WASM bundle size while growing endpoint coverage slice-by-slice.

If full-surface codegen is adopted later (e.g. via `progenitor` after normalizing
OpenAPI 3.1 schemas to 3.0, or a small workspace codegen binary in `tool/`), it can
replace or generate modules behind the same `Client` API without breaking UI callers.

## CI drift check

`scripts/gen-api-client.sh` verifies that every endpoint path, query parameter, and
DTO property modeled in `crates/api-client` matches `api/openapi.json` (and accepts
`--check` for CI).

In `.github/workflows/ci.yml`, after the existing `OpenAPI document is up to date`
step, add:

```yaml
      - name: Rust API client matches OpenAPI
        run: ./scripts/gen-api-client.sh --check
      - name: API client compiles for WASM
        run: cargo check -p tradocraft-api-client --target wasm32-unknown-unknown
```

## Verification

```bash
cargo test -p tradocraft-api-client
cargo check -p tradocraft-api-client --target wasm32-unknown-unknown
./scripts/gen-api-client.sh --check
```
