# `production` environment

Defines **no resources yet** — the backend is currently a local
placeholder. Per
[ADR-0003](../../docs/adr/0003-state-backend-strategy.md), production
requires a remote, locked, encrypted state backend.

## Backend setup (prerequisite)

1. Provision an S3-compatible bucket with:
   - Server-side encryption at rest (AES-256 or KMS)
   - Versioning enabled (state-rollback safety)
   - Public access blocked
   - `use_lockfile = true` (native S3 locking, OpenTofu 1.10+; preferred
     over `dynamodb_table`)

2. Edit [`backend.tf`](./backend.tf) — replace the local block with the
   S3 block (the commented example in the file is a starting point).

3. Initialize:

   ```bash
   export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..."
   ../../scripts/init-backend.sh production
   ```

## Apply workflow (once the backend is live)

```bash
export TF_VAR_ssh_public_key="$(vault kv get -field=key secret/ssh/production)"
tofu plan -out=tfplan.binary
tofu apply tfplan.binary       # apply the saved plan; avoids plan/apply race
```

Secrets via `TF_VAR_*` from the org secret manager. `terraform.tfvars`
holds non-secret defaults only. Drift detection is out-of-band (cron
`tofu plan`); automated reconciliation is the
`state-reconciliation-loop` pattern in
[`platform-blueprint`](https://github.com/rmednitzer/platform-blueprint).

Reviews assigned via
[`../../.github/CODEOWNERS`](../../.github/CODEOWNERS).
