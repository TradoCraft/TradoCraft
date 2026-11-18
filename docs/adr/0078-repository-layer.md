# 0078 — Repository layer for the Flutter app

**Status:** Accepted (phase 0 of the shared UI framework; builds on [ADR 0005](0005-api-contract-and-codegen.md) and [ADR 0073](0073-concurrent-edit-protection.md))

**Context.** Screens call the generated client directly: `ref.watch(apiProvider).crm.listCustomers(...)`,
`ref.read(apiProvider).sales.getQuotation(...)`. Each screen repeats how a list is paged, how a
page maps to `EntityList`'s `(items, total)` pair, and which client method belongs to which entity.
A shared UI framework (generic lists, forms, detail screens) needs one small, uniform way to ask
for an entity, without knowing which client group serves it.

**Decision.**

1. **Repositories wrap the generated client.** A repository takes one generated client (for example
   `CrmClient`) and exposes the calls for one entity. The client stays the single source of truth
   for paths and models (ADR 0005); nothing is hand-written HTTP.
2. **A small generic base in `app/lib/framework/data/`.** `ListQuery` (search, offset, limit, plus
   `sort` and `filters` reserved for later phases and read by no repository yet), `Page<T>` (items
   and an optional `total`) and capability interfaces: `ListSource<T>`, `GetSource<T, ID>`,
   `CreateSink<T, I>`, `UpdateSink<T, ID, I>`, `DeleteSink<ID>`. `Repository<T, ID>` is list plus
   get. A repository implements only what its API offers (customers have no delete); there are no
   stub methods that throw. List and detail types may differ (quotations list a summary and read the
   full quotation), so they are separate capabilities. Entity-specific list filters are named
   parameters on the concrete `list` (quotations: `status`).
3. **Errors are not wrapped.** The client's `DioException` passes through unchanged, so
   `errorMessage`, `errorStatus`, `errorCode` and `isRecordChangedError` (409 `record_changed`
   with `expected_version`, ADR 0073) behave exactly as before. A later phase may introduce a typed
   error once screens stop reading Dio types.
4. **Riverpod providers.** Each repository has a `Provider` next to it, built from `apiProvider`
   (`customerRepositoryProvider`, `quotationRepositoryProvider`). Tests that override `dioProvider`
   or `apiProvider` keep working, because the providers derive from them.
5. **Incremental migration.** Customers and quotations are the reference conversions: list pages feed
   `EntityList`'s `PageLoader` through `repository.list(...).asLoaderResult`, and the screens' own
   get, create and update calls go through the repository. Workflow calls (send, accept, convert),
   lookups and every other screen stay on `apiProvider` until they are converted one entity at a
   time. No big-bang change.

**Consequences.**

- Screens depend on an entity interface that tests can fake, and a generic UI can be written against
  `ListSource` and `GetSource`.
- One more small class per entity; the generated client is still reachable, so a missing method never
  blocks a screen.
- Both styles coexist during the migration; a screen mixes them only for calls the repository does
  not cover yet.
