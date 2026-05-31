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
| BL-1 | Execute the libvirt 0.9.x migration evaluation gates against a real lab host, then author the successor pin-bump ADR | [ADR-0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md) gates 2–5; [ADR-0012](docs/adr/0012-libvirt-0.9-schema-diff-inventory.md) (Proposed) | ADR-0012's schema diff is desk-derived; the gates need a running libvirt to confirm | Dedicated session on a lab libvirt host; capture the schema-diff/state-migration recipes from running infra |
| BL-2 | Evaluate `siderolabs/talos` write-only secret arguments (`client_configuration_wo`, `machine_configuration_input_wo`) to keep rendered machine config out of state | audit 2026-05-31 | Defense-in-depth only — state is already encrypted ([ADR-0015](docs/adr/0015-talos-machineconfig-as-code-and-secrets.md)) | Assess in the next `siderolabs/talos` provider review; note the outcome in [ADR-0014](docs/adr/0014-pin-siderolabs-talos-provider.md) |

## Resolved

_(none yet — when an item closes, move its row here and link the resolving PR.)_
