# `production` environment

Defines **no resources yet**, but the state backend is now the real
**S3-compatible remote backend** (no longer a local placeholder). Per
[ADR-0003](../../docs/adr/0003-state-backend-strategy.md) and the
realization decision [ADR-0011](../../docs/adr/0011-realize-production-s3-backend.md),
production uses a remote, locked, encrypted state backend.

[`backend.tf`](./backend.tf) declares `backend "s3"` with:

- `use_lockfile = true` — native S3 conditional-write locking (OpenTofu
  1.10+); **not** `dynamodb_table`.
- `endpoints = { s3 = "…" }` — the map form; **not** the deprecated
  top-level `endpoint`.
- `encrypt = true` — server-side encryption at rest.
- `use_path_style = true` — path-style URLs for non-AWS S3
  implementations (the legacy `force_path_style` is deprecated).

Every value in `backend.tf` is **non-secret** config (bucket, key,
region, endpoint). Credentials are injected via `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` (or an instance role) — never committed. CI keeps
using `tofu init -backend=false`, so `tofu validate` runs without
contacting S3; a real `tofu init` needs the bucket to exist and the AWS
credentials to be set.

`var.libvirt_uri` has **no default** in production (unlike lab, which
defaults to `qemu:///system`): `TF_VAR_libvirt_uri` is mandatory and must
be set before any `tofu plan`/`apply` so the production KVM host is always
named explicitly, never assumed.

## Backend setup (prerequisite)

The `backend "s3"` block already ships in [`backend.tf`](./backend.tf).
What remains is the org-specific bucket and credentials.

1. Provision the S3-compatible bucket named in `backend.tf` with:
   - Server-side encryption at rest (AES-256 or KMS) enforced by a
     bucket policy / default-encryption setting
   - Versioning enabled (state-rollback safety)
   - Public access blocked

2. Update the placeholder `bucket` / `key` / `region` / `endpoints` in
   [`backend.tf`](./backend.tf) to the provisioned values if they differ
   from the defaults. `use_lockfile`, `encrypt`, and `use_path_style`
   stay as shipped.

3. Initialize with credentials in the environment:

   ```bash
   export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..."
   ../../scripts/init-backend.sh production
   ```

   The helper warns if AWS credentials are absent before it reaches the
   opaque AWS error.

## Apply workflow (once the backend is live)

```bash
export TF_VAR_ssh_public_key="$(vault kv get -field=key secret/ssh/production)"
tofu plan -out=tfplan.binary
tofu apply tfplan.binary       # apply the saved plan; avoids plan/apply race
```

Secrets via `TF_VAR_*` from the org secret manager. `terraform.tfvars`
holds non-secret defaults only. Drift detection is out-of-band (cron
`tofu plan`); automated reconciliation is not wired up here.

Reviews assigned via
[`../../.github/CODEOWNERS`](../../.github/CODEOWNERS).
