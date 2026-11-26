# Releasing TradoCraft

How versions are chosen, where they live, how a release is cut and how to verify what it published.
The changelog is [CHANGELOG.md](../CHANGELOG.md); open work before a release is in the "First release
checklist" of [ROADMAP.md](ROADMAP.md).

## Versioning policy

TradoCraft uses [Semantic Versioning 2.0.0](https://semver.org/). A release is a git tag
`vMAJOR.MINOR.PATCH` (for example `v0.4.0`) on a commit of `main`. The tag is the only trigger of
`.github/workflows/release.yml`, which rejects any other form (no `-rc`, no build metadata).

One version number covers the whole product: the Cargo workspace (API, worker, portal server, web
UI), the OpenAPI document, the Flutter app and the Docker images are released together.

### Before 1.0.0

While the major version is 0, the public surface is not yet frozen:

- A **MINOR** release (0.x.0) may contain breaking changes, including to the HTTP API, the database
  schema, configuration variables and the deployment files. Breaking changes are marked **Breaking**
  in the changelog and, when an upgrade needs manual steps, explained there.
- A **PATCH** release (0.x.y) contains only backwards-compatible bug and security fixes. It does not
  add features, change configuration or require a migration that cannot run unattended.
- Pin a minor version (`tradocraft-backend:0.4`) to receive patch releases only.

### From 1.0.0

- **MAJOR**: a breaking change to the HTTP API (see the compatibility promise), to the configuration
  variables, or a database migration that cannot be applied to the previous major's data without manual
  steps; removal of a supported deployment.
- **MINOR**: backwards-compatible features: new endpoints, new optional fields, new modules, new
  optional configuration, additive migrations.
- **PATCH**: backwards-compatible fixes, including security fixes, dependency updates and
  documentation.

### API compatibility promise

The API is described by `api/openapi.json` (served at `/api-docs/openapi.json`) under `/api/v1`.

- From 1.0.0, within one major version: no endpoint, field or enum value is removed or renamed, no
  optional request field becomes required, no response field changes type, and error status codes keep
  their meaning. Clients must ignore response fields and enum values they do not know. New optional
  request fields and new endpoints may appear in any minor release.
- A feature may be deprecated in a minor release and removed in the next major release. A breaking
  change that cannot be avoided gets a new path prefix (`/api/v2`) and the old one keeps working for the
  rest of the major version.
- Before 1.0.0 the promise is weaker: breaking changes happen only in minor releases and are listed in
  the changelog; the generated Dart client and `crates/api-client` are regenerated together with the API.
- Not covered: endpoints marked internal or experimental in the OpenAPI document, the database schema
  (read it through the API), the Docker image contents other than the documented binaries and variables,
  and the development-only authentication mode.
- Database migrations only move forward; there is no supported downgrade. Take a backup first
  ([runbook](runbooks/backup-and-restore.md)).

## Where the version lives

| Place | What | How it changes |
|---|---|---|
| `Cargo.toml` `[workspace.package] version` | Source of truth; every crate uses `version.workspace = true` | `scripts/bump-version.sh` |
| `Cargo.lock` | Versions of the workspace crates (`--locked` builds fail if stale) | `cargo update --workspace`, run by the script |
| `api/openapi.json` `info.version` | Published API description | script; regenerate with `scripts/generate-api-client.sh` |
| `app/pubspec.yaml` `version: X.Y.Z+N` | Flutter app; `N` is a build number the script increments (Android requires it to rise) | script |
| `deploy/docker-compose.release.yml` | Default `TRADOCRAFT_VERSION` of the packaged Compose file (the release workflow also rewrites it) | script |
| `.github/workflows/release.yml` | Default of the manual `tag` input | script |
| `CHANGELOG.md` | Move `Unreleased` to the new version and date | by hand |

`scripts/bump-version.sh --check` fails when these places disagree; run it before tagging.

## Release procedure

1. Check the blockers in the "First release checklist" of `ROADMAP.md` and that CI is green on `main`.
2. `scripts/bump-version.sh X.Y.Z`, then `scripts/generate-api-client.sh` (the OpenAPI document and Dart
   client must match the code), then run `scripts/bump-version.sh --check`.
3. Edit `CHANGELOG.md`: rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`, add a fresh empty `Unreleased`
   section and update the compare links at the bottom.
4. Commit (`chore: release X.Y.Z`) through a pull request and merge it.
5. Tag the merge commit and push the tag:
   `git tag -s vX.Y.Z -m "TradoCraft X.Y.Z" && git push origin vX.Y.Z`
   (use `-a` instead of `-s` if you have no signing key for git).
6. The `Release` workflow then builds and pushes `tradocraft-backend` and `tradocraft-web` to GHCR
   tagged `X.Y.Z` and `X.Y` and signs each image by digest; builds the Windows app and the portable demo;
   smoke-tests the packaged `docker-compose.yml`; writes `SHA256SUMS`, signs it and creates the GitHub
   Release with all files.
7. Check the release page, make sure both GHCR packages are public, and verify the signatures (below).
8. Android builds are released by their own workflow; see
   [app/android/SIGNING.md](../app/android/SIGNING.md) for the signing keys and procedure.

A failed release can be re-run from the Actions tab (`workflow_dispatch`, tag input). Never move or
reuse a tag that was published; fix forward with the next patch version. The `latest` tag is not
published: always name a version.

## Release signing and verification

Release artifacts are signed with [cosign](https://docs.sigstore.dev/cosign/overview/) in keyless mode:
the release workflow proves its identity to Sigstore with a GitHub OIDC token and receives a
short-lived certificate. There is no signing key to store, rotate or leak, and nothing secret is
committed. The signatures are recorded in the public Rekor transparency log. The Docker images are
signed by digest; `SHA256SUMS` is signed as a blob and its bundle `SHA256SUMS.sigstore.json` is attached to
the release.

The identity to trust is this repository's release workflow on a version tag. Replace `OWNER` with the
repository owner (as written in the GitHub URL) and `X.Y.Z` with the version.

Verify a Docker image:

```bash
cosign verify ghcr.io/OWNER/tradocraft-backend:X.Y.Z \
  --certificate-identity-regexp '^https://github\.com/OWNER/TradoCraft/\.github/workflows/release\.yml@refs/tags/vX\.Y\.Z$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The same command works for `tradocraft-web`. For a deployment, pin the digest that verification printed
(`image: ghcr.io/OWNER/tradocraft-backend@sha256:...`) instead of the tag.

Verify the downloaded files:

```bash
cosign verify-blob SHA256SUMS --bundle SHA256SUMS.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/OWNER/TradoCraft/\.github/workflows/release\.yml@refs/tags/vX\.Y\.Z$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
sha256sum --check --ignore-missing SHA256SUMS    # on Windows: Get-FileHash -Algorithm SHA256 <file>
```

Windows binaries are not Authenticode-signed: Windows SmartScreen may warn when the demo or the app
is first started. The checksum signature above is the integrity check. The Android release key is
owned and held by the repository owner (see `app/android/SIGNING.md`); no production key is stored in the
repository or in the workflows.

Not yet verified in practice: the signing steps have not run on a real tag. Run a first release as a
dry run on a test tag in a fork, or check the workflow log of the first tag, before relying on them.
