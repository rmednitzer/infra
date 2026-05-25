# Changelog

All notable changes to this project will be documented in this file.

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `NOTICE` file for Apache 2.0 source-distribution conformance.
- `.editorconfig` for consistent indentation across editors.
- `.opentofu-version` pinning OpenTofu 1.12.0 for `asdf` / `tenv` / `mise`
  users.
- `.pre-commit-config.yaml` running `terraform_fmt`, `terraform_validate`,
  `terraform_tflint`, `terraform_trivy`, and standard hygiene hooks;
  mirrored in CI.
- Trivy IaC misconfiguration scan in `.github/workflows/ci.yml`, failing PRs
  on HIGH or CRITICAL findings.
- `environments/lab/README.md` and `environments/production/README.md`
  documenting per-environment setup, backend configuration, and the apply
  workflow.
- `.github/CODEOWNERS` assigning repo-wide review responsibility.
- `CONTRIBUTING.md` consolidating the contribution workflow, ADR
  expectations, and the local development loop.
- This `CHANGELOG.md`.

### Changed

- `README.md` indexes the new governance and tooling files.

## [0.0.0] — initial OpenTofu structure (post-rename)

- Repository renamed from `infra-ops` to `infra`.
- `libvirt-vm` module with cloud-init, configurable CPU / memory / disk,
  optional data disks, and full variable validation.
- `lab/` and `production/` environments scaffolded; lock files committed.
- ADR-0001 through ADR-0006 capturing the OpenTofu choice, libvirt
  provider pin (`~> 0.8.0`), state backend strategy, cloud-init
  conventions, module / environment layout, and the 2026-05 code-audit
  findings.
- CI: `tofu fmt -check`, `tofu validate` per environment, `tflint`.
- `.github/SECURITY.md`, PR / issue templates, Dependabot for actions.
