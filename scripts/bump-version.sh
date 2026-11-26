#!/usr/bin/env bash
# Sets the release version everywhere it lives (docs/RELEASING.md).
#   scripts/bump-version.sh 0.4.0          rewrite the files
#   scripts/bump-version.sh --check        fail unless all places agree with Cargo.toml
set -euo pipefail
cd "$(dirname "$0")/.."

current="$(sed -nE '/^\[workspace\.package\]/,/^\[/ s/^version = "([^"]+)"$/\1/p' Cargo.toml | head -n1)"
[[ -n "$current" ]] || { echo "Cannot read [workspace.package] version from Cargo.toml" >&2; exit 1; }

if [[ "${1:-}" == "--check" ]]; then
  bad=0
  grep -q "^version: ${current}+" app/pubspec.yaml || { echo "app/pubspec.yaml differs from ${current}"; bad=1; }
  python3 - "$current" <<'PY' || bad=1
import json, sys
v = json.load(open("api/openapi.json"))["info"]["version"]
if v != sys.argv[1]:
    print(f"api/openapi.json is {v}, expected {sys.argv[1]}"); sys.exit(1)
PY
  if grep -E 'TRADOCRAFT_VERSION:-[0-9]' deploy/docker-compose.release.yml | grep -vq "TRADOCRAFT_VERSION:-${current}}"; then
    echo "deploy/docker-compose.release.yml differs from ${current}"; bad=1
  fi
  grep -q "default: 'v${current}'" .github/workflows/release.yml || { echo ".github/workflows/release.yml default differs from v${current}"; bad=1; }
  exit "$bad"
fi

new="${1:-}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 MAJOR.MINOR.PATCH | --check" >&2; exit 2; }

sed -i -E "/^\[workspace\.package\]/,/^\[/ s/^version = \"[^\"]+\"$/version = \"${new}\"/" Cargo.toml
# Flutter: keep the build number (+N) and add one, so each release has a higher build number.
build="$(sed -nE 's/^version: [^+]+\+([0-9]+)$/\1/p' app/pubspec.yaml)"
sed -i -E "s/^version: .*/version: ${new}+$(( ${build:-0} + 1 ))/" app/pubspec.yaml
python3 - "$new" <<'PY'
import re, sys
p = "api/openapi.json"
s = open(p).read()
s = re.sub(r'("info": \{.*?"version": ")[^"]+(")', lambda m: m.group(1) + sys.argv[1] + m.group(2), s, count=1, flags=re.S)
open(p, "w").write(s)
PY
sed -i -E "s/(TRADOCRAFT_VERSION:-)[0-9]+\.[0-9]+\.[0-9]+\}/\1${new}}/g" deploy/docker-compose.release.yml
sed -i -E "s/default: 'v[0-9]+\.[0-9]+\.[0-9]+'/default: 'v${new}'/" .github/workflows/release.yml
# Cargo.lock records the workspace crates' versions; --locked builds fail if it is stale.
cargo update --workspace --offline >/dev/null
echo "Version set to ${new}. Next: scripts/generate-api-client.sh, update CHANGELOG.md, then scripts/bump-version.sh --check"
