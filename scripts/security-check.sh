#!/usr/bin/env bash
# Local security checks: the same ones CI runs (.github/workflows/security.yml, ADR 0069).
#
#   scripts/security-check.sh osv       known vulnerabilities in the lockfiles (osv-scanner, needs the network)
#   scripts/security-check.sh secrets   secrets committed to the git history (gitleaks)
#   scripts/security-check.sh licenses  licences and sources of the Rust dependencies (cargo-deny, deny.toml)
#   scripts/security-check.sh           all three
#
# SECURITY_CHECK_RANGE=<git revision range> limits `secrets` to those commits (the pre-push hook
# uses it); without it the whole history is scanned.
#
# Exit code: 0 clean, 1 something was found, 2 a check could not run (tool missing, offline).
# A check that could not run is never reported as a pass.
# shellcheck disable=SC2329  # osv, secrets and licenses are called through run
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

# Keep in step with the pinned versions in .github/workflows/security.yml.
OSV_SCANNER_VERSION=2.7.1
GITLEAKS_VERSION=8.30.1
CARGO_DENY_VERSION=0.20.2

LOCKFILES=(Cargo.lock app/pubspec.lock e2e/package-lock.json)

osv() {
  if ! command -v osv-scanner >/dev/null 2>&1; then
    cat >&2 <<EOF
osv: osv-scanner is not installed, so the vulnerability check did not run.
  Install v${OSV_SCANNER_VERSION} with:  go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v${OSV_SCANNER_VERSION}
  or download osv-scanner_linux_amd64 from https://github.com/google/osv-scanner/releases/tag/v${OSV_SCANNER_VERSION}
EOF
    return 2
  fi
  local args=() f
  for f in "${LOCKFILES[@]}"; do
    [ -f "$f" ] && args+=(-L "$f")
  done
  osv-scanner scan source "${args[@]}" --config osv-scanner.toml
  case $? in
    0)
      echo "osv: no known vulnerabilities (the reviewed exceptions in osv-scanner.toml apply)"
      return 0
      ;;
    1)
      echo "osv: known vulnerabilities found, see above. Fix them, or review one and record an exception with a reason and an expiry date in osv-scanner.toml." >&2
      return 1
      ;;
    *)
      echo "osv: osv-scanner could not finish (offline?), so the vulnerability check did not run." >&2
      return 2
      ;;
  esac
}

secrets() {
  if ! command -v gitleaks >/dev/null 2>&1; then
    cat >&2 <<EOF
secrets: gitleaks is not installed, so the secret scan did not run.
  Install v${GITLEAKS_VERSION} from https://github.com/gitleaks/gitleaks/releases/tag/v${GITLEAKS_VERSION}
  (or: go install github.com/zricethezav/gitleaks/v8@v${GITLEAKS_VERSION})
EOF
    return 2
  fi
  local args=(git . --redact --no-banner)
  [ -n "${SECURITY_CHECK_RANGE:-}" ] && args+=(--log-opts "$SECURITY_CHECK_RANGE")
  gitleaks "${args[@]}"
  case $? in
    0)
      echo "secrets: no secrets found"
      return 0
      ;;
    1)
      echo "secrets: possible secrets found, see above (values are redacted). Remove and rotate them; a false positive goes into .gitleaks.toml with a reason." >&2
      return 1
      ;;
    *)
      echo "secrets: gitleaks could not finish, so the secret scan did not run." >&2
      return 2
      ;;
  esac
}

licenses() {
  if ! command -v cargo-deny >/dev/null 2>&1; then
    cat >&2 <<EOF
licenses: cargo-deny is not installed, so the licence check did not run.
  Install v${CARGO_DENY_VERSION} from https://github.com/EmbarkStudios/cargo-deny/releases/tag/${CARGO_DENY_VERSION}
  (or: cargo install cargo-deny --locked --version ${CARGO_DENY_VERSION})
EOF
    return 2
  fi
  cargo-deny check licenses bans sources
  # Unlike the other tools, cargo-deny exits 1 when it could not run (no Cargo.toml, no network)
  # and with other non-zero codes (2 in v0.20.2; a bit set of the failed checks in the docs) when a
  # check failed, a broken deny.toml included. Death by a signal (128 and up) is not a finding.
  local r=$?
  if [ "$r" -eq 0 ]; then
    echo "licenses: licences and sources are within deny.toml"
    return 0
  elif [ "$r" -eq 1 ] || [ "$r" -ge 128 ]; then
    echo "licenses: cargo-deny could not finish, so the licence check did not run." >&2
    return 2
  fi
  echo "licenses: a dependency breaks the policy in deny.toml, see above. Replace it, or review the licence and allow it there with a reason." >&2
  return 1
}

rc=0
run() {
  "$1"
  local r=$?
  if [ "$r" -eq 1 ]; then
    rc=1
  elif [ "$r" -ne 0 ] && [ "$rc" -eq 0 ]; then
    rc=2
  fi
}

case "${1:-all}" in
  osv) run osv ;;
  secrets) run secrets ;;
  licenses) run licenses ;;
  all)
    run osv
    run secrets
    run licenses
    ;;
  *)
    echo "usage: scripts/security-check.sh [osv|secrets|licenses|all]" >&2
    exit 64
    ;;
esac
exit "$rc"
