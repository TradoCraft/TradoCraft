#!/usr/bin/env bash
# Smoke test for scripts/tutorial-env: up, idempotence, status/address, reset, down, refusals.
#
# Needs a built API (cargo build -p tradocraft-api; set ENVCTL_API_BIN to reuse a binary) and
# psql/createdb/dropdb/curl/jq. PostgreSQL comes from SMOKE_DATABASE_URL (a superuser-like URL) or
# a throwaway postgres:16 Docker container on SMOKE_PG_PORT (default 55470).
# shellcheck disable=SC2015  # pass never fails, so A && pass || fail is safe here
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUT="$ROOT/scripts/tutorial-env"
ENVCTL="$ROOT/scripts/envctl"
WORK="$(mktemp -d)"
CONTAINER="tradocraft-tutorial-smoke-$$-$RANDOM"
CID=""
FAILS=0
NAME="tutsmoke_$RANDOM"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
check() { # check "description" command...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}

export ENVCTL_DIR="$WORK/envs"
export ENVCTL_CONFIG=/dev/null

cleanup() {
  local f n
  if [[ -d "$ENVCTL_DIR/registry" && -n "${DATABASE_URL:-}" ]]; then
    for f in "$ENVCTL_DIR"/registry/*.env; do
      [[ -e "$f" ]] || continue
      n="$(basename "$f" .env)"
      "$ENVCTL" drop "$n" --yes >/dev/null 2>&1 || "$ENVCTL" stop "$n" >/dev/null 2>&1 || true
    done
  fi
  if [[ -n "$CID" ]]; then docker rm -f "$CID" >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [[ -n "${SMOKE_DATABASE_URL:-}" ]]; then
  export DATABASE_URL="$SMOKE_DATABASE_URL"
else
  PORT="${SMOKE_PG_PORT:-55470}"
  CID="$(docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=smoke -p "127.0.0.1:$PORT:5432" \
    postgres:16 -c max_connections=300)"
  export DATABASE_URL="postgresql://postgres:smoke@127.0.0.1:$PORT/postgres"
  for _ in $(seq 1 60); do
    PGPASSWORD=smoke psql -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -c 'select 1' >/dev/null 2>&1 && break
    sleep 1
  done
fi

export ENVCTL_PORT_MIN="${SMOKE_API_PORT_MIN:-18200}"
export ENVCTL_PORT_MAX="${SMOKE_API_PORT_MAX:-18250}"
export AUTH_MODE=dev

_rest="${DATABASE_URL#*://}"
_userinfo="${_rest%@*}"
_hostport="${_rest##*@}"
_hostport="${_hostport%%/*}"
export PGUSER="${_userinfo%%:*}"
export PGPASSWORD="${_userinfo#*:}"
export PGHOST="${_hostport%%:*}"
export PGPORT="${_hostport#*:}"
q() { psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }

echo "== help and usage errors =="
check "--help exits 0" "$TUT" --help
check "help prints usage" bash -c "'$TUT' help | grep -q 'Usage: tutorial-env'"
rc=0; "$TUT" bogus >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] && pass "unknown command exits 2" || fail "unknown command exit $rc"
rc=0; "$TUT" --nope up >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] && pass "unknown option exits 2" || fail "unknown option exit $rc"
rc=0; "$TUT" >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] && pass "missing command exits 2" || fail "missing command exit $rc"
check "unsafe name refused" bash -c "! '$TUT' --name 'x; y' up"
check "reserved name refused" bash -c "! '$TUT' --name live up"

echo "== up =="
OUT="$("$TUT" --name "$NAME" up)"
echo "$OUT"
URL="$("$TUT" --name "$NAME" address)"
[[ "$URL" == http://* ]] && pass "address prints a URL" || fail "address: '$URL'"
grep -q "$URL" <<<"$OUT" && pass "up prints the address" || fail "up output lacks the address"
grep -q "admin@example.com" <<<"$OUT" && pass "up prints the demo sign-in" || fail "up output lacks the sign-in"
DOC="$(curl -fsS "$URL/api/v1/meta/environment")"
[[ "$(jq -r .kind <<<"$DOC")" == tutorial ]] && pass "meta/environment kind is tutorial" || fail "kind: $DOC"
[[ "$(jq -r .name <<<"$DOC")" == "$NAME" ]] && pass "meta/environment name matches" || fail "name: $DOC"
ME="$(curl -fsS -H 'X-Dev-User: admin@example.com' "$URL/api/v1/me" || true)"
[[ -n "$ME" ]] && pass "GET /api/v1/me answers for the demo admin" || fail "/api/v1/me empty"
[[ "$(q "$NAME" "SELECT count(*) FROM core.companies")" -ge 1 ]] && pass "demo company exists" || fail "no demo company"
grep -qi 'demo' <<<"$ME" && pass "/api/v1/me shows the demo company" || echo "note: /api/v1/me has no 'demo' text: $ME"

echo "== up again is idempotent =="
PID1="$(grep '^api_pid=' "$ENVCTL_DIR/registry/$NAME.env" | cut -d= -f2-)"
OUT2="$("$TUT" --name "$NAME" up)"
PID2="$(grep '^api_pid=' "$ENVCTL_DIR/registry/$NAME.env" | cut -d= -f2-)"
[[ "$PID1" == "$PID2" && -n "$PID1" ]] && pass "same instance after a second up" || fail "pid changed $PID1 -> $PID2"
grep -q "already running" <<<"$OUT2" && pass "second up reports already running" || fail "second up output"
[[ "$("$TUT" --name "$NAME" address)" == "$URL" ]] && pass "address unchanged" || fail "address changed"

echo "== status and address agree =="
ST="$("$TUT" --name "$NAME" status)"
echo "$ST"
grep -q "^address:   $URL$" <<<"$ST" && pass "status address equals address" || fail "status address"
grep -q "^kind:      tutorial$" <<<"$ST" && pass "status kind" || fail "status kind"
grep -q "^state:     running$" <<<"$ST" && pass "status running" || fail "status state"
grep -Eq '^migration: [0-9]+$' <<<"$ST" && pass "status shows a migration version" || fail "status migration"

echo "== reset =="
q "$NAME" "INSERT INTO crm.customers (id, code, name) VALUES (gen_random_uuid(), 'MARKER1', 'Marker')"
[[ "$(q "$NAME" "SELECT count(*) FROM crm.customers WHERE code = 'MARKER1'")" == 1 ]] && pass "marker created" || fail "marker not created"
check "reset without --yes and without a terminal is refused" bash -c "! '$TUT' --name '$NAME' reset </dev/null"
[[ "$(q "$NAME" "SELECT count(*) FROM crm.customers WHERE code = 'MARKER1'")" == 1 ]] && pass "refused reset left the data" || fail "data lost by refused reset"
"$TUT" --name "$NAME" reset --yes >/dev/null
URL="$("$TUT" --name "$NAME" address)"
[[ "$(curl -fsS "$URL/api/v1/meta/environment" | jq -r .kind)" == tutorial ]] && pass "environment runs again after reset" || fail "not running after reset"
[[ "$(q "$NAME" "SELECT count(*) FROM crm.customers WHERE code = 'MARKER1'")" == 0 ]] && pass "marker gone after reset" || fail "marker survived reset"
[[ "$(q "$NAME" "SELECT count(*) FROM core.users WHERE email = 'admin@example.com'")" == 1 ]] && pass "demo data back after reset" || fail "no demo admin after reset"

echo "== down, then up restarts =="
"$TUT" --name "$NAME" down >/dev/null
check "address empty and non-zero when stopped" bash -c "! '$TUT' --name '$NAME' address"
check "api no longer answers" bash -c "! curl -fsS -m 2 '$URL/api/v1/meta/environment'"
grep -q "^state:     stopped$" <<<"$("$TUT" --name "$NAME" status)" && pass "status stopped" || fail "status after down"
[[ "$(q "$NAME" "SELECT count(*) FROM core.users WHERE email = 'admin@example.com'")" == 1 ]] && pass "data kept after down" || fail "data lost by down"
"$TUT" --name "$NAME" up >/dev/null
check "up after down starts it again" curl -fsS -m 3 "$(grep '^url=' "$ENVCTL_DIR/registry/$NAME.env" | cut -d= -f2-)/api/v1/meta/environment"

echo "== refusals =="
"$ENVCTL" register smoke_livereg --database "$NAME" --kind live >/dev/null
check "reset refuses a live-registered environment" bash -c "! '$TUT' --name smoke_livereg reset --yes"
check "down refuses a live-registered environment" bash -c "! '$TUT' --name smoke_livereg down"
[[ "$(q postgres "SELECT count(*) FROM pg_database WHERE datname = '$NAME'")" == 1 ]] && pass "live-registered database untouched" || fail "database dropped"
check "reset refuses an unknown name" bash -c "! '$TUT' --name tutsmoke_unknown reset --yes"

echo "== cleanup =="
"$ENVCTL" drop smoke_livereg --yes >/dev/null 2>&1 || rm -f "$ENVCTL_DIR/registry/smoke_livereg.env"
"$ENVCTL" drop "$NAME" --yes
[[ "$(q postgres "SELECT count(*) FROM pg_database WHERE datname LIKE 'tutsmoke\_%'")" == 0 ]] && pass "databases dropped" || fail "databases remain"

if ((FAILS > 0)); then echo "$FAILS check(s) failed" >&2; exit 1; fi
echo "tutorial-env smoke test passed"
