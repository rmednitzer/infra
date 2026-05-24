# Architecture Decision Records

This directory contains the Architecture Decision Records (ADRs) for `infra-ops`.
Each ADR captures a single significant architectural or operational decision —
the context that motivated it, the decision itself, and the consequences (good
and bad) of choosing it.

The format follows [Michael Nygard's template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions.html).

## Index

| ID | Title | Status | Date |
|----|-------|--------|------|
| [0001](0001-use-opentofu-not-terraform.md) | Use OpenTofu, not Terraform | Accepted | 2026-05 |
| [0002](0002-pin-libvirt-provider-to-0.8.md) | Pin `dmacvicar/libvirt` to `~> 0.8.0` | Accepted | 2026-05 |
| [0003](0003-state-backend-strategy.md) | State backend strategy (local lab, S3-compatible production) | Accepted | 2026-05 |
| [0004](0004-cloud-init-bootstrap-conventions.md) | Cloud-init bootstrap conventions | Accepted | 2026-05 |
| [0005](0005-module-and-environment-layout.md) | Module and environment layout | Accepted | 2026-05 |
| [0006](0006-code-audit-2026-05.md) | Code audit 2026-05 findings | Accepted | 2026-05 |

## Status values

- **Proposed** — Under discussion; not yet adopted.
- **Accepted** — Adopted; the codebase reflects this decision.
- **Superseded by ADR-NNNN** — Replaced by a later decision; kept for history.
- **Deprecated** — No longer applies, but not yet replaced.

## Authoring a new ADR

1. Copy the most recent ADR file as a starting template.
2. Increment the four-digit ID; use the next unused number.
3. Use a short, imperative title (`Adopt X`, `Pin Y to Z`, `Use A over B`).
4. Fill in **Context**, **Decision**, **Consequences**, and a dated **Status**.
5. Add an entry to the index table above.
6. Open a pull request — ADRs go through the same review path as code.

ADRs are immutable once accepted. To change a decision, write a new ADR that
supersedes the old one and update the old ADR's status to
`Superseded by ADR-NNNN`.
