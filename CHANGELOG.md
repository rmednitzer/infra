# Changelog

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Pin CI's OpenTofu version via `tofu_version_file: .opentofu-version`
  on both `Setup OpenTofu` steps in `.github/workflows/ci.yml`. The
  `opentofu/setup-opentofu` action defaults to `latest` when no version
  input is supplied, so the `.opentofu-version` pin (`1.12.0`) was
  previously informational only. CI now installs the same version
  declared in the file. No behaviour change on this push; protects
  against silent drift on the next OpenTofu release.
- Optimise and rewrite every `.md` file end-to-end for tighter prose,
  consistent voice, and uniform structure across the three companion
  repos: `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `.github/SECURITY.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/copilot-instructions.md`, `docs/adr/README.md`, all six
  ADRs (`0001`–`0006`), `environments/lab/README.md`,
  `environments/production/README.md`, and
  `modules/libvirt-vm/README.md`. ADR Status / Date / Decisions /
  Consequences shape preserved per the Michael Nygard template;
  all factual content — decisions, dates, deprecations, version
  numbers, finding states (FIXED / DEFERRED / NO CHANGE / DOCUMENTED) —
  preserved verbatim. No module, environment, or CI behaviour change.
  `tofu fmt -check -recursive`, `tofu validate` per environment, and
  `tflint --recursive` all pass.
- Trim placeholder boilerplate in `environments/production/`: removed the
  example-module comment block in `main.tf`, the three commented-out
  variable stubs in `variables.tf`, the placeholder comment in
  `outputs.tf`, the commented-out tfvars examples, and the long inline
  S3-backend example in `backend.tf` (the backend example, native S3
  locking with `use_lockfile = true`, and the `endpoints = { s3 = "…" }`
  guidance live in ADR-0003 and the production env README — single source
  of truth). The working local placeholder backend stays in place so
  `tofu init -backend=false && tofu validate` still works in CI;
  `tofu fmt -check`, `tofu validate`, and `tflint --recursive` all pass.
- Sync governance docs (SECURITY policy shape, PR template structure,
  copilot instructions, README Governance table) with the companion
  `runbooks` and `automation` repos. No module, environment, or CI
  behavior change.

## [0.0.0]

### Scaffolding (PR #12)

- Governance: `NOTICE`, `CHANGELOG.md`, `CONTRIBUTING.md`,
  `.github/CODEOWNERS`, `.editorconfig`, `.opentofu-version` (`1.12.0`).
- Per-environment READMEs for `lab/` and `production/`.
- `.pre-commit-config.yaml` running `terraform_fmt`, `terraform_validate`,
  `terraform_tflint`, `terraform_trivy`, EditorConfig, hygiene.
- CI: Trivy IaC misconfiguration scan (fails on HIGH / CRITICAL) and
  pre-commit hygiene job.

### Initial OpenTofu structure

- `libvirt-vm` module with cloud-init, validated inputs, committed lock
  files.
- `lab/` and `production/` environments scaffolded (production: local
  placeholder backend, no resources yet).
- ADR-0001..0006 — OpenTofu choice, libvirt pin (`~> 0.8.0`), state
  backend strategy, cloud-init conventions, module / environment layout,
  2026-05 code-audit findings.
- CI: `tofu fmt`, `tofu validate`, `tflint`.
- `.github/SECURITY.md`, PR / issue templates, Dependabot.
