# CLAUDE.md — AI Assistant Guide for infra-ops

## Project Overview

`infra-ops` is an OpenTofu infrastructure provisioning repository managing VM lifecycle, networking, and storage allocation via the `dmacvicar/libvirt` provider (KVM/libvirt). It defines the infrastructure layer — what gets created and destroyed — and is intentionally decoupled from configuration management concerns (Ansible, Salt, etc.).

This repository uses **OpenTofu** exclusively. All commands use `tofu`. Never reference Terraform as the active tool. The HCL language, `.tf` extensions, `terraform.tfvars` filename, and `.terraform/` directory are shared ecosystem conventions — not Terraform references.

---

## Repository Structure

```
infra-ops/
├── CLAUDE.md                    # This file: AI assistant guide
├── README.md                    # Project documentation
├── LICENSE                      # Apache 2.0
├── .gitignore                   # OpenTofu-specific ignores
├── .tflint.hcl                  # TFLint configuration (recommended preset)
├── .github/
│   ├── copilot-instructions.md  # Copilot coding guidelines
│   ├── PULL_REQUEST_TEMPLATE.md # PR checklist
│   ├── SECURITY.md              # Vulnerability reporting policy
│   ├── dependabot.yml           # GitHub Actions dependency updates
│   ├── ISSUE_TEMPLATE/          # Issue forms
│   └── workflows/
│       └── ci.yml               # CI: fmt, validate, lint
├── modules/                     # Reusable, self-contained OpenTofu modules
│   └── libvirt-vm/              # KVM/libvirt VM provisioning
│       ├── main.tf              # Resource definitions
│       ├── variables.tf         # Input variables with types and descriptions
│       ├── outputs.tf           # Output values with descriptions
│       ├── versions.tf          # Provider and OpenTofu version constraints
│       ├── cloud_init.cfg       # Cloud-init user-data template
│       └── README.md            # Module documentation
├── environments/                # Per-environment root configurations
│   ├── lab/                     # Lab: local state, libvirt on bare metal
│   │   ├── main.tf              # Module calls
│   │   ├── variables.tf         # Environment-level variables
│   │   ├── outputs.tf           # Environment outputs
│   │   ├── versions.tf          # Provider and OpenTofu version constraints
│   │   ├── terraform.tfvars     # Non-secret defaults (tracked in git)
│   │   ├── backend.tf           # State backend configuration
│   │   └── .terraform.lock.hcl  # Provider dependency lock (tracked in git)
│   └── production/              # Production: remote backend required (currently a local placeholder, no resources)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfvars
│       ├── backend.tf
│       └── .terraform.lock.hcl
├── docs/
│   └── adr/                     # Architecture Decision Records (read first when changing a convention)
│       ├── README.md            # ADR index and authoring guide
│       ├── 0001-use-opentofu-not-terraform.md
│       ├── 0002-pin-libvirt-provider-to-0.8.md
│       ├── 0003-state-backend-strategy.md
│       ├── 0004-cloud-init-bootstrap-conventions.md
│       ├── 0005-module-and-environment-layout.md
│       └── 0006-code-audit-2026-05.md
└── scripts/
    └── init-backend.sh          # Backend initialization helper
```

---

## Architecture Decision Records

Standing decisions — provider version pin, state backend strategy, module
layout, cloud-init defaults — live in `docs/adr/`. When asked to change a
convention, **read the relevant ADR first** to understand the existing
rationale. Changing a decision means writing a new ADR that supersedes the
old one, not silently editing the underlying code. The current set is
indexed in `docs/adr/README.md`.

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Module directories | `snake_case` | `libvirt-vm` (hyphen for readability) |
| Environment directories | lowercase | `lab`, `production` |
| Variables | `snake_case`, prefixed by module context | `libvirt_vm_vcpus` |
| Resources | `snake_case` | `libvirt_domain.vm` |
| Data sources | `snake_case` | `data.libvirt_network.default` |
| Outputs | `snake_case` | `vm_id`, `ip_address` |
| Locals | `snake_case` | `locals { disk_size_bytes = ... }` |

---

## HCL Style Guide

- **Indentation**: 2 spaces, no tabs
- **Provider versions**: explicit pins in `required_providers` using pessimistic constraint (`~>`)
- **versions.tf**: every module and every environment root must have a `versions.tf` with `required_providers` and `required_version`
- **Variables**: every variable must have `description` and `type`; use `default` only when a sensible default exists
- **Outputs**: every output must have `description`
- **Sensitive values**: mark with `sensitive = true`; never hardcode credentials
- **Locals**: use `locals {}` for computed or derived values; do not inline complex expressions in resource arguments
- **No hardcoded values** in resource blocks — reference variables or locals
- **Blank lines**: one blank line between top-level blocks; no trailing blank lines at EOF

Example variable block:

```hcl
variable "memory_mib" {
  description = "Memory allocated to the VM in MiB."
  type        = number
  default     = 2048
}
```

Example output block:

```hcl
output "ip_address" {
  description = "VM IP address assigned via DHCP."
  value       = libvirt_domain.vm.network_interface[0].addresses[0]
}
```

---

## Module Structure

Every module **must** contain:

| File | Purpose |
|------|---------|
| `main.tf` | Resource and data source definitions |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value declarations |
| `versions.tf` | Provider constraints (`required_providers`) |
| `README.md` | Usage documentation, inputs/outputs table |

Modules must be self-contained and reusable. They must not reference environment-specific paths or assume a particular backend.

---

## State Management

- **Lab**: local backend is acceptable for iteration
- **Non-lab environments**: remote backend required (e.g., S3-compatible, Consul)
- **Encryption at rest**: mandatory for all remote backends
- **State locking**: enabled on all remote backends to prevent concurrent modifications
- **No secrets in state**: avoid storing credentials as resource arguments where possible; use data sources
- **Never manually edit state** — use `tofu state mv`, `tofu state rm`, or `tofu import` as appropriate

---

## Secrets Management

- Never commit `.tfvars` files containing secrets
- Use `TF_VAR_<name>` environment variables for sensitive inputs in CI and production
- Mark sensitive variables with `sensitive = true`
- Use external secret stores (Vault, AWS Secrets Manager) for production credentials
- `terraform.tfvars` per environment contains only non-secret defaults and is tracked in git

---

## Common Commands

```bash
# Initialize working directory (download providers)
tofu init

# Preview changes
tofu plan

# Apply changes
tofu apply

# Destroy all managed resources
tofu destroy

# Format HCL files
tofu fmt -recursive

# Validate configuration syntax
tofu validate

# List resources in state
tofu state list

# Show output values
tofu output
```

---

## Quality Tools

| Tool | Purpose | Command |
|------|---------|---------|
| `tofu fmt` | HCL formatting | `tofu fmt -check -recursive` |
| `tofu validate` | Syntax and type checking | `tofu validate` |
| `tflint` | Lint rules for providers/practices | `tflint` |

CI enforces all three on every push and pull request.

---

## Git Workflow

1. Branch from `main` with a descriptive name:
   - `feature/add-hcloud-provider`
   - `fix/libvirt-network`
   - `docs/update-module-readme`
2. Make changes, run `tofu fmt` and `tofu validate` locally
3. Open a pull request — CI must pass before merge
4. Use clear, imperative commit messages: `Add libvirt-vm module`, `Fix cloud-init hostname injection`

---

## Important Notes for AI Assistants

- **Always read existing files** before modifying them to understand current state
- **Read the relevant ADR** in `docs/adr/` before changing a standing convention; if the decision should change, write a new ADR rather than silently editing code
- **Never commit secrets or state files** — check `.gitignore` and variable sensitivity
- **Use `tofu plan` before `tofu apply`** — never apply without reviewing the plan
- **Use OpenTofu terminology consistently** — commands are `tofu`, tool is "OpenTofu"
- **Do not reference Terraform** as the active tool in any documentation or comments
- **Pin provider versions** with `~>` pessimistic constraints in every `versions.tf`. For pre-1.0 providers, pin at the **patch** level (`~> 0.8.0`, not `~> 0.8`) — see ADR-0002
- **Every variable needs `description` and `type`** — no exceptions
- **Every output needs `description`** — no exceptions
- When adding a new module, create all five required files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
- For the production S3 backend, prefer `use_lockfile = true` over `dynamodb_table`, and the `endpoints = { s3 = "…" }` map attribute over the top-level `endpoint = "…"` — see ADR-0003 and ADR-0006
