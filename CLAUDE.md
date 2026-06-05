# CLAUDE.md — `infra`

OpenTofu infrastructure provisioning: VM lifecycle, networking, storage
allocation via [`dmacvicar/libvirt`](https://github.com/dmacvicar/terraform-provider-libvirt)
(KVM/libvirt). Defines what gets created and destroyed; intentionally
decoupled from configuration management.

Two operating models coexist:

- **Ubuntu VMs** (`modules/libvirt-vm`) — cloud-init bootstrap, then
  hardened/configured by the `automation` (Ansible) repo. The infra ↔
  config-management split (ADR-0004).
- **Talos Linux Kubernetes** (`modules/talos-cluster`) — an immutable,
  API-only OS configured entirely by a declarative machine config via
  the `siderolabs/talos` provider. **Intentionally NOT Ansible-managed**
  — there is no host to SSH into (ADR-0013/0014/0015).

Companions: `automation` (Ansible), `runbooks` (ad-hoc operator scripts).

**OpenTofu only.** All commands are `tofu`. Never write "terraform" as
the active tool. HCL, the `.tf` extension, `terraform.tfvars`, the
`.terraform/` directory, and the `terraform { }` block are shared
ecosystem artifacts — not Terraform references.

## Repository layout

```
infra/
├── modules/libvirt-vm/         # KVM/libvirt Ubuntu VM provisioning module
├── modules/talos-cluster/      # Talos Linux Kubernetes on libvirt (siderolabs/talos)
├── environments/{lab,production,talos-lab}/
├── scripts/init-backend.sh
├── docs/adr/                   # Architecture Decision Records (read first)
├── docs/talos-cis-kubernetes.md # Talos hardening -> CIS Kubernetes mapping
└── .github/                    # CI, PR/issue templates, copilot
```

## Architecture Decision Records

Standing decisions — provider pin, backend strategy, module layout,
cloud-init defaults — live in [`docs/adr/`](docs/adr/). **Read the
relevant ADR before changing a convention.** Changing a decision means
writing a new ADR that supersedes the old one, not silently editing the
underlying code.

| ID | Title |
|----|-------|
| [0001](docs/adr/0001-use-opentofu-not-terraform.md) | Use OpenTofu, not Terraform |
| [0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md) | Pin `dmacvicar/libvirt` to `~> 0.8.0` |
| [0003](docs/adr/0003-state-backend-strategy.md) | State backend strategy |
| [0004](docs/adr/0004-cloud-init-bootstrap-conventions.md) | Cloud-init bootstrap conventions |
| [0005](docs/adr/0005-module-and-environment-layout.md) | Module and environment layout |
| [0006](docs/adr/0006-code-audit-2026-05.md) | Code audit 2026-05 findings |
| [0007](docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md) | Set `meta_data` on `libvirt_cloudinit_disk` |
| [0008](docs/adr/0008-omit-graphics-from-libvirt-domain-by-default.md) | Omit `graphics` from `libvirt_domain` by default |
| [0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md) | Begin `dmacvicar/libvirt` 0.9.x migration evaluation |
| [0010](docs/adr/0010-permit-module-supporting-files.md) | Permit module-local supporting files and ship the graphics override |
| [0011](docs/adr/0011-realize-production-s3-backend.md) | Realize the production S3 remote state backend |
| [0012](docs/adr/0012-libvirt-0.9-schema-diff-inventory.md) | `dmacvicar/libvirt` 0.9.x schema-diff inventory (Proposed) |
| [0013](docs/adr/0013-adopt-talos-linux.md) | Adopt Talos Linux for the Kubernetes layer (coexists with libvirt/Ubuntu) |
| [0014](docs/adr/0014-pin-siderolabs-talos-provider.md) | Pin `siderolabs/talos` to `~> 0.11.0` |
| [0015](docs/adr/0015-talos-machineconfig-as-code-and-secrets.md) | Talos machine-config-as-code and secret handling |
| [0016](docs/adr/0016-migrate-libvirt-provider-to-0.9.md) | Migrate `dmacvicar/libvirt` to `~> 0.9.0` |

## Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Module directories | lowercase, hyphenated by provider/concern | `libvirt-vm` |
| Environment directories | lowercase, single word | `lab`, `production` |
| Variables, resources, outputs, locals | `snake_case` | `libvirt_vm_vcpus`, `libvirt_domain.vm` |
| Resource labels | The role within the module, not the type | `libvirt_volume.root` |

## HCL style

- 2-space indentation, no tabs
- One blank line between top-level blocks; no trailing blank line at EOF
- Every variable: `description` + `type`. `default` only when a sensible
  default exists
- Every output: `description`
- Mark sensitive values with `sensitive = true`; never hardcode
  credentials
- Use `locals {}` for computed/derived values; do not inline complex
  expressions in resource arguments
- No environment-specific hardcoded values in resource blocks — reference
  variables or locals. Structural constants intrinsic to the module's
  contract (e.g. the qcow2 `target.format.type`, the domain `type = "kvm"`,
  the serial console literals) may stay inline; the goal is portability across
  environments, not promoting every constant to a variable (ADR-0005)

Example variable:

```hcl
variable "memory_mib" {
  description = "Memory allocated to the VM in MiB."
  type        = number
  default     = 2048
}
```

Example output:

```hcl
output "ip_address" {
  description = "VM IP address from its first DHCP lease."
  value       = data.libvirt_domain_interface_addresses.vm.interfaces[0].addrs[0].addr
}
```

## Module structure

Every module **must** contain at least these five files:

| File | Purpose |
|------|---------|
| `main.tf` | Resource + data-source definitions |
| `variables.tf` | Input variables (typed, described, validated) |
| `outputs.tf` | Output values (described) |
| `versions.tf` | `required_version` + `required_providers` |
| `README.md` | Usage example, inputs/outputs table, notes |

A module may also carry supporting artifacts that belong to its
contract: template files referenced from within the module (e.g.
`cloud_init.cfg`) and a `tests/` directory of native OpenTofu tests
(`*.tftest.hcl`). See [ADR-0005](docs/adr/0005-module-and-environment-layout.md).

Modules must be self-contained and reusable. They must not configure
providers, hardcode environment-specific values, or depend on paths
outside the module directory.

## Environment root structure

Every environment under `environments/` **must** contain:

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration + module calls |
| `variables.tf` | Variable declarations (typed, described) |
| `outputs.tf` | Output declarations (described) |
| `versions.tf` | `required_version` + `required_providers` |
| `backend.tf` | State backend configuration |
| `terraform.tfvars` | Non-secret defaults (tracked in git) |
| `.terraform.lock.hcl` | Provider dependency lock (tracked in git) |

## State management

- **Lab** uses a local backend. Acceptable for single-operator iteration.
- **Non-lab** environments require a remote backend with encryption at
  rest and state locking.
- For S3-compatible backends: prefer `use_lockfile = true` (OpenTofu
  1.10+ native locking) over `dynamodb_table`; prefer the
  `endpoints = { s3 = "…" }` map over the deprecated top-level
  `endpoint = "…"`. See [ADR-0003](docs/adr/0003-state-backend-strategy.md).
- Never manually edit state — use `tofu state mv`, `tofu state rm`, or
  `tofu import`.

## Secrets

- Mark sensitive variables `sensitive = true`
- Never commit `.tfvars` files containing secrets
- Inject secrets via `TF_VAR_<name>` environment variables in CI and
  production
- Use external secret stores (Vault, AWS Secrets Manager) for production
  credentials; `terraform.tfvars` carries non-secret defaults only

## Provider pinning

Pessimistic constraint in every `versions.tf`. For pre-1.0 providers,
pin at the **patch** level — a minor-version bump is the provider
author's signal that breaking changes have shipped
([ADR-0002](docs/adr/0002-pin-libvirt-provider-to-0.8.md)):

```hcl
required_providers {
  libvirt = {
    source  = "dmacvicar/libvirt"
    version = "~> 0.9.0" # pre-1.0, patch-pinned (ADR-0002; bumped 0.8->0.9 in ADR-0016)
  }
  talos = {
    source  = "siderolabs/talos"
    version = "~> 0.11.0" # pre-1.0, patch-pinned (ADR-0014)
  }
}
```

## Common commands

```bash
tofu init                  # Initialize working directory; download providers
tofu plan                  # Preview changes
tofu apply                 # Apply planned changes
tofu destroy               # Destroy all managed resources
tofu fmt -recursive        # Format HCL
tofu validate              # Validate configuration
tofu state list            # List resources in state
tofu output                # Show output values
```

## Quality

| Tool | Purpose | Command |
|------|---------|---------|
| `tofu fmt` | HCL formatting | `tofu fmt -check -recursive` |
| `tofu validate` | Syntax + type | Per-env `tofu init -backend=false && tofu validate` |
| `tflint` | Lint | `tflint --recursive` |
| Trivy | IaC misconfiguration scan | `trivy config . --severity HIGH,CRITICAL` |
| gitleaks | Secret scan (full working tree) | `gitleaks dir .` (CI pins the image by digest) |
| `tofu test` | Module tests (mock providers; no live host) | `tofu test` per module |
| pre-commit | Hygiene | `pre-commit run --all-files` |

CI enforces all of these on every push and pull request (plus a CodeQL scan).

## Workflow

1. Branch from `main` with a descriptive name (`feature/add-hcloud-provider`,
   `fix/libvirt-network`, `adr/0007-…`).
2. Make changes; run `tofu fmt` + `tofu validate` locally.
3. Open a pull request — CI must pass before merge.
4. Imperative commit subjects (`Add libvirt-vm module`, `Fix cloud-init
   hostname injection`).

## Notes for AI assistants

- Read existing files before modifying them.
- Read the relevant ADR before changing a standing convention; if the
  decision should change, write a new ADR that supersedes it rather than
  silently editing code.
- Never commit secrets or state files — check `.gitignore` and variable
  sensitivity.
- Never `tofu apply` without first reviewing `tofu plan`.
- Use OpenTofu terminology consistently (`tofu`, "OpenTofu"); never
  reference Terraform as the active tool in docs or comments.
- Pin providers with `~>`. For pre-1.0 providers, pin at the patch level
  (see ADR-0002).
- Every variable needs `description` and `type`; every output needs
  `description`. No exceptions.
- For the production S3 backend, prefer `use_lockfile = true` and the
  `endpoints = { s3 = "…" }` map (ADR-0003 and ADR-0006 Finding 1).
