# 0053 — Backup and restore: physical base backups, retention, verified restores

**Status:** Accepted

**Context.** tradocraft keeps everything in one PostgreSQL server: the business data, and also every
attachment, photo, stored e-mail and signature as `bytea` (ADR 0048: there is no file storage
outside the database). Nothing in the repository took or tested a backup, so each installation
improvised one, and an untested backup is not known to restore. Roadmap item D2.

A logical backup (`pg_dump`) is what `envctl clone` uses, and it is the wrong tool for this job
while files live in the database. It reads and re-encodes every large value through the SQL
layer, so a dump and especially a restore of a database that is mostly attachments are slow
(the restore rebuilds every index too). It holds one long transaction for the whole dump, which
keeps vacuum from cleaning up on a busy server. And it covers one database, not the roles and
their passwords.

**Decision.** `scripts/backupctl` takes physical backups with `pg_basebackup`, applies a retention
rule, and restores and verifies them. The runbook is
[docs/runbooks/backup-and-restore.md](../runbooks/backup-and-restore.md).

*Backup.* `pg_basebackup -D - -F tar -X fetch -c fast --manifest-checksums=SHA256`, compressed with
gzip, into `BACKUP_DIR/<UTC timestamp>/base.tar.gz`. One file holds the whole server (every
database, the roles, the configuration files that live in the data directory), the WAL needed to
make it consistent, and the backup manifest. Copying files is fast regardless of what is in them,
and the backup does not hold a transaction open on the server. Writing tar to stdout makes the
command identical on the host and through a command prefix (`BACKUP_EXEC="docker compose exec -T
db"`), so the Docker Compose setup needs no replication port or `pg_hba.conf` change: the
container's local socket is used. Next to the archive, `backup.info` (key=value) records the
server version, the user, the application database, its latest migration, the size and the
SHA-256 of the archive. The backup is written to a hidden `.partial` directory and renamed when
complete, so a crash never leaves something that looks like a backup. Archives are mode 600 and
`BACKUP_DIR` mode 700: a backup holds all data and the password hashes. A lock prevents two
backups, or a backup and a prune, from running at once.

*Retention.* Grandfather-father-son. Kept: the newest backup, the newest backup of each of the last
`BACKUP_KEEP_DAILY` days (default 7), ISO weeks (default 4) and months (default 6). Periods are
counted from the backups that exist, not from the calendar, so when backups stop (a broken cron
job, a server that is down), pruning never deletes the last good ones. Pruning runs after every
backup; `prune --dry-run` and `list` show what would go.

*Verify.* `backupctl verify [ID|latest]` is the restore test. It checks the archive's SHA-256,
unpacks it into a throwaway directory, runs `pg_verifybackup` against the manifest, and starts
PostgreSQL on the copy with no TCP listener, a private socket directory, its own `pg_hba.conf`
(trust on that socket only) and `archive_mode=off` (a copy must never write into the live WAL
archive). Starting replays the backup's WAL, so a backup whose WAL is incomplete fails here.
Then it checks that the application database exists, that its latest migration matches the one
recorded at backup time and none failed, and reads every row of every database (`pg_dump` to
`/dev/null`), which proves that the out-of-line `bytea` values (TOAST) can be read back. With
`--amcheck` it also runs `pg_amcheck --heapallindexed`. It prints the row counts of companies and
users and the last worker heartbeat (ADR 0052) as "data as of". The result is written into
`backup.info` and shown by `list`. It needs the server programs of the same major version
(`BACKUP_PG_BIN`) and refuses to run as root, as PostgreSQL does.

*Restore.* `backupctl restore ID TARGET_DIR` checks the archive's checksum and unpacks it into a
new or empty directory, then checks it against the manifest. It never touches an existing data
directory: the operator stops the server and moves the old directory aside, so a failed restore
cannot destroy what was there. Starting the server on the directory performs the recovery; the
API then applies any newer migrations at boot. With `--start --port P` the copy runs on
`127.0.0.1:P` with archiving off: a restore drill. `envctl clone` against that server
(`--database-url`) gives a test environment with outbound mail off and credentials scrubbed (ADR
0048), where people can check the restored data in the app. That is how a restore is tested
against a clone ([ADR 0043](0043-environments.md)) without risking a mail to a real customer.

*Not built.* Continuous WAL archiving and point-in-time recovery: with daily backups, up to a day of
work can be lost. It needs an archive destination and its own monitoring, and is the next step when
that is too much; `backupctl` already turns archiving off on every copy it starts, so it stays safe
to use alongside archiving. Off-site copies and encryption at rest are left to the host's tooling
(rsync, rclone, restic) and described in the runbook. Logical exports with `pg_dump` remain the
tool for clones and for moving between major versions.

**Consequences.**

* A backup can only be restored onto the same PostgreSQL major version (and architecture). A major
  upgrade needs a fresh backup taken right after it; older backups need the old version's programs
  to verify or restore, which `BACKUP_PG_BIN` allows.
* `-X fetch` copies the WAL at the end of the backup. On a busy server WAL can be recycled before
  that; the backup then fails, nothing is kept, and the fix is a higher `wal_keep_size`.
* Tablespaces outside the data directory are not supported by tar-to-stdout; tradocraft does not
  create any.
* A packaged server (Debian, RHEL) keeps `postgresql.conf` and `pg_hba.conf` in `/etc`, so they are
  not in the backup. The runbook says to back them up with the host. `verify` and a drill write
  minimal ones so the copy can start.
* Verification costs a full read of the data and temporary disk space for one unpacked copy. Run it
  weekly, and always before relying on a backup.
* `scripts/backupctl-smoke-test.sh` tests backup, point in time, damage detection (archive checksum
  and manifest), retention and the drill against a throwaway server (`initdb`). It needs no Docker
  and no API build.
