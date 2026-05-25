# Contributing to infra

Thanks for considering a contribution. This repository defines the
**infrastructure layer** for the fleet — what gets created and destroyed —
managed by [OpenTofu](https://opentofu.org/). Configuration management lives
in [`automation`](https://github.com/rmednitzer/automation); ad-hoc operator
scripts live in [`runbooks`](https://github.com/rmednitzer/runbooks).

## Before you start

- Read [`README.md`](./README.md) for scope, prerequisites, and layout.
- Read [`CLAUDE.md`](./CLAUDE.md) for HCL style and module conventions.
- Skim [`docs/adr/`](./docs/adr/) — significant decisions are captured as
  Architecture Decision Records; non-trivial changes should add or supersede
  one.

## Branch naming

- `feature/<short-description>` for new modules, environments, or providers
- `fix/<short-description>` for bug fixes
- `chore/<short-description>` for tooling / CI / docs-only updates
- `adr/<short-description>` for ADR-only changes

## Local development loop

Install [OpenTofu 1.12+](https://opentofu.org/docs/intro/install/),
[TFLint](https://github.com/terraform-linters/tflint), and
[Trivy](https://aquasecurity.github.io/trivy/). Then:

```bash
# Install pre-commit once
pip install pre-commit
pre-commit install

# pre-commit-terraform calls `terraform` by default; point it at OpenTofu.
export TFTOOL=tofu

# Run all hooks locally before pushing
pre-commit run --all-files

# Per-environment validation
cd environments/lab && tofu init -backend=false && tofu validate
```

CI mirrors these checks (`tofu fmt -check`, `tofu validate`, `tflint`,
Trivy IaC scan). PRs cannot merge with failing CI.

## Architecture Decision Records

Decisions that shape the repo (provider pins, state strategy, module
layout, bootstrap conventions) are captured under [`docs/adr/`](./docs/adr/)
using the Michael Nygard template:

- **Status** — Proposed / Accepted / Deprecated / Superseded by ADR-NNNN
- **Date**
- **Context**
- **Decision**
- **Consequences**

If your PR introduces a meaningfully new convention, add an ADR in the same
PR and link it from the README's ADR table.

## Pull request expectations

Each PR should:

1. Update [`CHANGELOG.md`](./CHANGELOG.md) under `[Unreleased]`.
2. Pass `pre-commit run --all-files` locally.
3. Pass CI (`tofu fmt`, `tofu validate`, `tflint`, Trivy IaC scan).
4. Use clear imperative commit subjects (`Add hcloud-vm module`,
   `Fix cloud-init hostname injection`).
5. Reference an ADR for architecturally significant changes.

The full PR checklist lives in
[`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md).

## Security-sensitive PRs

Changes touching state backends, secrets handling, IAM, network policy, or
cloud-init bootstrap require an explicit security review. Flag them in the
PR description. Never open a public issue for a suspected vulnerability —
see [`.github/SECURITY.md`](./.github/SECURITY.md).

## License

By contributing, you agree your contribution is licensed under
[Apache License 2.0](./LICENSE).
