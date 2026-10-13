# Independent GitHub source recovery

## Scope and trust boundary

The eight public repositories owned by rmednitzer are captured on vertex
outside GitHub and outside the Forgejo database, at the root-owned directory
/var/backups/github-recovery (mode 0700). A daily local cron job starts at
04:17 UTC. Root runs the documented script without GitHub credentials.

Each invocation clones all advertised Git branches and tags, checks Git object
integrity, creates an independent Git bundle, verifies the bundle, compares
the captured main commit with the source, and writes a checksummed manifest.
The snapshot staging directory is only promoted to a dated snapshot after
every repository passes. Failures leave earlier snapshots intact.

Snapshots DO NOT include GitHub issues, PR discussions, wiki content, release
attachments, GitHub Actions logs, Git LFS objects, permissions or secrets.
Do not represent a snapshot as a complete GitHub platform backup. Forgejo's
separate application-consistent six-hourly backup covers its own application
state, not GitHub-hosted metadata.

The eight lab repositories in Forgejo are GitHub-authoritative replicas.
A separate scoped replication job maintains their branches and tags using
verified preservation bundles and leased atomic updates. This recovery snapshot
script never updates live repositories. See
[the replication contract](github-forgejo-replication.md); its Git-only scope
and destination access policies remain distinct from GitHub's.

## Deployment and verification

On vertex, install scripts/github-recovery-snapshot.sh as
/usr/local/sbin/github-recovery-snapshot, owned by root with mode 0750.
Install ops/github-recovery.cron as /etc/cron.d/github-recovery, owned by root
with mode 0644; verify cron is enabled. Do not store an authentication token.

Invoke the installed snapshot script once with root permissions and verify
the resulting manifest, eight bundle SHA-256 digests and main commit IDs.
A recovery drill must run without GitHub network access:

1. Select a completed dated snapshot with manifest.json and SHA256SUMS.
2. Verify SHA256SUMS before reading the bundles.
3. For every repository, clone the bundle into a temporary bare Git repository.
4. Run git fsck --full and check restored refs/heads/main against manifest.json.
5. Preserve the result and test time as evidence; remove the isolated test
   repositories after verification.

Cron output is appended to /var/log/github-recovery-snapshot.log. A script
failure returns nonzero but the cron configuration itself does not notify an
operator; monitor its successful snapshot freshness independently. Keep at most 90 complete daily snapshots. The script prunes older generations
only after an entire new capture was verified and atomically promoted.
Monitor available disk capacity independently.

## Current verification boundary

A 2026-10-12 recovery drill restored all eight Git bundles independently on
vertex and verified main commit IDs and object integrity. The separate Forgejo
backup's compressed checksum, SQLite integrity and a restored Git repository
were verified on svr-01 without stopping the application. A full Forgejo
application-level restore and cross-host backup replication have not yet been
demonstrated. Do not assume a tested disaster-recovery RTO/RPO from these tests.
