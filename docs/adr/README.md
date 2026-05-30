# Architecture Decision Records

Each ADR captures one significant architectural or operational decision:
context, decision, consequences. Format follows
[Michael Nygard's template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions.html).

## Index

| ID | Title | Status | Date |
|----|-------|--------|------|
| [0001](0001-use-opentofu-not-terraform.md) | Use OpenTofu, not Terraform | Accepted | 2026-05 |
| [0002](0002-pin-libvirt-provider-to-0.8.md) | Pin `dmacvicar/libvirt` to `~> 0.8.0` | Accepted | 2026-05 |
| [0003](0003-state-backend-strategy.md) | State backend strategy (local lab, S3-compatible production) | Accepted | 2026-05 |
| [0004](0004-cloud-init-bootstrap-conventions.md) | Cloud-init bootstrap conventions | Accepted | 2026-05 |
| [0005](0005-module-and-environment-layout.md) | Module and environment layout | Accepted (amended by 0010) | 2026-05 |
| [0006](0006-code-audit-2026-05.md) | Code audit 2026-05 findings | Accepted | 2026-05 |
| [0007](0007-set-meta-data-on-libvirt-cloudinit-disk.md) | Set `meta_data` on `libvirt_cloudinit_disk` | Accepted | 2026-05 |
| [0008](0008-omit-graphics-from-libvirt-domain-by-default.md) | Omit `graphics` from `libvirt_domain` by default | Accepted | 2026-05 |
| [0009](0009-begin-libvirt-0.9-migration-evaluation.md) | Begin `dmacvicar/libvirt` 0.9.x migration evaluation | Accepted | 2026-05 |
| [0010](0010-permit-module-supporting-files.md) | Permit module-local supporting files and ship the graphics override | Accepted | 2026-05 |
| [0011](0011-realize-production-s3-backend.md) | Realize the production S3 remote state backend | Accepted | 2026-05 |
| [0012](0012-libvirt-0.9-schema-diff-inventory.md) | `dmacvicar/libvirt` 0.9.x schema-diff inventory | Proposed | 2026-05 |
| [0013](0013-adopt-talos-linux.md) | Adopt Talos Linux for the Kubernetes layer (coexists with libvirt/Ubuntu) | Accepted | 2026-05 |
| [0014](0014-pin-siderolabs-talos-provider.md) | Pin `siderolabs/talos` to `~> 0.11.0` | Accepted | 2026-05 |
| [0015](0015-talos-machineconfig-as-code-and-secrets.md) | Talos machine-config-as-code and secret handling | Accepted | 2026-05 |

## Status values

- **Proposed** — Under discussion; not yet adopted.
- **Accepted** — Adopted; the codebase reflects this decision.
- **Superseded by ADR-NNNN** — Replaced by a later decision; kept for
  history.
- **Deprecated** — No longer applies, but not yet replaced.

## Authoring a new ADR

1. Copy the most recent ADR file as a template.
2. Increment the four-digit ID; use the next unused number.
3. Short imperative title (`Adopt X`, `Pin Y to Z`, `Use A over B`).
4. Fill in **Context**, **Decision**, **Consequences**, and a dated
   **Status**.
5. Add an entry to the index above.
6. Open a PR — ADRs go through the same review path as code.

ADRs are immutable once accepted. To change a decision, write a new ADR
that supersedes the old one and update the old ADR's status to
`Superseded by ADR-NNNN`.
