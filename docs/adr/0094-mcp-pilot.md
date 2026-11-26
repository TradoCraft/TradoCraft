# 0094 — MCP pilot: delegated, read-only order lookup

**Status:** Accepted (pilot; M1 of the roadmap; written after the fact for PR #115; builds on
[ADR 0004](0004-authentication.md))

**Context.** AI clients call tools on a server through the Model Context Protocol (MCP). Letting
one read TradoCraft data on a user's behalf raises three questions: how the client proves which user
it acts for, which company it may see, and what it may do, without a second permission model next to
the staff API. The pilot answers them for one small, read-only tool.

**Decision.** A separate binary `tradocraft-mcp` (`apps/mcp`, built on the `rmcp` crate) and one
table, `core.mcp_order_read_grants` (migration `20270222000001_mcp_order_read_grants.sql`).

1. **One tool.** `get_order` takes a sales-order UUID (`order_id`, unknown fields refused) and
   returns the id, number, status, latest revision, currency and total as structured content. It
   is annotated read-only, not destructive and not open-world. An order that does not exist, belongs
   to another company or is not permitted gives the same tool error ("Order is unavailable to this
   user."), so the answer does not tell which.
2. **Transport.** Streamable HTTP at `/mcp` (`StreamableHttpService`), with JSON responses, the
   legacy session mode off and request bodies limited to 32 KiB. Origin validation is enforced, so
   browser requests carrying an `Origin` header are refused; the public host of `MCP_RESOURCE_URL`
   is the allowed host.
3. **OAuth protected resource.** The server is a resource server only; issuing tokens, consent
   and refresh are left to an external authorization server (authorization code with S256 PKCE).
   `GET /.well-known/oauth-protected-resource/mcp` publishes the resource, the one authorization
   server (`MCP_ISSUER`), the scope `orders:read` and the header bearer method. Every request to
   `/mcp` must carry a bearer token; a missing or invalid one is a 401 and a missing scope a 403
   with `error="insufficient_scope"`, each with a `WWW-Authenticate` header pointing at the
   metadata. The `Authorization` header is removed from the request before it reaches the tool.
4. **Token checks.** The token must be a JWT with `typ` `at+jwt` (or `application/at+jwt`). Its
   signature, `kid`, algorithm, issuer and expiry are checked by the shared verifier of
   `tradocraft_core::identity` (keys from the issuer's discovery and JWKS). On top of that the
   `iss` claim must equal `MCP_ISSUER` exactly, the `aud` claim must be `MCP_RESOURCE_URL` and
   nothing else (a string or a one-element array), `client_id` must be present and `scope` must
   contain `orders:read`. A token issued for the staff API or another resource is therefore not
   accepted here.
5. **Grant selects the user and the company.** A token is mapped to a TradoCraft user through a row
   of `core.mcp_order_read_grants`, keyed by issuer, resource, subject (`sub`) and `client_id`, which
   names exactly one `user_id` and `company_id`. The row references the membership
   (`core.user_companies`) and is deleted with it. A token without a matching grant is a 403. For the
   pilot an administrator verifies the user's consent and company and inserts the row by hand;
   deleting it revokes access.
6. **Same boundary and permission as the staff API.** On every request the user and membership are
   loaded again (`CurrentUser::for_member`: the user must be active and still a member), and the tool
   calls the staff API's own `tradocraft_sales::orders::read_order`, which requires
   `Permission::OrdersRead` (`orders.read`) and loads the order within the user's company. No MCP
   permission of its own exists, and changes to the user, membership or role take effect on the next
   call.
7. **Logging.** Each tool call is logged through `tracing` with the user, company, OAuth client,
   order and whether it succeeded.
8. **Deployment.** Configured by `DATABASE_URL` (the migrated TradoCraft database),
   `MCP_RESOURCE_URL` (must be a canonical HTTPS URL whose path is `/mcp`, without credentials,
   query or fragment), `MCP_ISSUER` (validated like other identity provider URLs) and
   `MCP_BIND_ADDR` (default `127.0.0.1:8091`; it must be a loopback address). TLS is terminated by a
   reverse proxy on the same host that routes `/mcp` and the metadata path to the process and keeps
   the public Host. The process does not run migrations; they are applied with
   `tradocraft-api migrate`.

**Consequences.**

- An AI client sees at most what its user may see in the staff API, in one company, and only one
  kind of record. Revoking a grant, removing the membership, deactivating the user or taking away
  `orders.read` stops it at the next call.
- The token, the grant and the membership are checked on each request, not cached per session, so
  each call costs a grant lookup and a membership lookup.
- Granting access is manual database work by an administrator; a self-service company selector and a
  grant management screen in TradoCraft are deferred.
- Tool calls are written to the service log, not to the audit trail.
- Only one authorization server per MCP process is supported, and it must issue JWT access tokens;
  opaque tokens with introspection are not supported.
- The binary is not in the Docker image or the compose files; it is run and proxied separately.
- No further tools (search, other records, any write) are planned.
