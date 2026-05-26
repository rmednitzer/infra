# infra

[![CI](https://github.com/rmednitzer/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/rmednitzer/infra/actions/workflows/ci.yml)

Infrastructure provisioning for KVM/libvirt VMs, networks, and storage,
managed with [OpenTofu](https://opentofu.org/). Compliance-aligned
practice, CI-gated changes, documented module interfaces.

Companions:
[`automation`](https://github.com/rmednitzer/automation) (Ansible
configuration + hardening) and
[`runbooks`](https://github.com/rmednitzer/runbooks) (ad-hoc operator
scripts).

The rationale behind every standing decision — OpenTofu over Terraform,
the `dmacvicar/libvirt` `~> 0.8.0` pin, the state-backend strategy, the
cloud-init baseline, the module/environment layout — lives in
[`docs/adr/`](docs/adr/).

## Scope

**Infrastructure layer only** — what gets created and destroyed.
Decoupled from configuration management (Ansible, Salt).

Current providers:

- **KVM/libvirt** via [`dmacvicar/libvirt`](https://github.com/dmacvicar/terraform-provider-libvirt),
  pinned `~> 0.8.0` ([ADR-0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md))

Planned: Hetzner Cloud (`hetznercloud/hcloud`) and additional providers
as required.

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) ≥ 1.6 (1.12 is
  current; production will require ≥ 1.10 once the S3 backend is wired
  up — see [ADR-0003](docs/adr/0003-state-backend-strategy.md))
- A KVM/libvirt host with `qemu-system` and `libvirtd` running; the
  `default` storage pool and network must already exist — the module
  does not create them ([ADR-0006 Finding 7](docs/adr/0006-code-audit-2026-05.md))
- A cloud-init compatible base image — e.g.
  [Ubuntu 24.04 noble cloud image](https://cloud-images.ubuntu.com/noble/current/)
- An SSH key pair for VM access
- [TFLint](https://github.com/terraform-linters/tflint) — optional for
  local linting

## Quick start

```bash
cd environments/lab
tofu init
export TF_VAR_ssh_public_key="ssh-ed25519 AAAA..."
tofu plan
tofu apply
```

## Repository structure

```
infra/
├── modules/libvirt-vm/      # KVM/libvirt VM provisioning module
├── environments/
│   ├── lab/                 # Local state, single-operator iteration
│   └── production/          # Remote backend required; local placeholder, no resources yet
├── scripts/init-backend.sh  # Per-environment init helper
├── docs/adr/                # Architecture Decision Records
└── .github/workflows/ci.yml # CI: fmt + validate + tflint + Trivy + pre-commit
```

## Modules

### [`libvirt-vm`](modules/libvirt-vm/)

KVM/libvirt VM with cloud-init, configurable CPU/memory/root disk, and
optional additional data disks. Full inputs and outputs:
[module README](modules/libvirt-vm/README.md).

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vm_name` | `string` | — | VM hostname |
| `vcpus` | `number` | `2` | Virtual CPU count |
| `memory_mib` | `number` | `2048` | Memory in MiB |
| `disk_size_gib` | `number` | `20` | Root disk size in GiB |
| `base_image` | `string` | — | Path or URL to cloud image |
| `ssh_public_key` | `string` | — | SSH public key (sensitive) |

## Environments

| Environment | Backend | Status | Notes |
|-------------|---------|--------|-------|
| [`lab`](environments/lab/) | Local | Active | Single-operator iteration on a local KVM host |
| [`production`](environments/production/) | Remote S3-compatible — *required, not yet configured* | Placeholder | No resources yet; `backend.tf` ships a local placeholder and must be switched before any production resource is added |

Each environment ships its own `backend.tf`, `variables.tf`,
`terraform.tfvars` (non-secret defaults only), `versions.tf`, and a
committed `.terraform.lock.hcl`. Initialize via the helper:

```bash
./scripts/init-backend.sh lab
```

For production, configure the S3 backend (locked + encrypted at rest —
see [ADR-0003](docs/adr/0003-state-backend-strategy.md)), set
credentials, then init:

```bash
export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..."
./scripts/init-backend.sh production
```

## Architecture decisions

Standing decisions live in [`docs/adr/`](docs/adr/). Each ADR captures
the context, the decision, and the consequences of one significant
choice. Adding a new significant decision means writing a new ADR, not a
README section.

| ID | Title |
|----|-------|
| [0001](docs/adr/0001-use-opentofu-not-terraform.md) | Use OpenTofu, not Terraform |
| [0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md) | Pin `dmacvicar/libvirt` to `~> 0.8.0` |
| [0003](docs/adr/0003-state-backend-strategy.md) | State backend strategy (local lab, S3-compatible production) |
| [0004](docs/adr/0004-cloud-init-bootstrap-conventions.md) | Cloud-init bootstrap conventions |
| [0005](docs/adr/0005-module-and-environment-layout.md) | Module and environment layout |
| [0006](docs/adr/0006-code-audit-2026-05.md) | Code audit 2026-05 findings |

## State safety

- Remote backends **must** have encryption at rest enabled
- Remote backends **must** have state locking — prefer `use_lockfile =
  true` (native S3 locking, OpenTofu 1.10+) over `dynamodb_table`
- Sensitive variables marked `sensitive = true` and never committed
- Secrets injected via `TF_VAR_*` environment variables
- Cloud-init bootstraps every VM into a hardened state: no password
  auth, no root SSH, locked default user, key-only access
- All changes flow through CI-gated pull requests

## Common commands

| Command | Purpose |
|---------|---------|
| `tofu init` | Initialize working directory, download providers |
| `tofu plan` | Preview changes |
| `tofu apply` | Apply planned changes |
| `tofu destroy` | Destroy all managed resources |
| `tofu fmt -recursive` | Format HCL files |
| `tofu validate` | Validate configuration syntax |
| `tofu state list` | List resources in state |
| `tofu output` | Show output values |

## CI / quality

| Check | Tool | Command |
|-------|------|---------|
| Format | `tofu fmt` | `tofu fmt -check -recursive` |
| Validate | `tofu validate` | Per-env `tofu init -backend=false && tofu validate` |
| Lint | [TFLint](https://github.com/terraform-linters/tflint) | `tflint --recursive` |
| Security | [Trivy](https://aquasecurity.github.io/trivy/) | `trivy config . --severity HIGH,CRITICAL` |
| Hygiene | [pre-commit](https://pre-commit.com/) | `pre-commit run --all-files` |

All checks must pass before a PR can merge.

## Development

```bash
pip install pre-commit && pre-commit install
export TFTOOL=tofu        # point pre-commit-terraform at OpenTofu
pre-commit run --all-files
```

Hook set: [`.pre-commit-config.yaml`](.pre-commit-config.yaml). OpenTofu
version pinned via [`.opentofu-version`](.opentofu-version) (`1.12.0`).

## Governance

| File | Purpose |
|------|---------|
| [`CLAUDE.md`](./CLAUDE.md) | HCL style, OpenTofu policy, conventions |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Workflow, ADR expectations |
| [`CHANGELOG.md`](./CHANGELOG.md) | Keep a Changelog 1.1.0 |
| [`docs/adr/`](./docs/adr/) | Architecture Decision Records |
| [`.github/SECURITY.md`](./.github/SECURITY.md) | Vulnerability reporting |
| [`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md) | PR checklist |
| [`.github/CODEOWNERS`](./.github/CODEOWNERS) | Review assignment |
| [`LICENSE`](./LICENSE) / [`NOTICE`](./NOTICE) | Apache 2.0 |
