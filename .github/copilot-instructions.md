# Copilot Instructions — `infra`

OpenTofu infrastructure provisioning: KVM/libvirt VMs, networks,
storage. All commands are `tofu`; never reference Terraform as the
active tool.

The rationale behind every convention below lives in `docs/adr/`. Read
the relevant ADR before changing one; if the convention itself should
change, propose a new ADR that supersedes it rather than silently
editing code.

## Repository layout

```
modules/libvirt-vm/         — Reusable VM provisioning module
environments/{lab,production}/
scripts/                    — Operational helper scripts
docs/adr/                   — Architecture Decision Records
```

## HCL conventions

- 2-space indentation, no tabs; one blank line between top-level blocks
- Every variable: `description` + `type`. Every output: `description`
- `locals {}` for computed values; no complex inline expressions in
  resource arguments
- No hardcoded values in resource blocks — use variables or locals
- Files end with a single newline

## Module design

- Five required files per module: `main.tf`, `variables.tf`,
  `outputs.tf`, `versions.tf`, `README.md`
- Self-contained and reusable — no environment-specific hardcoding, no
  provider blocks inside modules
- Inputs validated with `type` constraints (and `validation { … }` when
  reasonable)
- Provider versions pinned in `versions.tf` with `~>` pessimistic
  constraint

## Variable naming

- `snake_case` throughout
- Prefix variables by module context in environment roots
  (`libvirt_vm_vcpus`)
- Sensitive variables marked `sensitive = true`

## Provider pinning

Pessimistic constraint. For pre-1.0 providers (such as
`dmacvicar/libvirt`), pin at the **patch** level — a minor-version bump
is the provider author's signal that breaking changes have shipped:

```hcl
required_providers {
  libvirt = {
    source  = "dmacvicar/libvirt"
    version = "~> 0.8.0"
  }
}
```

See [ADR-0002](../docs/adr/0002-pin-libvirt-provider-to-0.8.md).

## State safety

- Never `tofu apply` without a prior `tofu plan`
- Never edit state files manually
- Remote backends require locking + encryption at rest
- Lab environments may use the local backend
- For S3-compatible backends, prefer `use_lockfile = true` (OpenTofu
  1.10+) over `dynamodb_table`; prefer `endpoints = { s3 = "…" }` over
  the deprecated top-level `endpoint = "…"`. See
  [ADR-0003](../docs/adr/0003-state-backend-strategy.md).

## Secrets

- Mark sensitive variables `sensitive = true`
- Never hardcode credentials in `.tf` files or `terraform.tfvars`
- Inject via `TF_VAR_<name>` environment variables in CI
- Never commit `.auto.tfvars` or any `.tfvars` containing secrets

## OpenTofu terminology

- Tool: **OpenTofu**
- Binary: **`tofu`**
- Commands: `tofu init`, `tofu plan`, `tofu apply`, `tofu destroy`,
  `tofu fmt`, `tofu validate`
- Do not write "terraform" as an active command or tool name anywhere

## Architecture Decision Records

| ID | Title |
|----|-------|
| [0001](../docs/adr/0001-use-opentofu-not-terraform.md) | Use OpenTofu, not Terraform |
| [0002](../docs/adr/0002-pin-libvirt-provider-to-0.8.md) | Pin `dmacvicar/libvirt` to `~> 0.8.0` |
| [0003](../docs/adr/0003-state-backend-strategy.md) | State backend strategy |
| [0004](../docs/adr/0004-cloud-init-bootstrap-conventions.md) | Cloud-init bootstrap conventions |
| [0005](../docs/adr/0005-module-and-environment-layout.md) | Module and environment layout |
| [0006](../docs/adr/0006-code-audit-2026-05.md) | Code audit 2026-05 findings |
| [0007](../docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md) | Set `meta_data` on `libvirt_cloudinit_disk` |
