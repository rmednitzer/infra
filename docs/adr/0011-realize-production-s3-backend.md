# ADR-0011: Realize the production S3 remote state backend

- **Status**: Accepted
- **Date**: 2026-05-30

## Context

[ADR-0003](0003-state-backend-strategy.md) decided the state-backend
strategy: lab uses a local backend; production uses an S3-compatible
remote backend with native locking, encryption at rest, and versioning.
That ADR also said production would ship a **local placeholder backend**
"until the real bucket is provisioned," and that production "must not
host real infrastructure until the placeholder is replaced."

The placeholder has been in `environments/production/backend.tf` since
the repo was scaffolded. The 2026-05 audit
([ADR-0006](0006-code-audit-2026-05.md)) and the
[`audit/2026-05-27-engagement.md`](../../audit/2026-05-27-engagement.md)
record both list "production S3 backend wiring" (F14) as deferred. The
adjacent Talos work ([ADR-0013](0013-adopt-talos-linux.md),
[ADR-0015](0015-talos-machineconfig-as-code-and-secrets.md)) puts
`talos_machine_secrets` — cluster CA keys and bootstrap tokens — into
OpenTofu state. A production Talos cluster therefore needs the remote,
encrypted, locked backend to actually exist, not merely be planned.

This ADR realizes the ADR-0003 production decision. It does **not**
change the strategy; it implements it.

## Decision

Replace the production placeholder `backend "local"` with the real
`backend "s3"` in `environments/production/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "rmednitzer-infra-tfstate-prod"
    key    = "production/terraform.tfstate"
    region = "us-east-1"
    endpoints = {
      s3 = "https://s3.us-east-1.amazonaws.com"
    }
    encrypt        = true
    use_lockfile   = true
    use_path_style = true
  }
}
```

Specifics, all per ADR-0003 and `CLAUDE.md`:

- **`use_lockfile = true`** — OpenTofu 1.10+ native S3 conditional-write
  locking. **Not** `dynamodb_table`; new deployments skip DynamoDB.
- **`endpoints = { s3 = "…" }`** — the map form. **Not** the deprecated
  top-level `endpoint = "…"` attribute.
- **`encrypt = true`** — server-side encryption at rest. The bucket must
  additionally enforce SSE via a bucket policy / default-encryption
  setting (out-of-band, documented in the env README).
- **`use_path_style = true`** — path-style URLs so the same block works
  against non-AWS S3 implementations (MinIO, Ceph RGW, Hetzner Object
  Storage). The legacy `force_path_style` is deprecated.

Every value in the block is **non-secret** configuration (bucket, key,
region, endpoint) and is committed. **Credentials** (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, or an instance role) are injected via the
environment in CI and on production/operator hosts and are never
committed.

**CI keeps using `tofu init -backend=false`.** A real `tofu init` against
this backend needs network access, the bucket to exist, and credentials;
none of those are available (or desirable) in the validate/lint CI jobs.
`tofu validate -backend=false` parses and type-checks the backend block
without contacting S3, so CI still gates the configuration.

`environments/production/versions.tf` already declares
`required_version = ">= 1.10"` (raised in a prior change, see the
CHANGELOG), which is the floor `use_lockfile` requires. No version bump
is needed; this ADR records that the prerequisite is satisfied.

`scripts/init-backend.sh` is updated: the old guard that warned when
production still carried `backend "local"` is kept (now as a
regression guard) and a second guard warns when the S3 backend is
configured but no AWS credentials are present in the environment, before
the operator hits the opaque AWS credential error.

## Consequences

**Positive**

- Production state is durable, locked, and encrypted by design — the
  ADR-0003 production posture is now real, not aspirational.
- The Talos subsystem can safely keep `talos_machine_secrets` in
  production state, because that state is now an encrypted, access-
  controlled, versioned object (ADR-0015).
- The block is S3-implementation-agnostic; the choice of AWS vs. MinIO
  vs. Ceph RGW vs. Hetzner remains a config change to `endpoints` +
  `region`, not a code change.

**Negative**

- `tofu init` for production now **requires** credentials and a live
  bucket; an operator who runs it without `AWS_*` set gets a backend
  error. Mitigated by the new `init-backend.sh` credential guard and the
  env README.
- The committed `bucket` / `region` / `endpoints` are placeholders for
  the org's real values; an operator must confirm or replace them before
  the first real `init`. They are non-secret, so committing concrete
  defaults is acceptable and reviewable.
- Two distinct `backend.tf` files (lab local, production S3) still carry
  some configuration-drift risk, as ADR-0003 noted. CI validates both.

## References

- [ADR-0003 — State backend strategy](0003-state-backend-strategy.md)
- [ADR-0006 — Code audit 2026-05 findings](0006-code-audit-2026-05.md)
- [ADR-0015 — Talos machine-config-as-code + secret handling](0015-talos-machineconfig-as-code-and-secrets.md)
- [OpenTofu S3 backend documentation](https://opentofu.org/docs/language/settings/backends/s3/)
- [OpenTofu state locking guide](https://opentofu.org/docs/language/state/locking/)
- `environments/production/backend.tf`, `environments/production/README.md`
- `scripts/init-backend.sh`
