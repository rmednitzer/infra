# Environment: `production`

Production environment. Defines **no resources yet** — the backend is
currently a local placeholder. Before provisioning, the remote backend below
**must** be configured and initialized.

## Status

Per [ADR-0003: State backend strategy](../../docs/adr/0003-state-backend-strategy.md),
production requires a remote, locked, encrypted state backend. The shipped
`backend.tf` contains a local placeholder block plus a commented example
for an S3-compatible backend.

This environment has no Terraform resources defined (intentional placeholder).
Adding resources before the backend is configured is a defect; CI does not
catch it.

## Backend configuration

1. Provision an S3-compatible bucket with:
   - Server-side encryption at rest (AES-256 or KMS).
   - Versioning enabled — required for state rollback.
   - Public access blocked.
   - State locking — prefer `use_lockfile = true` (OpenTofu 1.10+ native S3
     locking) over `dynamodb_table`.

2. Edit `backend.tf` to replace the local block with the S3 block. The
   commented example in the file is a starting point — fill in `bucket`,
   `region`, `endpoints` (if non-AWS S3), and the `use_lockfile = true`
   flag.

3. Set backend credentials via environment:

   ```bash
   export AWS_ACCESS_KEY_ID="..."
   export AWS_SECRET_ACCESS_KEY="..."
   ```

4. Initialize:

   ```bash
   ../../scripts/init-backend.sh production
   ```

## Prerequisites for resources (once the backend is live)

Same as the lab environment, plus:

- A change-management process — production changes go through a PR with an
  approving reviewer (see
  [`../../.github/CODEOWNERS`](../../.github/CODEOWNERS)).
- A break-glass procedure for cases where state is locked by a stale run.
- An incident contact and on-call rotation defined outside this repo.

## Usage (after backend is configured)

```bash
cd environments/production

export TF_VAR_ssh_public_key="$(vault kv get -field=key secret/ssh/production)"

# Use the helper to init against the remote backend.
../../scripts/init-backend.sh production

# Always plan first, save the plan.
tofu plan -out=tfplan.binary

# Apply the saved plan only — avoids races between plan and apply.
tofu apply tfplan.binary
```

## Secrets

- All secrets injected via `TF_VAR_*` environment variables sourced from the
  organization's secret manager (Vault, AWS Secrets Manager, …).
- `terraform.tfvars` contains **non-secret defaults only** and is committed.
- Backend credentials are session-scoped, never written to the repo.

## State safety

- Versioning on the bucket allows state rollback if `tofu apply` corrupts
  state.
- The lock file prevents concurrent `apply` runs from racing.
- Anyone with backend credentials can read state — restrict access tightly.

## Drift detection

Production state drift is monitored out-of-band (cron `tofu plan` against
the locked state, output reviewed manually). Automated drift reconciliation
is **not** in scope here — see the related pattern in
[`platform-blueprint`](https://github.com/rmednitzer/platform-blueprint)
(`state-reconciliation-loop`).
