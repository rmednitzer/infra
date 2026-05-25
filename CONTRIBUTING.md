# Contributing to infra

This repository defines the **infrastructure layer** — what gets created
and destroyed — via [OpenTofu](https://opentofu.org/). HCL style and
OpenTofu policy live in [`CLAUDE.md`](./CLAUDE.md); standing decisions
in [`docs/adr/`](./docs/adr/). This file covers workflow only.

## Branch naming

| Prefix | Use |
|--------|-----|
| `feature/` | New modules, environments, providers |
| `fix/` | Bug fixes |
| `chore/` | CI / tooling / lint updates |
| `adr/` | ADR-only changes |

## Local loop

```bash
pip install pre-commit && pre-commit install
export TFTOOL=tofu        # point pre-commit-terraform at OpenTofu
pre-commit run --all-files
```

CI mirrors the hook set (`tofu fmt`, `tofu validate`, `tflint`, Trivy
IaC, hygiene). PRs cannot merge with failing CI.

## Pull request expectations

1. Update [`CHANGELOG.md`](./CHANGELOG.md) under `[Unreleased]`.
2. Pass `pre-commit run --all-files` locally.
3. For architecturally significant changes, add an ADR using the
   Michael Nygard template and link it from the README's ADR table.

PR template:
[`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md).
Suspected vulnerabilities: see
[`.github/SECURITY.md`](./.github/SECURITY.md) — never open a public
issue.

By contributing, you agree your contribution is licensed under
[Apache License 2.0](./LICENSE).
