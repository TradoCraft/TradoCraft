# TradoCraft MCP pilot

The MCP binary exposes one read-only tool, `get_order`. Given a sales-order UUID, it returns
the order number, status, latest revision, currency and total. It uses the same company
boundary and order permission as the staff API. The tool call log records the user,
company, OAuth client, order and outcome.

## Start the service

Apply the workspace migrations with `cargo run --locked -p tradocraft-api -- migrate`
against the intended database. Then set these variables for the MCP process and run
`cargo run --locked -p tradocraft-mcp` from the repository root.

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | The migrated TradoCraft PostgreSQL database |
| `MCP_RESOURCE_URL` | Canonical public HTTPS URL such as `https://mcp.example.com/mcp` |
| `MCP_ISSUER` | Exact issuer URL as it appears in OAuth access tokens and discovery |
| `MCP_BIND_ADDR` | Loopback socket, defaults to `127.0.0.1:8091` |

Terminate TLS at a reverse proxy on the same host. Route `/mcp` and
`/.well-known/oauth-protected-resource/mcp` to this process and preserve the public Host.
The endpoint supports Streamable HTTP with per-request authorization. Browser requests
carrying an Origin header are refused.

## Authorize a pilot user

Use an OAuth authorization server that supports the AI client's authorization-code flow
with S256 PKCE and a client registration method it accepts. Configure the server to
authorize `orders:read` and issue signed JWT access tokens with `typ: at+jwt`, a
`kid` resolvable through the issuer's OpenID discovery and JWKS, and the exact
`MCP_RESOURCE_URL` as their sole audience. The token must identify the consenting
user in `sub` and the OAuth client in `client_id`. Token issuance, consent and refresh
are handled by the authorization server.

For the pilot, an administrator verifies the user's consent and company selection and
provisions the corresponding row in `core.mcp_order_read_grants`. Set `issuer`,
`resource`, `subject` and `client_id` to the verified OAuth identifiers, and `user_id`
and `company_id` to the user's existing TradoCraft membership. This one-company grant
requires an active user and membership on each request. The user's current `OrdersRead`
permission must also allow the tool call. To revoke access, delete that grant row.
A self-service company selector and TradoCraft grant management UI are outside this pilot.

## Test

Run `cargo test --locked -p tradocraft-mcp` with a PostgreSQL `DATABASE_URL` whose
role can create temporary test databases. The test uses a local issuer and checks the
MCP authorization challenge, tool discovery, a successful read and denial after
audience, scope, company, permission or grant changes.
