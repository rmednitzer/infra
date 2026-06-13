# Phase 1 — Validation baseline (`infra`)

Audit pass: `audit/2026-06-13-full-pass`. Read-only phase. This is the
regression reference for any later change in this pass.

All commands below were run this session against branch base `72e0888`.
OpenTofu 1.12.1 was installed this session (the pinned version) so the
baseline is executed, not inferred.

## Build / init

Each module and environment initialized with `tofu init -backend=false`
(the CI mode; no backend or credentials contacted). All 5 roots succeeded.

## Format

```
$ tofu fmt -check -recursive
$ echo $?
0
```

Result: **clean** (exit 0, no files reformatted).

## Validate

`tofu validate` per root after `init -backend=false`:

| Root | Result |
|------|--------|
| `modules/libvirt-vm` | Success! The configuration is valid. |
| `modules/talos-cluster` | Success! The configuration is valid. |
| `environments/lab` | Success! The configuration is valid. |
| `environments/production` | Success! The configuration is valid. |
| `environments/talos-lab` | Success! The configuration is valid. |

Result: **5/5 valid.**

## Tests

`tofu test` per module (providers mocked via `mock_provider`; no libvirtd,
talosctl, or live cluster required):

| Module | Result | Runtime |
|--------|--------|---------|
| `modules/libvirt-vm` | **17 passed, 0 failed** | sub-second (mocked) |
| `modules/talos-cluster` | **46 passed, 0 failed** | sub-second (mocked) |

Total: **63 passed, 0 failed.** No flaky candidates observed (mocked providers,
deterministic). Coverage tooling: none exists for HCL modules; the suites
exercise every input validation and every cross-variable precondition
(`terraform_data.node_invariants`) by assertion. Absence of a line-coverage
metric is inherent to OpenTofu, not a gap to remediate.

## Lint

```
$ tflint --recursive
$ echo $?
0
```

Result: exit 0. **`[PARTIAL]`**: `tflint --init` could not install the
`terraform-linters/tflint-ruleset-terraform` plugin in this environment —
unauthenticated GitHub API returned `403 API rate limit exceeded`. The
recursive run therefore exercised tflint's built-in core rules only, not the
pinned terraform ruleset (`.tflint.hcl`). CI installs the plugin with
`GITHUB_TOKEN`, so the full ruleset runs there. This is an environment
limitation of the audit container, not a repository defect.

## Security tooling (cross-referenced in Phase 2)

| Tool | Command | Result |
|------|---------|--------|
| Trivy (IaC) | `trivy config . --severity HIGH,CRITICAL --skip-dirs '**/.terraform'` | 0 misconfigurations across all 3 scanned OpenTofu roots (lab, production, talos-lab; Trivy labels the type `terraform`) |
| gitleaks (history) | `gitleaks detect --redact` | 35 commits scanned, **no leaks** |
| gitleaks (working tree) | `gitleaks detect --no-git --redact` | **no leaks** |

## CI drift

The commands above mirror the CI job definitions in `ci.yml` (same arguments).
The only divergence between this local baseline and CI is the tflint ruleset
plugin (rate-limited locally, installed via token in CI) and gitleaks version
(dev build locally vs pinned v8.30.1 in CI; both reported zero leaks). No
behavioral drift between CI config and what runs.

## Baseline summary

| Gate | Result |
|------|--------|
| `tofu fmt` | clean |
| `tofu validate` (x5) | 5/5 pass |
| `tofu test` (x2) | 63/63 pass |
| `tflint` | exit 0 (core rules; ruleset rate-limited locally) |
| Trivy HIGH/CRITICAL | 0 |
| gitleaks | 0 (history + working tree) |

The repository is **green across every reproducible gate.**
