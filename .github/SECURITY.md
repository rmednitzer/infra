# Security Policy

Security fixes apply to the current `main` branch only.

## In scope

- Secrets in state files — credentials or sensitive values written to
  `.tfstate`
- Insecure provider configurations — missing TLS, unencrypted libvirt
  connections, weak provider auth
- Exposed infrastructure credentials — API keys, passwords, private
  keys committed to the repository
- Missing encryption or locking on remote state backends
- Overly permissive security groups or firewall rules — unrestricted
  access (`0.0.0.0/0`) on sensitive ports
- Insecure cloud-init configurations — password authentication enabled,
  root SSH allowed, weak SSH configuration

## Reporting

[GitHub private vulnerability reporting](https://github.com/rmednitzer/infra/security/advisories/new).
Include the affected file path, line numbers, reproduction steps, and
an impact assessment.

Acknowledgement within 5 business days; remediation timeline within 14
days.

## Best practices for contributors

- Never commit secrets, credentials, or private keys.
- Mark sensitive OpenTofu variables `sensitive = true`.
- Inject secrets via `TF_VAR_*` environment variables in CI.
- Remote state backends must have encryption at rest, state locking,
  and access logging — see
  [ADR-0003](../docs/adr/0003-state-backend-strategy.md).
- The cloud-init bootstrap hardens every VM at provisioning time (no
  password auth, no root SSH, locked default user). Changes to that
  baseline require updating
  [ADR-0004](../docs/adr/0004-cloud-init-bootstrap-conventions.md).
- Review `tofu plan` output carefully before applying to production.
