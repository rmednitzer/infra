# Backlog — deferred and tracked work

Explicitly-deferred items that are not yet GitHub issues. Each was raised by an
audit or an ADR and intentionally postponed; this file keeps deferred work from
silently rotting (the 2026-05-27 engagement flagged that there was no such
tracker). Close an item by linking the PR/commit (or issue) that resolves it and
moving it to **Resolved**.

## Open

| Id | Item | Origin | Why deferred | Next step |
|----|------|--------|--------------|-----------|
| F12 | Verify `main` branch-protection rules (required CI checks, required review, no admin bypass, signed commits if intended) | [audit/2026-05-27-engagement.md](audit/2026-05-27-engagement.md) §8.1 (F12) | Not inspectable from the engagement's tool surface; needs the repo-admin API/UI | An admin confirms the ruleset out-of-band and records the confirmed settings here |

## Resolved

| Id | Item | Origin | Resolved by |
|----|------|--------|-------------|
| BL-1 | Execute the libvirt 0.9.x migration evaluation gates against a real lab host, then author the successor pin-bump ADR | [ADR-0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md) gates 2–5; [ADR-0012](docs/adr/0012-libvirt-0.9-schema-diff-inventory.md) | [ADR-0016](docs/adr/0016-migrate-libvirt-provider-to-0.9.md) (PR #29, merged 2026-06-04): gates 2–5 host-verified by the maintainer, pin bumped to `~> 0.9.0`, ADR-0002/0009/0012 superseded |
| BL-2 | Evaluate `siderolabs/talos` write-only secret arguments (`client_configuration_wo`, `machine_configuration_input_wo`) to keep rendered machine config out of state | audit 2026-05-31 | [ADR-0017](docs/adr/0017-adopt-talos-write-only-secret-arguments.md) (PR #38, 2026-06-09): adopted on `talos_machine_configuration_apply` + `talos_machine_bootstrap`; outcome noted in [ADR-0014](docs/adr/0014-pin-siderolabs-talos-provider.md) |
