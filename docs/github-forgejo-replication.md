# GitHub-authoritative Forgejo replicas

## Ownership and boundary

GitHub is the source of truth for the eight public repositories represented in
Forgejo's `lab` organization. These are ordinary private Forgejo repositories
receiving scheduled pushes, rather than native pull mirrors. Operators should
submit changes to GitHub; the replica is a read and recovery surface.

The separate MCP-to-Forgejo sync remains a fast-forward-only committed-state
backup. It does not use the replica deploy keys and is not changed by this job.
GitHub recovery bundles and application-consistent Forgejo backups remain
separate recovery controls. This replication copies Git branches and tags,
not issues, PR discussions, release attachments, access policy or Actions state.

The installed executable is `/usr/local/sbin/github-forgejo-replica-sync`.
Its reviewed source is `scripts/github-forgejo-replica-sync.py` in this repository.
The compatibility entry point formerly used by the MCP checkout delegates to
this executable. Host-specific endpoints and private keys remain outside Git.

## Credential and update contract

The root-owned configuration `/etc/github-forgejo-replica/config.json` contains
an explicit repository allowlist and `authoritative: true`. Every repository
has its own write-enabled Forgejo deploy key. A key cannot read or write a
different private repository. The service runs as `mcp`; keys and host pins are
root-owned and readable by that service group. SSH ignores inherited config,
agents and administrator identities, and requires the pinned host key.

The timer retains its four runs per day, with up to ten minutes of scheduling
jitter. A nonblocking file lock rejects overlapping executions. Git operations
have 90-second deadlines and the service has a 15-minute execution limit.

For each configured repository the job:

1. Captures the GitHub branch and tag set into local staging.
2. Refuses to proceed if source `main` is missing.
3. Reads the current Forgejo branch and tag set.
4. If an update is needed, clones the destination into an isolated workspace.
5. Creates a complete advertised-ref bundle before updating existing refs.
6. Restores that bundle into a disposable bare repository and verifies every
   captured ref plus Git object integrity.
7. Writes a checksummed recovery receipt before submitting the update.
8. Pushes all changed refs atomically, with an exact destination-SHA lease for
   each creation, update or deletion.
9. Reads the destination again and requires exact branch/tag equality with
   the captured GitHub source set.

Thus a source rewrite or removal can change the replica, but its prior Git
state is preserved first. Concurrent destination changes cause lease rejection;
the job does not silently overwrite them. An interrupted push is reconciled by
reading the destination and is never automatically retried within that run.
Atomicity is per repository, not across the entire eight-repository fleet.

An empty destination has no prior refs to preserve. A bundle is not a full
Forgejo application backup and does not include LFS object bytes. Repository
branch/tag protections and GitHub required-check policies are not replicated.
The existing unprotected destination refs permit the designated replication
writer; do not claim the two hosts have equivalent access policies.

## Verification and monitoring

On the execution host, an operator with root access runs:

```sh
sudo /usr/local/sbin/github-forgejo-replica-sync --check-config
sudo systemd-analyze verify /etc/systemd/system/lab-mirror-sync.service
sudo systemctl start --no-block lab-mirror-sync.service
sudo systemctl show lab-mirror-sync.service -p Result -p ExecMainStatus
sudo cat /var/lib/github-forgejo-replica/latest.json
sudo cat /var/lib/node_exporter/textfile_collector/github_forgejo_replica.prom
```

Do not infer completion from `start --no-block`: wait for terminal service
status and check the receipt. Success requires all eight repository results to
be true and independently read destination refs to equal the captured sources.

A root-owned `ExecStopPost` publisher validates the receipt and atomically
publishes metrics. The sync process cannot write unrelated collector files.
VMAlert evaluates failed runs, failed repositories and missing/stale success
timestamps; eight hours is the stale threshold for the six-hour schedule.
The legacy source-host ref comparison remains supplementary and may legitimately
show lag between scheduled runs. It is not the replication completion signal.

Verify credential boundaries separately: each new key must authorize its own
repository's receive-pack service and reject access to another private replica.
Do not test by writing synthetic refs to a production repository.

## Failure and recovery

Recovery bundles and receipts are under
`/var/lib/github-forgejo-replica/recovery/<run-id>/`. The job never prunes these
archives. Operators must manage retention separately after checking required
recovery history. Less than 1 GiB free space prevents new updates; existing
filesystem monitoring remains necessary.

If a run fails, inspect its receipt and service journal. A partial fleet run can
leave some repositories updated and others unchanged. Do not repeat an unknown
push before reading the current destination refs and original receipt.

To restore prior refs, first stop the replica timer and confirm its service is
inactive. Verify the recorded bundle SHA-256, then clone the bundle into an
isolated bare repository and run `git fsck --full`. Compare every restored ref
against the receipt before preparing an explicit restoration manifest. Restoring
production refs is a separate consequential operation; a restored local clone
alone does not prove that production was restored. Keep the timer disabled until
the source-of-truth decision is reconciled, otherwise the next run would reapply
GitHub's refs.

To roll back the job, keep the timer stopped, restore the preserved service,
executable and compatibility wrapper, then verify syntax and credential scope.
The old job used an administrator key and unconditional force/prune; restoring
that behaviour deliberately returns to the old risk model. Revoke only the
eight deploy keys created for this replication task if retiring it, and preserve
its recovery receipts. Leave the separate MCP key and sync untouched.
