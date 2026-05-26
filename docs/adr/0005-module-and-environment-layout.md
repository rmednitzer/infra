# ADR-0005: Module and environment layout

- **Status**: Accepted
- **Date**: 2026-05-24

## Context

OpenTofu does not enforce a project layout. Without a convention,
contributors reach for different patterns — variables in `main.tf`,
outputs scattered, provider blocks duplicated, READMEs inconsistent or
absent — and the codebase fragments.

We need a layout that is predictable (a contributor can open any module
and find its inputs, outputs, and version pins without searching),
separates **reusable infrastructure logic** (modules) from
**environment-specific composition** (roots), plays well with tooling
(`tofu fmt -recursive`, `tofu validate`, `tflint --recursive`, CI
matrices, dependency lock files), and stays small (five files per
module is plenty; prefer adding files when needed over splitting
prematurely).

## Decision

### Top-level layout

```
infra/
├── modules/<module-name>/      # Reusable building blocks
├── environments/<env-name>/    # Root configurations that compose modules
├── scripts/                    # Operational helpers (init-backend.sh, etc.)
├── docs/adr/                   # Architecture decision records
├── .github/                    # CI, issue/PR templates, dependabot
└── README.md, CLAUDE.md, …     # Top-level docs
```

### Module layout (every module)

Every module **must** contain exactly:

| File | Purpose |
|------|---------|
| `main.tf` | Resource and data-source definitions |
| `variables.tf` | Input variables — `type`, `description`, and validation where reasonable |
| `outputs.tf` | Output values — `description` |
| `versions.tf` | `required_version` + `required_providers` |
| `README.md` | Usage example, inputs/outputs table, notes |

Modules **must not**:

- Configure providers (`provider "x" { … }`) — that belongs in the calling root
- Hardcode environment-specific values (paths, hostnames, IPs)
- Depend on file paths outside the module directory (template files
  live inside the module — e.g. `cloud_init.cfg`)

### Environment root layout (every environment)

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

Secrets (`ssh_public_key`, credentials, API tokens) are injected via
`TF_VAR_<name>` environment variables, never via committed files.

### Naming

- Module directory names: lowercase, hyphenated by provider/concern
  (`libvirt-vm`; future: `hcloud-server`, `dns-zone`)
- Environment directory names: lowercase, single word
  (`lab`, `production`)
- Variables, resources, outputs, locals: `snake_case`
- Resource labels: the role within the module
  (`libvirt_volume.root`, `libvirt_domain.vm`), not the type

## Consequences

**Positive**

- A new contributor finds any input or output of any module in 30
  seconds.
- CI's validate matrix is trivial: iterate over `environments/*` and
  `modules/*` and run `tofu init -backend=false && tofu validate`.
- `tofu fmt -check -recursive` and `tflint --recursive` work without
  per-directory configuration.
- Modules stay reusable: the same `libvirt-vm` module serves lab today
  and could serve a hypothetical `staging/` environment tomorrow with
  no change.

**Negative**

- Five files per module is overhead for trivial modules (one resource,
  no inputs). We accept this for uniformity — the alternative is an
  "is this module conventional or not?" question on every PR.
- Environment roots duplicate the `terraform { required_providers { … } }`
  block from each module they call. OpenTofu's provider-resolution
  rules require this, but it is a place where version drift can hide.
  CI catches mismatches via `tofu init` failures.

## References

- [OpenTofu module structure recommendations](https://opentofu.org/docs/language/modules/develop/structure/)
- [HashiCorp's standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
  (the underlying convention, predating the fork)
- `CLAUDE.md` — AI-assistant guide; restates the convention
- `.github/copilot-instructions.md` — Copilot guide; restates the
  convention
