# ADR-0003: State backend strategy (local lab, S3-compatible production)

- **Status**: Accepted
- **Date**: 2026-05-24

## Context

OpenTofu state files contain the canonical record of what infrastructure exists
and, in places, sensitive values (e.g., generated passwords, cloud-init
material). The backend determines where state lives, who can read it, whether
it is locked during writes, and whether it is encrypted at rest.

`infra-ops` has two environments with different operational needs:

- **Lab** — single operator, fast iteration, transient infrastructure, no
  shared-modification risk. Losing the state file means destroying and
  re-creating a few VMs; the cost is low.
- **Production** — eventual multi-operator access, durable infrastructure,
  high cost of state loss or corruption, and a hard requirement that
  concurrent applies cannot race.

OpenTofu supports several backends. For this project the credible options are:

| Backend | Locking | Encryption at rest | Notes |
|---------|---------|--------------------|-------|
| `local` | OS file lock | None (filesystem perms only) | Acceptable for single-operator use |
| `s3` (AWS S3 or compatible: MinIO, Ceph RGW) | DynamoDB table **or** native `use_lockfile` (OpenTofu 1.10+) | SSE (AES-256, KMS) | Standard production choice |
| `consul` / `etcd` | Native | Cluster-dependent | Adds a dependency we do not otherwise need |

The 0.x and 1.x backend names are inherited language artifacts (see ADR-0001);
OpenTofu reads and writes the same `backend "s3"` syntax.

## Decision

- **Lab** uses a **local** backend. `backend "local" { path = "terraform.tfstate" }`
  in `environments/lab/backend.tf`. State files and `.terraform/` are
  gitignored.
- **Production** uses an **S3-compatible** backend with:
  - **State locking** via `use_lockfile = true` (native S3 conditional writes,
    OpenTofu 1.10+) — preferred. `dynamodb_table` is acceptable when
    transitioning from a legacy configuration, but new deployments should
    skip DynamoDB.
  - **Encryption at rest** required (`encrypt = true` for AWS-side SSE; the
    bucket must additionally enforce server-side encryption via bucket policy
    or default encryption settings).
  - **Versioning** enabled on the bucket so accidental state deletion is
    recoverable.
  - The modern `endpoints = { s3 = "…" }` map attribute when targeting a
    non-AWS S3 implementation. The top-level `endpoint = "…"` attribute is
    deprecated.
  - `use_path_style = true` for implementations that don't support virtual-host
    bucket URLs. The legacy `force_path_style` is deprecated.
- **Production** ships a **local placeholder backend** in `backend.tf` until
  the real bucket is provisioned. The environment must not host real
  infrastructure until the placeholder is replaced.

Credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or instance-role
credentials in CI) are passed via environment variables — never committed.

## Consequences

**Positive**

- Lab stays frictionless; one command (`tofu init && tofu plan`) gets going.
- Production state is durable, locked, and encrypted by design.
- The S3 backend works against any S3-compatible store, so the choice of
  provider (AWS, MinIO on-prem, Ceph RGW, Hetzner Object Storage) is
  deferrable.
- Using `use_lockfile` removes the need to operate a DynamoDB table, which
  cuts AWS surface area and cost for non-AWS deployments.

**Negative**

- Lab state on a single machine is a single point of failure for lab work.
  Mitigation: lab infrastructure is by definition reproducible from `main.tf`.
- Two distinct `backend.tf` files (lab and production) mean every environment
  carries some configuration drift risk. CI validates both per-environment.
- `use_lockfile` requires OpenTofu **1.10 or newer** at apply time. The
  current pin (`required_version = ">= 1.6"`) does not enforce this; the
  production environment's `versions.tf` should be bumped to `>= 1.10` when
  the S3 backend is wired up. See ADR-0006.

## References

- [OpenTofu S3 backend documentation](https://opentofu.org/docs/language/settings/backends/s3/)
- [OpenTofu state locking guide](https://opentofu.org/docs/language/state/locking/)
- [OpenTofu state encryption (1.7+)](https://opentofu.org/docs/language/state/encryption/)
- `scripts/init-backend.sh` — per-environment init helper
