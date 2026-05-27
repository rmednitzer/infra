# Changelog

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Open the structured evaluation of the `dmacvicar/libvirt` 0.8.x to
  0.9.x migration as
  [ADR-0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md).
  No pin change. The ADR captures gating criteria (schema-diff
  inventory, lab apply-cycle test, state-migration walk-through,
  functional smoke test, maintenance-horizon check); the actual bump
  lands in ADR-0010 when those gates close.
- Remove the SPICE `graphics` block from `libvirt_domain.vm` in the
  `libvirt-vm` module. The default-shaped VM no longer creates a
  SPICE (or any) graphics listener. Serial console
  (`virsh console <vm>`) remains as the out-of-band recovery path.
  Rationale in new
  [ADR-0008](docs/adr/0008-omit-graphics-from-libvirt-domain-by-default.md).
  Operators on existing infra see an in-place domain update; the
  graphics element is removed from the XML on the next domain
  restart.
- Set `meta_data` on `libvirt_cloudinit_disk.init` to
  `instance-id: ${vm_name}\nlocal-hostname: ${vm_name}\n`. Honours
  the cloud-init NoCloud contract for `instance-id` explicitly rather
  than relying on the provider's empty-file fallback. Closes
  [ADR-0006 Finding 2](docs/adr/0006-code-audit-2026-05.md) (status
  was DEFERRED); rationale and operator migration note in new
  [ADR-0007](docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md).
  Operators with existing VMs see a one-time cloudinit-disk re-create
  + domain restart on the first apply after upgrading.
- SHA-pin every `uses:` in `.github/workflows/ci.yml`. Major-version
  refs (`@v6`, `@v3`, etc.) re-resolve on every run; SHA pins are
  immutable. Each line carries a `# vX.Y.Z` (or equivalent) trailing
  comment so reviewers can see what version the SHA represents,
  matching the format Dependabot expects when bumping. Affects
  `actions/checkout`, `opentofu/setup-opentofu`,
  `terraform-linters/setup-tflint`, `aquasecurity/trivy-action`,
  `github/codeql-action/upload-sarif`, `actions/setup-python`, and
  `pre-commit/action`. Dependabot's `github-actions` ecosystem
  continues to track each line weekly. Aligns with NIST SSDF
  SP 800-218 PW.4 and SLSA Source Track guidance on third-party
  dependency pinning.
- Track Python tooling via Dependabot. Add `requirements-dev.txt`
  pinning `pre-commit==4.6.0` -- the only direct Python dependency
  the repo cares about -- and extend `.github/dependabot.yml` with a
  `pip` ecosystem entry that watches it weekly (label: `python`).
  `README.md` and `CONTRIBUTING.md` switched from
  `pip install pre-commit` to `pip install -r requirements-dev.txt`.
  No CI change.
- Extend `.gitignore` secret coverage: add `*.crt`, `*.cer`, `*.p12`,
  `*.pfx`, `.env`, `.env.local`, `.envrc`, and `.envrc.*`. The repo
  currently has none of these files; the additions are defensive so
  operator-side direnv files, local env files, and certificate
  bundles cannot accidentally be staged.
- Align `.claude/settings.json` permission allowlist with the
  OpenTofu-only policy from CLAUDE.md and ADR-0001. Drop the eight
  `Bash(terraform …)` entries (the active-tool policy says never use
  the `terraform` binary). Add read-only `tofu state list`, `tofu
  state show`, `tofu version`, the safe `tofu init -backend=false`
  prefix (so CI-equivalent validation runs without a permission
  prompt), and `trivy config` (the security gate from CI). No new
  state-mutating commands granted.
- Validate `var.libvirt_uri` in `environments/production/variables.tf`
  against the libvirt QEMU URI grammar. Accepts `qemu:///system`,
  `qemu:///session`, and the remote transports
  (`qemu+ssh`, `qemu+tls`, `qemu+tcp`, `qemu+unix`, others). A
  malformed URI now fails at plan time with a clear error rather than
  surfacing as a provider connection error at apply.
- Emit Trivy results as SARIF and upload them to the GitHub Security
  tab. The `security` job in `.github/workflows/ci.yml` now writes
  `trivy.sarif` and a follow-up step calls
  `github/codeql-action/upload-sarif@v3` with `if: always()` so
  findings surface even when Trivy's `exit-code: "1"` blocks the job.
  Job-level `permissions: security-events: write` granted; the
  workflow-level `contents: read` stays in place. No change to which
  severities block CI (still HIGH and CRITICAL).
- Add workflow-level `concurrency:` block to `.github/workflows/ci.yml`.
  Concurrent runs for the same `github.ref` cancel any in-progress run,
  so rapid pushes to a PR branch no longer pile up runners. Pushes to
  `main` after merge are infrequent (branch is protected; merges happen
  one PR at a time) so the same policy is safe there.
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
