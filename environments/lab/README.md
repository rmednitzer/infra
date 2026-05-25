# Environment: `lab`

Lab environment for development and testing on a local KVM host with
**local state**. Not for production workloads.

## Backend

Local state file (`terraform.tfstate`) in this directory. State locking is
filesystem-based. The `.terraform.lock.hcl` file is committed; per-init
metadata under `.terraform/` is gitignored.

This choice is intentional — see
[ADR-0003: State backend strategy](../../docs/adr/0003-state-backend-strategy.md).

## Prerequisites

- A local KVM host (Linux) with `libvirtd` running, the `default` storage
  pool, and the `default` network defined. The `libvirt-vm` module does not
  create these — see
  [ADR-0006 Finding 7](../../docs/adr/0006-code-audit-2026-05.md).
- A cloud-init compatible base image accessible to `libvirtd`. The default
  is Ubuntu 24.04 (noble) — place it in the `default` pool or mount it on a
  path readable by `qemu`.
- An SSH key pair for VM access (the public key is injected via cloud-init).
- OpenTofu 1.6+ (1.12.0 pinned via `.opentofu-version` at the repo root).

## Usage

```bash
cd environments/lab

# Inject the SSH public key — never commit it.
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

# Initialize provider + lock file.
tofu init

# Preview.
tofu plan

# Apply.
tofu apply

# Tear down.
tofu destroy
```

## Variables

Lab-specific defaults live in `terraform.tfvars`. Non-secret defaults only —
the SSH public key is sensitive and **must** be passed via
`TF_VAR_ssh_public_key` or a non-committed `*.auto.tfvars` file.

| Variable | Default | Purpose |
|----------|---------|---------|
| `vm_name` | from tfvars | Hostname injected via cloud-init |
| `base_image` | Ubuntu 24.04 cloud image | Path or URL to the cloud-init image |
| `vcpus` | `2` | Virtual CPU count |
| `memory_mib` | `2048` | Memory in MiB |
| `disk_size_gib` | `20` | Root disk size in GiB |

See [`../../modules/libvirt-vm/README.md`](../../modules/libvirt-vm/README.md)
for the complete module API.

## State and secrets

- Local state — do not share `terraform.tfstate`. It contains resource IDs
  and (potentially) sensitive metadata.
- Secrets are injected only via `TF_VAR_*` environment variables. Never
  commit them to `terraform.tfvars` or check them into Git.

## Promotion to production

Resources defined here are **not** promoted directly. The `production/`
environment ships a separate backend (S3-compatible, encrypted, locked) and
a separate state — see [ADR-0003](../../docs/adr/0003-state-backend-strategy.md).
Resource definitions may be copied, but the state must remain isolated.
