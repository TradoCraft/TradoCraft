# Security policy

## Reporting a vulnerability

Please report security problems **privately**, with GitHub's private vulnerability reporting:
open the repository's **Security** tab and choose **Report a vulnerability**
(<https://github.com/TradoCraft/TradoCraft/security/advisories/new>).

Please do not open a public issue or pull request for a vulnerability, and do not put real customer
data or credentials in a report.

It helps to include:

* the version or commit, and how you run TradoCraft (Docker Compose or your own build, and which
  `AUTH_MODE`);
* the steps to reproduce it;
* what you expected, what happened, and the impact you see.

## What to expect

TradoCraft is free software (AGPL-3.0-or-later) that you run yourself. It is maintained without a
support contract, so reports are handled on a best-effort basis and no response time is promised.

When a report is confirmed, the fix goes into `main` and a GitHub Security Advisory is published
with the affected versions, the fixed version and any workaround. The reporter is credited unless
they prefer not to be.

## Supported versions

Only the latest release and `main` receive security fixes. There are no backports: update to the
latest release to get a fix.

## If you run TradoCraft

* **Hear about advisories:** on the repository page choose *Watch* → *Custom* → *Security alerts*
  and *Releases*.
* **Never run `AUTH_MODE=dev` on a server that others can reach.** It trusts the `X-Dev-User`
  header, so anybody can sign in as any user. It exists for development and the tutorial
  environment only. Use OIDC (see `docs/adr/0004-authentication.md`).
* **Change the default database credentials** of the example Compose file before you use it.

## How the project checks its dependencies

Known vulnerabilities in the Rust, Dart and Node dependencies are checked with
[OSV](https://osv.dev) on every pull request and every week, and committed secrets are scanned
for. Each release carries a CycloneDX software bill of materials. See
[ADR 0069](docs/adr/0069-dependency-vulnerability-scanning-and-disclosure.md).
