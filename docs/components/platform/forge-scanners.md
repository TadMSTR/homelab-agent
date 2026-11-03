# osv-scanner offline DB refresh

Daily root cron job that refreshes osv-scanner's offline vulnerability database. The
security prescan, which runs the host's installed scanners over the files a build changed,
scans dependency manifests with `osv-scanner --offline` against this database, so no scan
reaches the network.

- **Cron file:** `/etc/cron.d/osv-scanner-db` (added 2026-10-31)
- **Schedule:** system cron, daily at 04:17 (`17 4 * * *`), as root
- **Database:** `/var/lib/forge-scanners/osv`
- **Log:** `/var/log/osv-scanner-db.log`
- **Timeout:** 30 minutes (`timeout 1800`)
- **No listening port**: a batch job

## Why the DB is root-owned

The offline DB is a trust input. A scanner reading a DB someone has edited can report a
vulnerable package as clean, with exit 0 and nothing on stderr. So the DB is written only by
root, and the prescan refuses to trust it unless it's root-owned and not group- or
other-writable.

The same rule covers everything the cron line runs or reads. It calls only `/usr/bin/env`,
`/usr/bin/timeout`, `/usr/local/bin/osv-scanner`, `/usr/bin/find` and `/usr/bin/chmod`,
against root-owned files. It runs no script from a user's home directory and no
Healthchecks wrapper, because a root job that runs an agent-writable file is a privilege
escalation.

## How It Works

1. Starts with an empty environment (`env -i`): `PATH=/usr/bin:/bin`, a private `HOME` and
   `TMPDIR` under `/var/lib/forge-scanners`, `LANG=C.UTF-8`, and
   `OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY` pointing at the DB.
2. Runs `osv-scanner scan source --offline-vulnerabilities --download-offline-databases`
   over one seed manifest per ecosystem the repos use. `--download-offline-databases` only
   fetches the ecosystems of the manifests it scans, which is why the seeds exist.
3. Passes a root-owned empty config (`--config .../empty.toml`) and `--no-ignore`, so no
   config file or ignore list can change what it reads. `--call-analysis` is never passed.
4. Opens the DB directories to 0755 with `find ... -exec chmod 0755`. osv-scanner creates
   them 0750, which the non-root scanning user can't enter. The files are already 0644.

The two steps are joined with `;`, not `&&`. The seed manifests contain known advisories,
so the seed scan always exits 1, and the chmod has to run anyway.

## Configuration

| Setting | Value |
|---------|-------|
| DB directory | `/var/lib/forge-scanners/osv` |
| Seed manifests | `/var/lib/forge-scanners/osv-seed/requirements.txt` (PyPI), `/var/lib/forge-scanners/osv-seed/package-lock.json` (npm) |
| Empty config | `/var/lib/forge-scanners/osv-seed/empty.toml` |
| Private HOME / TMPDIR | `/var/lib/forge-scanners/home`, `/var/lib/forge-scanners/tmp` |
| Output | `--format json`, to the log |

A new ecosystem in the repos needs a new seed manifest, added by root, and a new `-L` on the
cron line. Until then the prescan reports that ecosystem as a coverage gap.

## Dependencies

- **osv-scanner** at `/usr/local/bin/osv-scanner`, root-owned
- **Network access** to the OSV database downloads, for this job only. The scans that read
  the DB run offline
- **Depended on by:** the security prescan, which reads the DB as a non-root user

## Liveness

The job has no Healthchecks ping and sends no alert. Its liveness signal is the prescan's
freshness check: the prescan records a coverage gap when the DB isn't root-owned, lacks an
ecosystem a scanned manifest needs, or is older than 48 hours. A refresh that stopped
running shows up there within two days, as a gap, never as a clean scan.

## Operations

```bash
# Last run's output
sudo tail -50 /var/log/osv-scanner-db.log

# DB age and ownership, per ecosystem
sudo find /var/lib/forge-scanners/osv -name all.zip -printf '%TY-%Tm-%Td %TH:%TM  %u:%g %m  %p\n'

# Directories the scanning user can't enter (expect no output)
sudo find /var/lib/forge-scanners/osv -type d ! -perm 0755
```

To refresh by hand, run the command from the cron line as root. Don't run osv-scanner
against the DB as a non-root user with `--download-offline-databases`: a DB written by
anyone but root fails the prescan's ownership check.

## Related Docs

- [snapshot-monitoring.md](snapshot-monitoring.md), [disk-space-probe.md](disk-space-probe.md):
  other scheduled host jobs in this category
