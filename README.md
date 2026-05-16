# infra-ops

[![CI](https://github.com/rmednitzer/infra-ops/actions/workflows/ci.yml/badge.svg)](https://github.com/rmednitzer/infra-ops/actions/workflows/ci.yml)

Infrastructure provisioning repository for KVM/libvirt virtual machines, networks, and storage, managed with [OpenTofu](https://opentofu.org/). Designed for production-grade operations with compliance-aligned practices, CI-gated changes, and documented module interfaces.

## Scope

This repository defines the **infrastructure layer**: what gets created and destroyed. It is decoupled from configuration management concerns (e.g., Ansible, Salt). Current providers:

- **KVM/libvirt** (`dmacvicar/libvirt`) — VM provisioning on bare-metal hosts

Planned future expansion:

- **Hetzner Cloud** (`hetznercloud/hcloud`)
- Additional cloud providers as required

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6
- A KVM/libvirt host with `qemu-system` and `libvirtd` running
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
infra-ops/
├── modules/
│   └── libvirt-vm/              # KVM/libvirt VM provisioning module
├── environments/
│   ├── lab/                     # Lab environment (local state)
│   └── production/              # Production environment (remote state)
├── scripts/
│   └── init-backend.sh          # Backend initialization helper
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
that file), then set backend credentials and initialize:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
./scripts/init-backend.sh production
```

## Compliance and State Safety

These are the project's required practices. The lab environment uses a local
backend by design; any non-lab environment must satisfy the remote-backend
requirements below before it provisions resources.

- Remote backends **must** have encryption at rest enabled
- Remote backends **must** have state locking enabled to prevent concurrent modifications
- Sensitive variables are marked `sensitive = true` and never committed
- Secrets are injected via `TF_VAR_*` environment variables
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

Every push and pull request runs three checks:

| Check | Tool | Command |
|-------|------|---------|
| Format | `tofu fmt` | `tofu fmt -check -recursive` |
| Validate | `tofu validate` | Per-environment `tofu init -backend=false && tofu validate` |
| Lint | [TFLint](https://github.com/terraform-linters/tflint) | `tflint --recursive` |

All checks must pass before a pull request can be merged.

## Contributing

1. Branch from `main` with a descriptive name (e.g., `feature/add-hcloud-provider`, `fix/libvirt-network`)
2. Run `tofu fmt -recursive` and `tofu validate` locally before committing
3. Open a pull request — CI must pass before merge
4. Use clear, imperative commit messages (e.g., *Add libvirt-vm module*, *Fix cloud-init hostname injection*)

See the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for the full checklist.

## Security

To report a vulnerability, see [SECURITY.md](.github/SECURITY.md).

## License

Apache 2.0 — see [LICENSE](LICENSE).