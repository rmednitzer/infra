# ADR-0009: Begin `dmacvicar/libvirt` 0.9.x migration evaluation

- **Status**: Accepted
- **Date**: 2026-05-27

## Context

[ADR-0002](0002-pin-libvirt-provider-to-0.8.md) pins
`dmacvicar/libvirt` to `~> 0.8.0` and includes a migration plan to
move to 0.9.x "when we need 0.9.x capability" or "before 0.8.x goes
unmaintained." Neither trigger has been recorded as evaluated; the
0.8.x pin has been in place since the repo was scaffolded.

State of the provider's release lines as of this ADR:

| Branch | Latest | First release | Cadence |
|--------|--------|---------------|---------|
| 0.8.x | 0.8.3 (Mar 2026) | Mature | Patch fixes only |
| 0.9.x | 0.9.7 (Mar 2026) | Nov 2025 | Seven point releases in five months; still stabilising |

0.9.0 was a "breaking redesign with new plugin framework," per the
provider's own release notes. The schema is not source-compatible
with 0.8.x; state migration is required.

We do not yet need any 0.9.x-only capability. The trigger for this
ADR is the maintenance horizon, not a feature pull.

## Decision

Open a **structured evaluation** of the 0.8.x to 0.9.x migration.
This ADR does **not** change the pin. The pin moves only after the
evaluation completes and a successor ADR (`0010-…`) records the
decision to bump.

The evaluation consists of:

1. **Schema diff inventory.** For each resource we use
   (`libvirt_domain`, `libvirt_volume`, `libvirt_cloudinit_disk`,
   `libvirt_network` if/when added), document the 0.8.x to 0.9.x
   attribute deltas (renamed fields, dropped fields, new required
   fields, semantics changes).
2. **Lab apply-cycle test.** Run a 0.9.x build against
   `environments/lab` with the current resource graph plus a few
   variations (additional disks, multiple NICs, host networking).
   Capture the `tofu plan` schema diffs that show up before any
   intentional change, capture every error.
3. **State migration walk-through.** For each schema change that
   would otherwise produce a destroy/create on a real apply, write
   the `tofu state mv` / `tofu state rm` / `tofu import` recipe.
   Verify on a copy of lab state.
4. **Functional smoke test.** Confirm the migrated VMs reach a
   reachable, cloud-init-bootstrapped state. SSH lands, serial
   console works, ADR-0004 baseline behaviours hold.
5. **Maintenance horizon check.** Before the bump lands, confirm
   the 0.8.x branch has not received a security advisory we need to
   stay on.

Outcome of (1) through (4) goes into the successor ADR's evidence;
(5) goes into the successor ADR's `Context`. If any step fails or
forces an unacceptable trade-off, the successor ADR records the
decision to **defer**.

## Consequences

**Positive**

- The 0.9.x migration moves from oral tradition (a sentence in
  ADR-0002) to a tracked piece of work with documented gating
  criteria.
- Lab is the appropriate place for the experiment; the lab backend
  is local and the lab VMs are reproducible from `main.tf`. State
  loss during the experiment is recoverable by destroying and
  re-applying.
- When the bump does land, the successor ADR is a single
  reviewable artifact summarising every change instead of a
  scattered conversation across PRs.

**Negative**

- No immediate change; the 0.8.x branch carries one more cycle of
  patch-only maintenance work.
- If 0.9.x stabilises faster than we evaluate, we may end up
  bumping to a non-`.0` release (0.9.8, 0.9.9) instead of catching
  up at the next minor. Acceptable; 0.9.x patches do not break
  schema.

## Out of scope for this ADR

- The actual provider-pin change. That lives in ADR-0010 (when
  written).
- Any production-environment migration. Production currently
  defines no resources (placeholder backend per ADR-0003);
  production state migration only becomes relevant after the
  backend is wired up and resources land.

## Migration plan (when the evaluation closes positively)

This is the working sketch. The successor ADR refines and dates it.

1. Author ADR-0010 capturing the evaluation outcome, the decision
   to bump, and superseding the migration plan in ADR-0002.
2. In `modules/libvirt-vm/versions.tf` and every environment root's
   `versions.tf`: change `version = "~> 0.8.0"` to
   `version = "~> 0.9.0"` (patch-level pessimistic, consistent with
   the pre-1.0 pin rule from ADR-0002).
3. In `environments/lab`: `tofu init -upgrade` -- refreshes
   `.terraform.lock.hcl` with the 0.9.x hashes. Commit the new
   lock file in the same PR.
4. Run `tofu plan` per env. Resolve schema diffs via
   `tofu state mv` / `tofu state rm` + `tofu import` per the
   recipes captured during evaluation step (3). Never hand-edit
   `.tfstate`.
5. Apply in lab. Verify VMs survive the migration and behave per
   ADR-0004 baseline.
6. Repeat steps 3-5 in `environments/production` only after
   production has real resources; otherwise the production change
   is just the `versions.tf` edit and a `tofu init -upgrade`.
7. CI matrix already covers all three roots; no workflow edit.

## References

- [ADR-0002 — `dmacvicar/libvirt` pin](0002-pin-libvirt-provider-to-0.8.md)
- [`dmacvicar/libvirt` release notes](https://github.com/dmacvicar/terraform-provider-libvirt/releases)
- [OpenTofu state migration documentation](https://opentofu.org/docs/cli/commands/state/)
- [OpenTofu provider lock file](https://opentofu.org/docs/language/files/dependency-lock/)
