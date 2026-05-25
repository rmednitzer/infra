# Copilot Instructions for infra

`infra` is an OpenTofu infrastructure provisioning repository. It manages KVM/libvirt VMs, networks, and storage. All tooling uses `tofu` commands. Never reference Terraform as the active tool.

The rationale behind each standing convention below lives in `docs/adr/`. Before changing one, read the relevant ADR; if the convention itself should change, propose a new ADR that supersedes the existing one rather than silently editing the code.

---

## Repository Layout

```
modules/libvirt-vm/   — Reusable VM provisioning module (dmacvicar/libvirt)
environments/lab/     — Lab environment, local state backend
environments/production/ — Production environment, remote state backend
scripts/              — Operational helper scripts
docs/adr/             — Architecture Decision Records
```

---

## HCL Conventions

- 2-space indentation, no tabs
- One blank line between top-level blocks
- All variables must have `description` and `type`
- All outputs must have `description`
- Use `locals {}` for computed values, never inline complex expressions in resource arguments
- No hardcoded values in resource blocks — use variables or locals
- Files end with a single newline

---

## Module Design Rules

- Every module contains exactly: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
- Modules are self-contained and reusable — no environment-specific hardcoding
- All inputs are validated with `type` constraints
- All outputs are documented with `description`
- Provider versions are pinned in `versions.tf` using `~>` pessimistic constraint

---

## Variable Naming

- Use `snake_case` throughout
- Prefix variables by module context when in environment root configs (e.g., `libvirt_vm_vcpus`)
- Sensitive variables are marked `sensitive = true`

---

## Provider Pinning

Pin providers with a pessimistic constraint. For pre-1.0 providers (such as
`dmacvicar/libvirt`), a minor-version bump can introduce breaking changes, so
pin to the patch level (`~> 0.8.0`, i.e. `>= 0.8.0, < 0.9.0`):

```hcl
required_providers {
  libvirt = {
    source  = "dmacvicar/libvirt"
    version = "~> 0.8.0"
  }
}
```

---

## State Safety

- Never run `tofu apply` without a prior `tofu plan`
- Never edit state files manually
- Remote backends must have locking enabled and encryption at rest
- Lab environments may use local backend
- For S3-compatible backends, prefer `use_lockfile = true` (OpenTofu 1.10+) over `dynamodb_table`, and the `endpoints = { s3 = "…" }` map attribute over the deprecated top-level `endpoint = "…"`. See ADR-0003.

---

## Secrets

- Mark sensitive variables: `sensitive = true`
- Never hardcode credentials in `.tf` files or `terraform.tfvars`
- Use `TF_VAR_<name>` environment variables for secrets in CI
- Never commit `.auto.tfvars` or any `.tfvars` containing secrets

---

## OpenTofu Terminology

- Tool: **OpenTofu**
- Binary: **`tofu`**
- Commands: `tofu init`, `tofu plan`, `tofu apply`, `tofu destroy`, `tofu fmt`, `tofu validate`
- Do not write "terraform" as an active command or tool name anywhere

---

## Architecture Decision Records

| ID | Title | Location |
|----|-------|----------|
| 0001 | Use OpenTofu, not Terraform | `docs/adr/0001-use-opentofu-not-terraform.md` |
| 0002 | Pin `dmacvicar/libvirt` to `~> 0.8.0` | `docs/adr/0002-pin-libvirt-provider-to-0.8.md` |
| 0003 | State backend strategy | `docs/adr/0003-state-backend-strategy.md` |
| 0004 | Cloud-init bootstrap conventions | `docs/adr/0004-cloud-init-bootstrap-conventions.md` |
| 0005 | Module and environment layout | `docs/adr/0005-module-and-environment-layout.md` |
| 0006 | Code audit 2026-05 findings | `docs/adr/0006-code-audit-2026-05.md` |
