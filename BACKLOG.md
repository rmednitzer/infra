# Backlog — deferred and tracked work

Explicitly-deferred items that are not yet GitHub issues. Each was raised by an
audit or an ADR and intentionally postponed; this file keeps deferred work from
silently rotting (the 2026-05-27 engagement flagged that there was no such
tracker). Close an item by linking the PR/commit (or issue) that resolves it and
moving it to **Resolved**.

## Open

| Id | Item | Origin | Why deferred | Next step |
|----|------|--------|--------------|-----------|
| F12 | Verify the *contents* of `main` branch protection (which checks are required, required review, no admin bypass, signed commits if intended) | [audit/2026-05-27-engagement.md](audit/2026-05-27-engagement.md) §8.1 (F12) | The branch-protection contents are still not exposed by any available tool; only the `protected` boolean is. Needs the repo-admin API/UI | An admin confirms the required-checks list and bypass posture, and records them under "F12 evidence" below |

### F12 evidence (2026-08-12)

Partially advanced. `GET /repos/{owner}/{repo}/branches` exposes a `protected`
boolean, which the 2026-05-27 engagement could not reach. Observed across the
eleven reachable fleet repositories:

| Protected | Repositories |
|---|---|
| yes | `infra`, `core-graph`, `agents`, `relay-shell`, `6dof-ascent-sim`, `aiops-mcp`, `ai-stack`, `automation`, `rmednitzer.github.io`, `runbooks`, `renovate-config` |
| no | none |

**Closed later the same day.** `renovate-config` was the one gap at first
observation: it publishes a Renovate preset that any repository may extend, so
an unreviewed push to its `main` propagated fleet-wide dependency policy.
Nothing automerges there (it has no dependencies of its own), so the exposure
was unreviewed change rather than unreviewed merge. The maintainer applied a
ruleset and `protected` was re-verified as true, so all eleven reachable
repositories now protect `main`.

The boolean is necessary but not sufficient. What remains unverified is the
required-checks list, and it matters more than "Info" implied when F12 was
raised. `renovate-preset.json` automerges
minor, patch, digest, pin and pinDigest updates with `platformAutomerge: true`,
and its own description states the property as "automerge low-risk updates once
required checks pass". That property is delegated, not self-enforced:

- Renovate's **branch** automerge waits for passing status checks it observes,
  independent of branch protection ("By default, Renovate will not automerge
  until it sees passing status checks / check runs for the branch",
  [Renovate automerge docs](https://docs.renovatebot.com/key-concepts/automerge/)).
- **`platformAutomerge: true` hands merging to GitHub's native auto-merge**,
  which waits for *required* reviews and status checks. If a protected branch
  declares no required checks, there is nothing for it to wait on.

So the required-checks list is a precondition of the preset's stated safety
property, not an independent hardening nicety. Confirming it is what closes F12.

The repositories where that actually bites are the ones Renovate automerges
into: `ai-stack`, `aiops-mcp`, `core-graph`, `agents`, `relay-shell`. A
protected branch there with no required checks would let an automerged update
land without CI having passed. `renovate-config` has no dependencies of its
own, so its own protection is about unreviewed change, not unreviewed merge.

Also unverified from here, and worth recording when an admin next has the UI
open: whether the ruleset bypass list is empty, and whether **Allow auto-merge**
is enabled per repository, since `platformAutomerge` is a no-op without it.

## Resolved

| Id | Item | Origin | Resolved by |
|----|------|--------|-------------|
| BL-1 | Execute the libvirt 0.9.x migration evaluation gates against a real lab host, then author the successor pin-bump ADR | [ADR-0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md) gates 2–5; [ADR-0012](docs/adr/0012-libvirt-0.9-schema-diff-inventory.md) | [ADR-0016](docs/adr/0016-migrate-libvirt-provider-to-0.9.md) (PR #29, merged 2026-06-04): gates 2–5 host-verified by the maintainer, pin bumped to `~> 0.9.0`, ADR-0002/0009/0012 superseded |
| BL-2 | Evaluate `siderolabs/talos` write-only secret arguments (`client_configuration_wo`, `machine_configuration_input_wo`) to keep rendered machine config out of state | audit 2026-05-31 | [ADR-0017](docs/adr/0017-adopt-talos-write-only-secret-arguments.md) (PR #38, 2026-06-09): adopted on `talos_machine_configuration_apply` + `talos_machine_bootstrap`; outcome noted in [ADR-0014](docs/adr/0014-pin-siderolabs-talos-provider.md) |
