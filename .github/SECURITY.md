# Security Policy

Security fixes apply to the current `main` branch only.

## In scope

- Secrets in state files — credentials or sensitive values written to
  `.tfstate`
- Insecure provider configurations — missing TLS, unencrypted
  connections to libvirt or other providers
- Exposed infrastructure credentials — API keys, passwords, or private
  keys committed to the repository
- Missing encryption or locking on remote state backends
- Overly permissive security groups or firewall rules — unrestricted
  access (`0.0.0.0/0`) on sensitive ports
- Insecure cloud-init configurations — password authentication enabled,
  weak SSH configuration

## Reporting

Use [GitHub private vulnerability reporting](https://github.com/rmednitzer/infra/security/advisories/new).
Include the affected file path and line numbers, reproduction steps,
and an impact assessment.

We acknowledge within 5 business days and provide a remediation timeline
within 14 days.

## Best practices for contributors

- Never commit secrets, credentials, or private keys.
- Mark sensitive OpenTofu variables with `sensitive = true`.
- Use `TF_VAR_*` environment variables for secrets in CI pipelines.
- Ensure remote state backends have encryption at rest and access
  logging enabled; the project's full state-safety standard is captured
  in [ADR-0003](../docs/adr/0003-state-backend-strategy.md).
- The cloud-init bootstrap hardens every VM at provisioning time (no
  password auth, no root SSH, locked default user); changes to that
  baseline require updating
  [ADR-0004](../docs/adr/0004-cloud-init-bootstrap-conventions.md).
- Review `tofu plan` output carefully before applying changes to
  production.
