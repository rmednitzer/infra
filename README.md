# infra

[![CI](https://github.com/rmednitzer/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/rmednitzer/infra/actions/workflows/ci.yml)

Infrastructure provisioning for KVM/libvirt VMs, networks, and storage,
managed with [OpenTofu](https://opentofu.org/). The setup is
compliance-aligned, CI-gated, and ships documented module interfaces.

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

**Infrastructure layer only** — what gets created and destroyed. For
Ubuntu VMs this is decoupled from configuration management (Ansible,
Salt). For the Kubernetes layer it uses **Talos Linux**, an immutable,
API-only OS configured entirely as code (no Ansible — there is no host to
configure; [ADR-0013](docs/adr/0013-adopt-talos-linux.md)).

Current providers:

- **KVM/libvirt** via [`dmacvicar/libvirt`](https://github.com/dmacvicar/terraform-provider-libvirt),
  pinned `~> 0.8.0` ([ADR-0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md))
- **Talos Linux** via [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos),
  pinned `~> 0.11.0` ([ADR-0014](docs/adr/0014-pin-siderolabs-talos-provider.md))

Planned: Hetzner Cloud (`hetznercloud/hcloud`) and additional providers
as required.

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) ≥ 1.10 (every
  root pins `required_version = ">= 1.10"`; 1.12 is current). The 1.10
  floor matches the production S3 backend's `use_lockfile` requirement
  ([ADR-0003](docs/adr/0003-state-backend-strategy.md),
  [ADR-0011](docs/adr/0011-realize-production-s3-backend.md))
- A KVM/libvirt host with `qemu-system` and `libvirtd` running; the
  `default` storage pool and network must already exist — the module
  does not create them ([ADR-0006 Finding 7](docs/adr/0006-code-audit-2026-05.md))
- A cloud-init compatible base image — version-neutral across
  [Ubuntu 24.04 noble](https://cloud-images.ubuntu.com/noble/current/)
  and [Ubuntu 26.04 resolute](https://cloud-images.ubuntu.com/resolute/current/)
  (kernel 7.0); the shipped cloud-init is distro-neutral
- For the Talos Kubernetes layer: a
  [Talos disk image](https://factory.talos.dev/) and `talosctl`
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
├── modules/libvirt-vm/      # KVM/libvirt Ubuntu VM provisioning module
├── modules/talos-cluster/   # Talos Linux Kubernetes on libvirt (siderolabs/talos)
├── environments/
│   ├── lab/                 # Ubuntu VMs; local state, single-operator iteration
│   ├── production/          # Remote S3 backend (ADR-0011); no resources yet
│   └── talos-lab/           # Talos Kubernetes cluster; local state
├── scripts/init-backend.sh  # Per-environment init helper
├── docs/adr/                # Architecture Decision Records
├── docs/talos-cis-kubernetes.md # Talos hardening -> CIS Kubernetes mapping
└── .github/workflows/ci.yml # CI: fmt + validate + tflint + Trivy + pre-commit + tests
```

## Modules

### [`libvirt-vm`](modules/libvirt-vm/)

KVM/libvirt Ubuntu VM with cloud-init, configurable CPU/memory/root
disk, and optional additional data disks. The `base_image` is
version-neutral (Ubuntu 24.04 noble or 26.04 resolute). Full inputs and
outputs: [module README](modules/libvirt-vm/README.md).

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vm_name` | `string` | — | VM hostname |
| `vcpus` | `number` | `2` | Virtual CPU count |
| `memory_mib` | `number` | `2048` | Memory in MiB |
| `disk_size_gib` | `number` | `20` | Root disk size in GiB |
| `base_image` | `string` | — | Path or URL to cloud image (24.04 or 26.04) |
| `ssh_public_key` | `string` | — | SSH public key (sensitive) |

### [`talos-cluster`](modules/talos-cluster/)

A [Talos Linux](https://www.talos.dev/) Kubernetes cluster on libvirt:
VMs via `dmacvicar/libvirt` (booting the Talos image directly, no
cloud-init) plus the `siderolabs/talos` provider for machine secrets,
hardened machine config, apply, etcd bootstrap, and the exported
kube/talos configs. Immutable, API-only, **not Ansible-managed**
([ADR-0013](docs/adr/0013-adopt-talos-linux.md)). Hardened baseline
mapped to the CIS Kubernetes Benchmark in
[`docs/talos-cis-kubernetes.md`](docs/talos-cis-kubernetes.md). Full
inputs and outputs: [module README](modules/talos-cluster/README.md).

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | `string` | — | Cluster name |
| `cluster_endpoint` | `string` | — | Kubernetes API endpoint URL |
| `talos_image` | `string` | — | Path or URL to the Talos disk image |
| `control_plane_nodes` | `map(object)` | — | Control-plane node name → `{ip, mac, …}` |
| `worker_nodes` | `map(object)` | `{}` | Worker node name → `{ip, mac, …}` |

## Environments

| Environment | Backend | Status | Notes |
|-------------|---------|--------|-------|
| [`lab`](environments/lab/) | Local | Active | Ubuntu VMs; single-operator iteration on a local KVM host |
| [`production`](environments/production/) | Remote S3-compatible | Backend live, no resources | `backend.tf` ships the real `backend "s3"` (`use_lockfile`, encrypted; [ADR-0011](docs/adr/0011-realize-production-s3-backend.md)); needs the org bucket + AWS creds for a real `init` |
| [`talos-lab`](environments/talos-lab/) | Local | Active | Talos Kubernetes cluster (1 control-plane + 2 workers); secrets gitignored |

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
| [0007](docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md) | Set `meta_data` on `libvirt_cloudinit_disk` |
| [0008](docs/adr/0008-omit-graphics-from-libvirt-domain-by-default.md) | Omit `graphics` from `libvirt_domain` by default |
| [0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md) | Begin `dmacvicar/libvirt` 0.9.x migration evaluation |
| [0010](docs/adr/0010-permit-module-supporting-files.md) | Permit module-local supporting files and ship the graphics override |
| [0011](docs/adr/0011-realize-production-s3-backend.md) | Realize the production S3 remote state backend |
| [0012](docs/adr/0012-libvirt-0.9-schema-diff-inventory.md) | `dmacvicar/libvirt` 0.9.x schema-diff inventory (Proposed) |
| [0013](docs/adr/0013-adopt-talos-linux.md) | Adopt Talos Linux for the Kubernetes layer |
| [0014](docs/adr/0014-pin-siderolabs-talos-provider.md) | Pin `siderolabs/talos` to `~> 0.11.0` |
| [0015](docs/adr/0015-talos-machineconfig-as-code-and-secrets.md) | Talos machine-config-as-code and secret handling |

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
pip install -r requirements-dev.txt && pre-commit install
export PCT_TFPATH=tofu     # point pre-commit-terraform at OpenTofu
pre-commit run --all-files
```

Hook set: [`.pre-commit-config.yaml`](.pre-commit-config.yaml). OpenTofu
version pinned via [`.opentofu-version`](.opentofu-version) (`1.12.0`).
Pre-commit version pinned via
[`requirements-dev.txt`](requirements-dev.txt); Dependabot watches both
this file and the GitHub Actions workflow weekly.

## Governance

| File | Purpose |
|------|---------|
| [`CLAUDE.md`](./CLAUDE.md) | HCL style, OpenTofu policy, conventions |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Workflow, ADR expectations |
| [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) | Contributor Covenant 2.1 |
| [`CHANGELOG.md`](./CHANGELOG.md) | Keep a Changelog 1.1.0 |
| [`docs/adr/`](./docs/adr/) | Architecture Decision Records |
| [`SECURITY.md`](./SECURITY.md) / [`.github/SECURITY.md`](./.github/SECURITY.md) | Vulnerability reporting (root stub + policy) |
| [`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md) | PR checklist |
| [`.github/CODEOWNERS`](./.github/CODEOWNERS) | Review assignment |
| [`LICENSE`](./LICENSE) / [`NOTICE`](./NOTICE) | Apache 2.0 |
