# Phase 0 — Recon and inventory (`infra`)

Audit pass: `audit/2026-06-13-full-pass`. Read-only phase. Branch base:
`72e0888` ("Adopt siderolabs/talos write-only secret arguments (ADR-0017);
close backlog BL-1/BL-2", #38).

Every figure below was produced by a command run in this session; the command
is cited inline. Items not verifiable this session are tagged `[UNVERIFIED]`.

## Component map

OpenTofu (HCL) infrastructure-as-code. No application runtime; the "build" is
provider initialization and the "tests" are native `tofu test` suites with
mocked providers.

```
infra/
├── modules/
│   ├── libvirt-vm/       # KVM/libvirt Ubuntu VM module (cloud-init bootstrap)
│   └── talos-cluster/    # Talos Linux Kubernetes on libvirt (siderolabs/talos)
├── environments/
│   ├── lab/              # local backend
│   ├── production/       # S3 backend (ADR-0011), placeholder resources
│   └── talos-lab/        # Talos cluster environment
├── scripts/init-backend.sh
├── docs/adr/             # 17 ADRs (0001-0017) + README index
└── .github/workflows/ci.yml
```

## File inventory

Source: `git ls-files | wc -l`, `find . -name '*.tf' …`, run 2026-06-13.

| Metric | Value |
|--------|-------|
| Tracked files | 90 |
| `.tf` files | 23 (1382 lines) |
| `.md` files | 44 |
| Modules | 2 (`libvirt-vm`, `talos-cluster`) |
| Environments | 3 (`lab`, `production`, `talos-lab`) |
| ADRs | 17 (0001-0017) accepted |
| In-code TODO/FIXME/XXX/HACK markers | 0 (`grep -rnE 'TODO|FIXME|XXX|HACK' --include='*.tf' --include='*.sh'`) |

## Dependency graph

Direct providers (from `.terraform.lock.hcl` and `versions.tf`):

| Provider | Pin (`versions.tf`) | Locked version | Upstream latest stable | Status |
|----------|---------------------|----------------|------------------------|--------|
| `dmacvicar/libvirt` | `~> 0.9.0` | `0.9.8` (all 5 lockfiles) | `v0.9.8` (2026-05-31) | Current [V] |
| `siderolabs/talos` | `~> 0.11.0` | `0.11.0` | `0.11.x` stable; `0.12.0` is alpha-only (latest tag `v0.12.0-alpha.4`, 2026-06-12) | Current stable [V] |

Upstream-latest checked via WebFetch of the providers' GitHub release pages,
2026-06-13. Lockfile versions identical across all 5 roots; no version drift
between modules and environments.

OpenTofu pinned to `1.12.1` (`.opentofu-version`); per-root `required_version`
floors: `lab`/`libvirt-vm` `>= 1.10`, `production` `>= 1.10.4`,
`talos-lab`/`talos-cluster` `>= 1.11` (write-only args, ADR-0017).

## CI configuration

`.github/workflows/ci.yml`, `permissions: contents: read` at workflow scope,
`concurrency` with `cancel-in-progress`. Jobs:

| Job | Tool |
|-----|------|
| `format` | `tofu fmt -check -recursive` |
| `validate` (matrix x5) | `tofu init -backend=false` + `tofu validate` |
| `lint` | `tflint --recursive` (ruleset via `tflint --init`, `GITHUB_TOKEN`) |
| `security` | Trivy IaC config scan, HIGH/CRITICAL, SARIF upload |
| `secret-scan` | gitleaks v8.30.1 (pinned by image digest), full working tree |
| `pre-commit` | hygiene hooks (terraform_* skipped; dedicated jobs above) |
| `test` (matrix x2) | `tofu test` per module |

All `uses:` are SHA-pinned with version comments. CodeQL runs via GitHub
default code-scanning setup (not a tracked workflow) `[UNVERIFIED]` from the
repo tree alone — consistent with the 2026-05-27 engagement's finding.

## Toolchain available in this environment

| Tool | Version | Note |
|------|---------|------|
| OpenTofu | 1.12.1 | Installed this session (pinned version) to enable the baseline |
| tflint | 0.63.1 | terraform ruleset plugin install rate-limited locally (see 01-baseline) |
| trivy | 0.71.0 | |
| gitleaks | dev build (`detect`/`protect`, no `dir` subcommand) | CI uses v8.30.1 |
| python3 | 3.11.15 | |

Absent at container start: `tofu` (installed this session; see the table
above), `semgrep`, `pip-audit` (no Python
package manifest beyond `requirements-dev.txt` pinning `pre-commit`).
