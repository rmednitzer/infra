# Security Policy

## Supported Versions

Security fixes are applied to the current `main` branch. We do not backport fixes to prior configurations.

## Security Scope

The following are considered in-scope security concerns for this repository:

- **Secrets in state files** — Credentials or sensitive values inadvertently written to `.tfstate`
- **Insecure provider configurations** — Missing TLS, unencrypted connections to libvirt or other providers
- **Exposed infrastructure credentials** — API keys, passwords, or private keys committed to the repository
- **Missing encryption on state backends** — Remote backends without server-side encryption enabled
- **Overly permissive security groups or firewall rules** — Rules allowing unrestricted access (0.0.0.0/0) on sensitive ports
- **Insecure cloud-init configurations** — Password authentication enabled, weak SSH configuration

## Reporting a Vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/rmednitzer/infra-ops/security/advisories/new) to report security issues. This keeps the disclosure private until a fix is available.

Include in your report:
- A description of the vulnerability
- The affected file(s) and line numbers if applicable
- Steps to reproduce or exploit the issue
- Your assessment of the impact

We aim to acknowledge reports within 5 business days and provide a remediation timeline within 14 days.

## Security Best Practices for Contributors

- Never commit secrets, credentials, or private keys to this repository
- Mark sensitive OpenTofu variables with `sensitive = true`
- Use `TF_VAR_*` environment variables for secrets in CI pipelines
- Ensure state backends have encryption at rest and access logging enabled; the project's full state-safety standard is captured in [ADR-0003](../docs/adr/0003-state-backend-strategy.md)
- The cloud-init bootstrap hardens every VM at provisioning time (no password auth, no root SSH, locked default user); changes to that baseline require updating [ADR-0004](../docs/adr/0004-cloud-init-bootstrap-conventions.md)
- Review `tofu plan` output carefully before applying changes to production
