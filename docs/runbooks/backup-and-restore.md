# Runbook: backup and restore (backupctl)

See [ADR 0053](../adr/0053-backup-and-restore.md). `scripts/backupctl` takes physical backups of
the whole PostgreSQL server (every database, roles and passwords, and all attachments and photos,
which are stored in the database). It keeps them by a retention rule, verifies them by restoring
them, and restores them.

| | Default |
|---|---|
| Frequency | one backup a day (cron or systemd timer, below) |
| Kept | newest of each of the last 7 days, 4 weeks and 6 months (about 17 backups) |
| Verified | every week, and always before a restore |
| Data loss after a disaster | up to one day (the time since the last backup) |

## Set up

Needs bash, `tar`, `gzip`, `sha256sum`, GNU `date` and the PostgreSQL client programs. For
`verify` and `restore` it also needs the server programs (`pg_ctl`, `postgres`, `pg_verifybackup`)
of the same major version as the server, in `PATH`, `/usr/lib/postgresql/<major>/bin` or
`BACKUP_PG_BIN`.

Settings go in the environment or a config file (`--config FILE`, `$BACKUPCTL_CONFIG`, `./.env`; the
file is read for the known keys only, never executed):

```bash
BACKUP_DIR=/srv/tradocraft-backups          # required; on another disk than the database
DATABASE_URL=postgresql://tradocraft:PASSWORD@db-host:5432/tradocraft
# BACKUP_KEEP_DAILY=7  BACKUP_KEEP_WEEKLY=4  BACKUP_KEEP_MONTHLY=6
```

The user in `DATABASE_URL` needs the `REPLICATION` attribute (a superuser has it), and
`pg_hba.conf` must allow it a replication connection from the backup host, for example
`host replication tradocraft 10.0.0.5/32 scram-sha-256`. The database in the URL is the
application database: its latest migration is recorded and checked on verify.

Run backups as a dedicated non-root user that owns `BACKUP_DIR`. `verify` cannot run as root,
because PostgreSQL refuses to.

### Docker Compose

`BACKUP_EXEC` runs `pg_basebackup` and `psql` inside the database container over its local socket.
No replication port or `pg_hba.conf` change is needed, because the `postgres` image trusts local
socket connections. Only the user and database name are taken from `DATABASE_URL`:

```bash
cd /srv/tradocraft          # the directory with docker-compose.yml
BACKUP_DIR=/srv/tradocraft-backups BACKUP_EXEC="docker compose exec -T db" \
  DATABASE_URL=postgresql://tradocraft@db/tradocraft scripts/backupctl backup
```

To verify or restore without installing PostgreSQL on the host, run `backupctl` in the same image
as the server (`postgres:16`). Use your own non-root user id, the one that owns the backups:

```bash
docker run --rm --user "$(id -u):$(id -g)" -e BACKUP_DIR=/backups -e BACKUPCTL_CONFIG=/dev/null \
  -v /srv/tradocraft-backups:/backups -v "$PWD/scripts:/scripts:ro" \
  postgres:16 /scripts/backupctl verify latest
```

## Daily backup and weekly verification

```bash
scripts/backupctl backup            # backup, then prune by the retention rule
scripts/backupctl list              # id, size, migration, last verification, retention
scripts/backupctl verify latest     # restore into a throwaway directory and check it
scripts/backupctl prune --dry-run   # what the retention rule would remove
```

Cron (as the backup user). `MAILTO` sends the output of a failed run, so make sure the host can
deliver mail:

```cron
MAILTO=ops@example.com
BACKUPCTL_CONFIG=/srv/tradocraft/backup.env
# 02:17 every night; verify on Sundays at 04:43
17 2 * * *  /srv/tradocraft/scripts/backupctl backup >/dev/null
43 4 * * 0  /srv/tradocraft/scripts/backupctl verify latest >/dev/null
```

Both commands exit non-zero on failure, so the same lines work with a systemd timer and
`OnFailure=`. Also check `backupctl list` now and then: the newest backup should be from today
and the latest verification `ok`.

### What verify checks

1. The SHA-256 of the archive matches the one recorded when it was taken (damage on disk or in a
   copy).
2. `pg_verifybackup`: every file matches the backup manifest, and the WAL is complete.
3. PostgreSQL starts on the copy and replays that WAL. The copy has no network listener, uses a
   private socket, and has archiving off.
4. The application database exists, its latest migration matches the recorded one, and no
   migration failed.
5. Every row of every database can be read, including attachments (`pg_dump` to `/dev/null`).
6. With `--amcheck`: tables and indexes are consistent (`pg_amcheck --heapallindexed`; slower).

It prints the number of companies and users and the last worker heartbeat (the latest moment the
data shows), and records `ok` or `failed` in `backup.info`. It needs free disk space for one
unpacked copy in `$TMPDIR`; point `TMPDIR` elsewhere if `/tmp` is small.

## Off-site copies

A backup on the same machine does not survive losing the machine. Copy `BACKUP_DIR` elsewhere
after the nightly backup, for example `rsync -a --delete /srv/tradocraft-backups/
backup-host:/srv/tradocraft-backups/`, or use restic or rclone. A backup holds all business data and
the password hashes, so encrypt it wherever it is not on your own disk. A packaged PostgreSQL
(Debian, RHEL) keeps `postgresql.conf` and `pg_hba.conf` in `/etc`, outside the backup, so back
those up with the host. Also keep `docker-compose.yml` and the API and worker settings (`.env`):
they are not in the database.

## Restore drill (test a backup in the app)

Do this after setting up backups and then every few months. It brings a backup up next to live
and opens it in the app as a test environment, without any risk of sending mail:

```bash
scripts/backupctl restore latest /srv/restore-drill --start --port 55432
# The copy runs on 127.0.0.1:55432 with the same users and passwords as the source.
scripts/envctl --database-url postgresql://tradocraft:PASSWORD@127.0.0.1:55432/postgres \
  clone tradocraft restore_drill --kind test
# In the app: add the printed address as an environment (amber "test" banner), sign in, and check
# recent quotations, orders, tickets and that attachments and photos open.
scripts/envctl --database-url postgresql://tradocraft:PASSWORD@127.0.0.1:55432/postgres drop restore_drill
/usr/lib/postgresql/16/bin/pg_ctl -D /srv/restore-drill stop && rm -rf /srv/restore-drill
```

`envctl clone` makes the instance a `test` environment: mail goes to files, the mailbox is not
polled, and portal links and sessions are removed ([ADR 0048](../adr/0048-environment-clones-and-outbound-safety.md)).
Never point the live API or worker at a drill copy.

## Restore after a disaster

Use this when the database is lost or damaged, or when you must go back to the state of a backup.
Everything entered after that backup is lost, so tell the users which moment they get back (the
time of the backup, and the last worker heartbeat that `verify` prints).

1. **Stop everything that writes:** the API, the portal server and the worker
   (`docker compose stop api portal-api worker`), so nobody keeps working on data that is about
   to be replaced.
2. **Choose and verify the backup:** `backupctl list`, then `backupctl verify <ID>`. If it fails,
   take the next older one.
3. **Stop PostgreSQL and keep the old data directory.** Do not delete it until the restore works:
   - Packaged server: `systemctl stop postgresql`, then
     `mv /var/lib/postgresql/16/main /var/lib/postgresql/16/main.broken`.
   - Docker Compose: `docker compose stop db`, copy the volume out (`docker run --rm -v
     tradocraft_pgdata:/from -v /srv/pgdata-broken:/to debian cp -a /from/. /to/`), then
     `docker compose rm -f db && docker volume rm tradocraft_pgdata`. The volume name is
     `<project>_pgdata`; see `docker volume ls`.
4. **Restore into the empty location:**
   - Packaged server, as the postgres user:
     `sudo -u postgres BACKUP_DIR=/srv/tradocraft-backups scripts/backupctl restore <ID> /var/lib/postgresql/16/main`.
     The configuration in `/etc/postgresql` stays as it was.
   - Docker Compose: recreate the empty volume through the database service and restore into it
     as the image's postgres user:

     ```bash
     docker compose run --rm --no-deps --user postgres -e BACKUP_DIR=/backups -e BACKUPCTL_CONFIG=/dev/null \
       -v /srv/tradocraft-backups:/backups -v "$PWD/scripts:/scripts:ro" --entrypoint /scripts/backupctl \
       db restore <ID> /var/lib/postgresql/data
     ```

     The postgres user must be able to read the backups (for example `chmod -R o+rX` for the
     duration, or `chown 999` on a copy).
5. **Start PostgreSQL** (`systemctl start postgresql` / `docker compose up -d db`). It replays the
   backup's WAL and opens. The log shows `database system is ready to accept connections`.
6. **Start the API and the portal server, not the worker yet.** The API applies newer migrations at
   boot if the code is newer than the backup. Check recent records and attachments in the app.
7. **Decide about queued mail.** Mail that was waiting in the backup is sent again when the worker
   starts, even though live may already have sent it after the backup was taken. List it:

   ```sql
   SELECT 'system' AS kind, id, to_address AS recipient, subject, created_at
     FROM core.mail_outbox WHERE delivery = 'queued'
   UNION ALL
   SELECT 'ticket', id, array_to_string(to_addresses, ', '), subject, created_at
     FROM helpdesk.articles WHERE delivery = 'queued'
   ORDER BY created_at;
   ```

   If it was most likely sent already (the backup is more than a few minutes older than the
   failure), cancel it the way a clone does:

   ```sql
   UPDATE core.mail_outbox  SET delivery = 'failed', delivery_error = 'cancelled: restore' WHERE delivery = 'queued';
   UPDATE helpdesk.articles SET delivery = 'failed', delivery_error = 'cancelled: restore' WHERE delivery = 'queued';
   ```

8. **Start the worker.** It records the gap since the last heartbeat in the backup as an outage and
   mails the administrators (ADR 0052). That is expected after a restore.
9. **Take a new backup** (`backupctl backup`), then delete the old data directory once you are sure.

## Troubleshooting

- `must be superuser or replication role` or `no pg_hba.conf entry for replication connection`:
  see Set up. With Docker Compose use `BACKUP_EXEC`.
- `requested WAL segment ... has already been removed`: the server recycled WAL during the backup.
  Raise `wal_keep_size` (for example `ALTER SYSTEM SET wal_keep_size = '1GB'; SELECT
  pg_reload_conf();`) and run the backup again. Nothing was kept from the failed run.
- `no PostgreSQL 16 server programs`: install the server package of that version (only the
  programs are needed, not a running service), set `BACKUP_PG_BIN`, or use the Docker command above.
- `another backupctl backup or prune is running`: a previous run still holds the lock in
  `BACKUP_DIR/.lock`. Wait for it to finish; the lock is released when the process exits.
- After a PostgreSQL major upgrade, take a new backup at once. Older backups need the old
  version's programs to verify or restore (`BACKUP_PG_BIN`).
- `scripts/backupctl-smoke-test.sh` checks the tool end to end against a throwaway server
  (`sudo -u postgres scripts/backupctl-smoke-test.sh`; no Docker needed).
