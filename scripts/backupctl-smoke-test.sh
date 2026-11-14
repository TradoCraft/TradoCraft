#!/usr/bin/env bash
# Smoke test for scripts/backupctl (ADR 0056): back up a throwaway server holding large bytea
# values, verify the backup (point in time, every row readable), detect a damaged archive, apply
# the retention rule, and restore and start a drill copy.
#
# Needs the PostgreSQL server programs (initdb, pg_ctl, postgres, pg_basebackup, pg_verifybackup;
# SMOKE_PG_BIN or found like backupctl does) and must run as a non-root user (PostgreSQL refuses
# root), e.g. `sudo -u postgres scripts/backupctl-smoke-test.sh`. No Docker, no API build.
# shellcheck disable=SC2015,SC2010,SC2012  # pass never fails; the test names every file itself
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUPCTL="$ROOT/scripts/backupctl"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/backupctl-smoke.XXXXXX")"
PORT="${SMOKE_PG_PORT:-55481}"
DRILL_PORT="${SMOKE_DRILL_PORT:-55482}"
FAILS=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
check() { # check "description" command...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}

[[ "$(id -u)" != 0 ]] || { echo "run as a non-root user (e.g. sudo -u postgres $0)" >&2; exit 2; }

PG_BIN="${SMOKE_PG_BIN:-}"
if [[ -z "$PG_BIN" ]]; then
  for d in "$(dirname "$(command -v pg_ctl 2>/dev/null || echo /x/x)")" /usr/lib/postgresql/*/bin; do
    [[ -x "$d/initdb" && -x "$d/pg_ctl" ]] && PG_BIN="$d"
  done
fi
[[ -n "$PG_BIN" ]] || { echo "no PostgreSQL server programs found: set SMOKE_PG_BIN" >&2; exit 2; }
export PATH="$PG_BIN:$PATH" BACKUP_PG_BIN="$PG_BIN"

SRC="$WORK/src"
DRILL="$WORK/drill"
cleanup() {
  pg_ctl -D "$DRILL" -m immediate stop >/dev/null 2>&1 || true
  pg_ctl -D "$SRC" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# A source server with password authentication, like a real one.
echo s3cret-Pw9 >"$WORK/pw"
initdb -D "$SRC" -U tradocraft --pwfile="$WORK/pw" --auth=scram-sha-256 >/dev/null
pg_ctl -D "$SRC" -l "$WORK/src.log" -w -o "-c listen_addresses=127.0.0.1 -c port=$PORT -c unix_socket_directories='$WORK'" start >/dev/null
export PGPASSWORD=s3cret-Pw9
q() { psql -X -q -t -A -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PORT" -U tradocraft -d "$1" -c "$2"; }
q postgres "CREATE DATABASE tradocraft"
q tradocraft "CREATE TABLE _sqlx_migrations (version bigint PRIMARY KEY, success boolean NOT NULL);
  INSERT INTO _sqlx_migrations VALUES (20270126000001, true);
  CREATE SCHEMA core;
  CREATE TABLE core.companies (id int); INSERT INTO core.companies VALUES (1);
  CREATE TABLE core.users (id int); INSERT INTO core.users VALUES (1), (2);
  CREATE TABLE files (id serial PRIMARY KEY, body bytea NOT NULL);
  ALTER TABLE files ALTER body SET STORAGE EXTERNAL;
  INSERT INTO files (body) SELECT decode(string_agg(md5(i::text || g::text), ''), 'hex')
    FROM generate_series(1, 3) g, generate_series(1, 200000) i GROUP BY g;"
unset PGPASSWORD

export BACKUPCTL_CONFIG=/dev/null BACKUP_DIR="$WORK/backups"
export DATABASE_URL="postgresql://tradocraft:s3cret-Pw9@127.0.0.1:$PORT/tradocraft"
unset BACKUP_EXEC BACKUP_KEEP_DAILY BACKUP_KEEP_WEEKLY BACKUP_KEEP_MONTHLY

# --- backup ---
OUT="$("$BACKUPCTL" backup 2>&1)" && pass "backup succeeds" || { fail "backup succeeds"; echo "$OUT" >&2; }
ID="$(ls "$BACKUP_DIR" | grep -E '^[0-9]{8}T[0-9]{6}Z$' | head -n1 || true)"
check "backup directory with archive and description" test -s "$BACKUP_DIR/$ID/base.tar.gz" -a -s "$BACKUP_DIR/$ID/backup.info"
check "migration recorded" grep -qx "migration=20270126000001" "$BACKUP_DIR/$ID/backup.info"
check "password not in the description" bash -c "! grep -q s3cret-Pw9 '$BACKUP_DIR/$ID/backup.info'"
check "password not in the output" bash -c "! grep -q s3cret-Pw9 <<<'$OUT'"
check "archive is private" test "$(stat -c %a "$BACKUP_DIR/$ID/base.tar.gz")" = 600
check "no partial directory left" bash -c "! ls -a '$BACKUP_DIR' | grep -q partial"

# Changes after the backup must not be in it.
PGPASSWORD=s3cret-Pw9 q tradocraft "INSERT INTO files (body) VALUES ('\\x00'); INSERT INTO core.users VALUES (3)"

# --- verify ---
OUT="$("$BACKUPCTL" verify latest 2>&1)" && pass "verify succeeds" || { fail "verify succeeds"; echo "$OUT" >&2; }
check "verify reads every row" grep -q "reading every row of database tradocraft" <<<"$OUT"
check "verify reports the point in time (2 users, not 3)" grep -q "companies 1, users 2" <<<"$OUT"
check "verification recorded" grep -qx "verify_result=ok" "$BACKUP_DIR/$ID/backup.info"
check "list shows the verification" bash -c "'$BACKUPCTL' list | grep '$ID' | grep -q ok"
OUT="$("$BACKUPCTL" verify "$ID" --amcheck 2>&1)" && pass "verify --amcheck succeeds" || { fail "verify --amcheck succeeds"; echo "$OUT" >&2; }

# --- a damaged archive is detected ---
BAD="20200101T000000Z"
cp -a "$BACKUP_DIR/$ID" "$BACKUP_DIR/$BAD"
printf 'damage' | dd of="$BACKUP_DIR/$BAD/base.tar.gz" bs=1 seek=4096 conv=notrunc 2>/dev/null
check "damaged archive fails verification" bash -c "! '$BACKUPCTL' verify $BAD"
check "failure recorded" grep -qx "verify_result=failed" "$BACKUP_DIR/$BAD/backup.info"
# A checksum that matches but content that does not (e.g. damaged before the checksum was taken):
# the manifest check catches it.
BAD2="20200102T000000Z"
mkdir -p "$WORK/repack" && tar -xzf "$BACKUP_DIR/$ID/base.tar.gz" -C "$WORK/repack"
printf 'damage' | dd of="$WORK/repack/PG_VERSION" bs=1 seek=0 conv=notrunc 2>/dev/null
mkdir -p "$BACKUP_DIR/$BAD2"
tar -czf "$BACKUP_DIR/$BAD2/base.tar.gz" -C "$WORK/repack" .
sed "s/^sha256=.*/sha256=$(sha256sum "$BACKUP_DIR/$BAD2/base.tar.gz" | cut -d' ' -f1)/" "$BACKUP_DIR/$ID/backup.info" >"$BACKUP_DIR/$BAD2/backup.info"
check "manifest check catches altered files" bash -c "! '$BACKUPCTL' verify $BAD2"
rm -rf "${BACKUP_DIR:?}/$BAD" "${BACKUP_DIR:?}/$BAD2" "$WORK/repack"

# --- restore and drill ---
OUT="$("$BACKUPCTL" restore latest "$DRILL" --start --port "$DRILL_PORT" 2>&1)" && pass "restore --start succeeds" || { fail "restore --start succeeds"; echo "$OUT" >&2; }
check "drill copy answers with the source password and the backup's data" \
  test "$(PGPASSWORD=s3cret-Pw9 psql -X -t -A -h 127.0.0.1 -p "$DRILL_PORT" -U tradocraft -d tradocraft -c 'SELECT count(*) FROM files' 2>/dev/null)" = 3
check "drill copy does not archive WAL" \
  test "$(PGPASSWORD=s3cret-Pw9 psql -X -t -A -h 127.0.0.1 -p "$DRILL_PORT" -U tradocraft -d tradocraft -c 'SHOW archive_mode' 2>/dev/null)" = off
pg_ctl -D "$DRILL" -m fast stop >/dev/null
check "restore refuses a non-empty target" bash -c "! '$BACKUPCTL' restore latest '$DRILL'"
check "restore refuses an unknown id" bash -c "! '$BACKUPCTL' restore 20000101T000000Z '$WORK/none'"

# --- retention ---
# Fake backups over 400 days (description and archive only; prune does not open them).
mkdir -p "$WORK/fake"
for days in $(seq 0 400); do
  for hour in 02 14; do
    fid="$(date -u -d "2026-01-31 - $days days" +%Y%m%d)T${hour}0000Z"
    mkdir -p "$WORK/fake/$fid"
    : >"$WORK/fake/$fid/base.tar.gz"
    echo "id=$fid" >"$WORK/fake/$fid/backup.info"
  done
done
mkdir -p "$WORK/fake/.20260131T150000Z.partial"
export BACKUP_KEEP_DAILY=7 BACKUP_KEEP_WEEKLY=4 BACKUP_KEEP_MONTHLY=6
"$BACKUPCTL" --dir "$WORK/fake" prune --dry-run >/dev/null
check "dry run removes nothing" test "$(ls "$WORK/fake" | wc -l)" = 802
"$BACKUPCTL" --dir "$WORK/fake" prune >/dev/null
KEPT="$(ls "$WORK/fake" | tr '\n' ' ')"
check "newest backup kept" grep -q "20260131T140000Z" <<<"$KEPT"
check "only the newest of a day is kept" bash -c "! grep -q 20260131T020000Z <<<'$KEPT'"
check "7 daily backups (Jan 25-31)" test "$(ls "$WORK/fake" | grep -c '^2026012[5-9]\|^2026013')" = 7
check "6 monthly backups reach back to August 2025" grep -q "^20250831T140000Z\| 20250831T140000Z" <<<"$KEPT"
check "nothing older than six months" bash -c "! grep -q ' 202507\|^202507' <<<'$KEPT'"
# Days Jan 25-31 (7), weeks W02-W04 ending Jan 18/11 (+ Jan 25 week already counted) and months.
check "kept set is small" test "$(ls "$WORK/fake" | wc -l)" -le 17
check "crashed partial removed" test ! -e "$WORK/fake/.20260131T150000Z.partial"

# --- configuration errors ---
check "missing BACKUP_DIR fails" bash -c "! env -u BACKUP_DIR '$BACKUPCTL' list"
check "bad retention value is refused" bash -c "! BACKUP_KEEP_DAILY=x '$BACKUPCTL' list"

echo
if ((FAILS)); then echo "$FAILS check(s) failed"; exit 1; fi
echo "all checks passed"
