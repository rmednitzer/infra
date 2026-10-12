# Forgejo recovery and independent backup replication

## Architecture and scope

Forgejo's existing application-consistent backup runs every six hours and
retains 16 generations on the source host. Its archives include the database,
repository data and server configuration; treat them as highly sensitive.

A second root-controlled host retrieves the newest verified backup through
SSH using a dedicated key restricted by source address and a forced command.
The account is restricted by OpenSSH authorized_keys options: restrict,
from and command. Sudo permits only the zero-argument backup-stream program.
The recipient pins the source host key and refuses unexpected identities.

The source checks age and SHA-256 before transmission. The recipient verifies
SHA-256, archive decompression and source metadata before atomically promoting
complete archives into root-only recovery storage. Older replicas are removed
only after a successful transfer. Retention is 28 generations (about seven
days at the current six-hour interval).

This is cross-host recovery, not independently proven geographically off-site
resilience. The process does not update live Forgejo repositories.

## Scheduling and monitoring

- Source backup: the existing six-hourly systemd timer.
- Recipient copy: 00:48, 06:48, 12:48 and 18:48 UTC.
- Source health: hourly, with Forgejo backup validity/age metrics.
- Recipient health: hourly, with Forgejo replica validity/age metrics.
- Independent GitHub Git snapshots: daily at 04:17 UTC, hourly health checks.
- Restore drill: considered stale after 45 days.

Node Exporter textfile collectors on both hosts expose metrics. The supplied
Prometheus alert rule file describes critical missing/stale/invalid backup
alerts, and a warning for overdue restore drills. Those alert rules still
need deployment to an observed rule evaluator and notifier: a rule file by
itself does not prove that anyone is paged on failure.

## Verification evidence (2026-10-12)

A source archive was restored into a temporary Forgejo application instance
with isolated filesystem and database paths, mail, SSH and Actions disabled,
and localhost-only networking. The login route returned HTTP 200 and the
unauthenticated API returned the expected HTTP 403 access-control message.
SQLite integrity passed; restored Git passed fsck; the database contained
23 repository records. The production service was not restarted.

The replicated archive transferred to the separate recovery host passed
SHA-256 and decompression checks, and extracted SQLite/Git checks passed.
Temporary test data and the restored service were removed. Neither test
modified production repository refs or the production database.

This demonstrates application startup and basic recovery, not every external
integration, a published recovery service, or quantified RTO/RPO.

## Security boundary and rollback

No source file in this repository contains SSH private keys, internal host
addresses, authorized_keys lines or host-specific credentials.
The local root-owned Forgejo replica environment file and SSH identity are
outside Git. Verify deployed scripts against version-control checksums.

Before altering SSH allowlists, preserve the previous config; run sshd -t
and verify existing access. Revoke replication by disabling its receiving
cron, removing the limited authorized key/sudo grant, validating and
reloading SSH configuration. Keep the source backup archive unchanged.

If a drill must test corruption detection, use a disposable copy of an
archive. Do not modify or deliberately corrupt production backup sets.
Cross-host copies increase independence, but the copied archives contain
sensitive data and SSH does not encrypt them at rest. Add an independently
controlled encrypted or cross-site copy for full site-failure resilience.

## Independent GitHub main-ref drift auditing

The existing private lab repositories in Forgejo are independent, not
configured pull mirrors. Their branch refs are never force-updated by backup
jobs. A scheduled, read-only comparison fetches GitHub main refs with
Git ls-remote and compares them with local Forgejo main refs. Node Exporter
exposes one match gauge per public repository, a total match count, and a
probe-success gauge. Transient mismatch does not page an operator because
these repositories are not promised synchronous mirrors; failed remote probes
indicate that the audit itself was not completed.

Forgejo pull mirroring cannot be activated on already-existing repositories
without migration to new repository identities. Any change to establish
continuous mirroring must preserve independent Forgejo work and branch
histories through a reviewed migration plan.
