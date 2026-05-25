# infra

[![CI](https://github.com/rmednitzer/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/rmednitzer/infra/actions/workflows/ci.yml)

Infrastructure provisioning repository for KVM/libvirt virtual machines, networks, and storage, managed with [OpenTofu](https://opentofu.org/). Designed for production-grade operations with compliance-aligned practices, CI-gated changes, and documented module interfaces.

This repository was previously named `infra-ops`. Companion repositories: `automation` (Ansible configuration and hardening) and `runbooks` (ad-hoc operator scripts).

The rationale behind the standing architectural choices — OpenTofu over Terraform, the `dmacvicar/libvirt` `~> 0.8.0` pin, the state-backend strategy, the cloud-init baseline, and the module/environment layout — is recorded in [`docs/adr/`](docs/adr/).

## Scope

This repository defines the **infrastructure layer**: what gets created and destroyed. It is decoupled from configuration management concerns (e.g., Ansible, Salt). Current providers:

- **KVM/libvirt** (`dmacvicar/libvirt`, pinned `~> 0.8.0` — see [ADR-0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md)) — VM provisioning on bare-metal hosts

Planned future expansion:

- **Hetzner Cloud** (`hetznercloud/hcloud`)
- Additional cloud providers as required

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6 (1.12 is current; production will require >= 1.10 once the S3 backend is wired up — see [ADR-0003](docs/adr/0003-state-backend-strategy.md))
- A KVM/libvirt host with `qemu-system` and `libvirtd` running, with `default` storage pool and network defined (the module does not create them — see [ADR-0006 Finding 7](docs/adr/0006-code-audit-2026-05.md))
- A cloud-init compatible base image (e.g., [Ubuntu 24.04 cloud image](https://cloud-images.ubuntu.com/noble/current/))
- An SSH key pair for VM access
- [TFLint](https://github.com/terraform-linters/tflint) (for local linting, optional)

## Quick Start

```bash
# Install OpenTofu: https://opentofu.org/docs/intro/install/

# Initialize the lab environment
cd environments/lab
tofu init

# Set required secrets via environment variables
export TF_VAR_ssh_public_key="ssh-ed25519 AAAA..."

# Preview and apply
tofu plan
tofu apply
```

## Repository Structure

```
infra/
├── modules/
│   └── libvirt-vm/              # KVM/libvirt VM provisioning module
├── environments/
│   ├── lab/                     # Lab environment (local state)
│   └── production/              # Production environment (remote backend required; local placeholder, no resources yet)
├── scripts/
│   └── init-backend.sh          # Backend initialization helper
├── docs/
│   └── adr/                     # Architecture Decision Records
└── .github/
    └── workflows/
        └── ci.yml               # CI: tofu fmt, tofu validate, tflint
```

## Modules

### [libvirt-vm](modules/libvirt-vm/)

Provisions a KVM/libvirt VM with cloud-init, configurable CPU, memory, root disk, and optional additional data disks. See the [module README](modules/libvirt-vm/README.md) for full inputs/outputs documentation.

Key inputs:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vm_name` | `string` | — | VM hostname |
| `vcpus` | `number` | `2` | Virtual CPU count |
| `memory_mib` | `number` | `2048` | Memory in MiB |
| `disk_size_gib` | `number` | `20` | Root disk size in GiB |
| `base_image` | `string` | — | Path or URL to cloud image |
| `ssh_public_key` | `string` | — | SSH public key (sensitive) |

## Environments

| Environment | Backend | Status | Description |
|-------------|---------|--------|-------------|
| [lab](environments/lab/) | Local | Active | Development and testing on a local KVM host |
| [production](environments/production/) | Remote (S3-compatible) — *required, not yet configured* | Placeholder | Defines no resources yet; `backend.tf` ships a local placeholder and must be switched to a locked, encrypted remote backend before any production resources are added |

Each environment has its own `backend.tf`, `variables.tf`, `terraform.tfvars` (non-secret defaults only), `versions.tf`, and a committed `.terraform.lock.hcl`. Use the helper script to initialize:

```bash
./scripts/init-backend.sh lab
```

Production currently ships a **local placeholder backend** and declares no
infrastructure. Before provisioning production, edit
`environments/production/backend.tf` to configure the remote S3-compatible
backend (with locking and encryption at rest — see the commented example in
that file and [ADR-0003](docs/adr/0003-state-backend-strategy.md) for the
full rationale), then set backend credentials and initialize:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
./scripts/init-backend.sh production
```

## Architecture Decisions

Standing decisions live in [`docs/adr/`](docs/adr/). Each ADR captures the
context, the decision, and the consequences of a single significant choice.
Current set:

| ID | Title |
|----|-------|
| [0001](docs/adr/0001-use-opentofu-not-terraform.md) | Use OpenTofu, not Terraform |
| [0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md) | Pin `dmacvicar/libvirt` to `~> 0.8.0` |
| [0003](docs/adr/0003-state-backend-strategy.md) | State backend strategy (local lab, S3-compatible production) |
| [0004](docs/adr/0004-cloud-init-bootstrap-conventions.md) | Cloud-init bootstrap conventions |
| [0005](docs/adr/0005-module-and-environment-layout.md) | Module and environment layout |
| [0006](docs/adr/0006-code-audit-2026-05.md) | Code audit 2026-05 findings |

New significant decisions are recorded as additional ADRs rather than as
ad-hoc README sections; the README links out, the ADR owns the explanation.

## Compliance and State Safety

These are the project's required practices. The lab environment uses a local
backend by design; any non-lab environment must satisfy the remote-backend
requirements below before it provisions resources. The full rationale is in
[ADR-0003](docs/adr/0003-state-backend-strategy.md) (state) and
[ADR-0004](docs/adr/0004-cloud-init-bootstrap-conventions.md) (VM bootstrap).

- Remote backends **must** have encryption at rest enabled
- Remote backends **must** have state locking enabled — prefer `use_lockfile = true` (OpenTofu 1.10+ native S3 locking) over `dynamodb_table`
- Sensitive variables are marked `sensitive = true` and never committed
- Secrets are injected via `TF_VAR_*` environment variables
- Cloud-init bootstraps every VM into a hardened state: no password auth, no root SSH, locked default user, key-only access
- All changes flow through CI-gated pull requests

## Common Commands

| Command | Purpose |
|---------|---------|
| `tofu init` | Initialize working directory and download providers |
| `tofu plan` | Preview changes before applying |
| `tofu apply` | Apply planned changes |
| `tofu destroy` | Destroy all managed resources |
| `tofu fmt -recursive` | Format all HCL files |
| `tofu validate` | Validate configuration syntax |
| `tofu state list` | List resources in state |
| `tofu output` | Show output values |

## CI / Quality

Every push and pull request runs five checks:

| Check | Tool | Command |
|-------|------|---------|
| Format | `tofu fmt` | `tofu fmt -check -recursive` |
| Validate | `tofu validate` | Per-environment `tofu init -backend=false && tofu validate` |
| Lint | [TFLint](https://github.com/terraform-linters/tflint) | `tflint --recursive` |
| Security | [Trivy](https://aquasecurity.github.io/trivy/) | `trivy config . --severity HIGH,CRITICAL` |
| Hygiene | [pre-commit](https://pre-commit.com/) | `pre-commit run --all-files` |

All checks must pass before a pull request can be merged.

## Local development loop

```bash
pip install pre-commit
pre-commit install
# pre-commit-terraform calls `terraform` by default; point it at OpenTofu.
export TFTOOL=tofu
pre-commit run --all-files
```

The hook set is in [`.pre-commit-config.yaml`](.pre-commit-config.yaml) and
covers `terraform_fmt`, `terraform_validate`, `terraform_tflint`,
`terraform_trivy`, EditorConfig conformance, and the standard hygiene hooks.
The OpenTofu binary version is pinned via
[`.opentofu-version`](.opentofu-version) (`1.12.0`) for `asdf` / `tenv` /
`mise` users.

## Governance

- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — contribution workflow, ADR
  expectations, branch naming.
- [`CHANGELOG.md`](./CHANGELOG.md) — Keep-a-Changelog 1.1.0 format.
- [`.github/SECURITY.md`](.github/SECURITY.md) — vulnerability reporting.
- [`.github/CODEOWNERS`](.github/CODEOWNERS) — review assignment for ADRs,
  modules, production environment, and workflows.
- [`CLAUDE.md`](./CLAUDE.md) — AI-authoring contract; OpenTofu-only
  policy; HCL style.

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
