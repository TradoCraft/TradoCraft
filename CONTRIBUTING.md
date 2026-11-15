# Contributing

TradoCraft is licensed under the GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later). See [LICENSE](LICENSE).

By submitting a contribution you agree that it is licensed under the same terms,
and you certify that you have the right to submit it (the
[Developer Certificate of Origin](https://developercertificate.org/)). Sign off
your commits with `git commit -s`.

Note that AGPL section 13 applies to modified versions run as a network service:
users interacting with it remotely must be offered the corresponding source.

## Security checks

CI checks the dependencies for known vulnerabilities ([OSV](https://osv.dev)), the git history for
secrets and the Rust dependencies' licences (AGPL-compatible, `deny.toml`), on every pull request and every week (`.github/workflows/security.yml`, ADR 0069). You can run
the same checks before you push:

```bash
scripts/security-check.sh            # all three; or `osv` / `secrets` / `licenses`
git config core.hooksPath .githooks  # once per clone: run them automatically before every push
```

They need [osv-scanner](https://github.com/google/osv-scanner/releases) and
[gitleaks](https://github.com/gitleaks/gitleaks/releases) and
[cargo-deny](https://github.com/EmbarkStudios/cargo-deny/releases) on your `PATH` (the script says which
version and how to install it when one is missing). A check that cannot run, because a tool is missing
or you are offline, is reported and never counts as a pass. `git push --no-verify` skips the hook for
one push.

A vulnerability that is found is fixed by updating the dependency. If it has been looked at and does
not apply, record it in `osv-scanner.toml` with a reason and an expiry date. A new dependency under
a licence that `deny.toml` does not allow is replaced, or its licence is reviewed and added there with a
reason.

Report a security problem privately, as described in [SECURITY.md](SECURITY.md).
