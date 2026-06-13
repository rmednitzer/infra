# Phase 2/3 — Security and quality findings register (`infra`)

Audit pass: `audit/2026-06-13-full-pass`. Read-only phases. Schema:
ID, title, severity, CWE (where applicable), location, evidence,
exploit-plausibility, recommended fix, effort (S/M/L).

Severity scale: critical / high / medium / low / info.

## Summary

**No new critical, high, medium, or low security findings.** The repository
was last audited 2026-05-27 (see [2026-05-27-engagement.md](2026-05-27-engagement.md), 14 findings
F1-F14, all FIXED or explicitly DEFERRED/OUTSTANDING) and has since landed
ADR-0010 through ADR-0017. This pass re-ran the full gate suite (see
`01-baseline.md`) and reviewed every `.tf` source, the cloud-init template,
the Talos machine-config templates, the backend configuration, and the
`init-backend.sh` script. The findings below are the residual carried items
plus informational observations.

## Security audit coverage (this session)

| Area | Method | Result |
|------|--------|--------|
| Dependency vulnerabilities | Provider versions vs upstream latest (WebFetch) | libvirt 0.9.8 = latest; talos 0.11.0 = current stable. No advisories/KEV for components in scope. |
| IaC misconfiguration | `trivy config` HIGH/CRITICAL | 0 |
| Secrets | `gitleaks detect` (history + working tree) | 0 |
| SAST | Manual review (no semgrep in env) of all 23 `.tf`, templates, shell | No injection/path-traversal/unsafe-default findings |
| Input boundaries | Reviewed every `variable` validation + module preconditions | Comprehensive; see Q-INFO-1 |
| Supply chain | Lockfile integrity; SHA-pinned actions; gitleaks image digest pin | Intact |
| IaC hardening | cloud-init, Talos sysctls/kubelet, graphics default-off | Hardened (ADR-0008, docs/talos-cis-kubernetes.md) |

## Findings

### S-1 — `main` branch-protection ruleset not verifiable from this surface

- Severity: info
- Location: repository settings (GitHub), not in-tree
- Evidence: No admin API access from this session's tool surface; carried from
  the 2026-05-27 engagement as F12 and tracked in `BACKLOG.md` (Open).
- Exploit-plausibility: n/a (governance gap, not a code defect). If protection
  is weak, an unreviewed push to `main` could bypass the CI gates.
- Recommended fix: a repo admin confirms required-checks, required-review,
  no-admin-bypass (and signed commits if intended) out of band and records the
  confirmed settings in `BACKLOG.md`.
- Effort: S (admin action, out of band)

### Q-INFO-1 — Input validation surface (observation, no action)

- Severity: info
- Location: `modules/*/variables.tf`, `modules/talos-cluster/main.tf`
- Evidence: Every external input is typed and validated. `libvirt-vm` validates
  `vm_name` (RFC 1123), `vcpus`/`memory_mib`/`disk_size_gib` (whole-number
  floors), `ssh_public_key` (OpenSSH key shape, marked `sensitive`),
  `additional_disks` (unique names, size floor, <= 25 cap matching the vdb-vdz
  device derivation), `graphics.type` (enum). `talos-cluster` enforces
  cross-variable invariants (disjoint node names, unique/in-CIDR/non-reserved
  IPs, unique MACs) via `terraform_data.node_invariants` preconditions, all
  exercised by the test suite. No unvalidated boundary found.
- Recommended fix: none.

## Carried items from the 2026-05-27 engagement

| Prior ID | Disposition this pass |
|----------|-----------------------|
| F1-F11, F14 | FIXED previously; re-confirmed green in `01-baseline.md` |
| F12 | Still OUTSTANDING -> tracked as S-1 above and in `BACKLOG.md` |
| F13 (`production` `required_version` >= 1.10 on S3 backend) | RESOLVED: `production/versions.tf` now pins `>= 1.10.4` (ADR-0011) |
| Outstanding §8 item 6 (`PCT_TFPATH` vs `TFTOOL`) | RESOLVED: `.pre-commit-config.yaml` and README both use `PCT_TFPATH=tofu` |

No stop conditions encountered: no secret material in tree or history, no
dependency with an active advisory, no instruction-bearing untrusted content.
