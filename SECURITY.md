# Security policy: infra

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/rmednitzer/infra/security/advisories/new).
Do not post exploit payloads, secrets, personal data or sensitive operational
details in public issues. If private reporting is unavailable, use an existing
maintainer security contact where published; otherwise request a private channel
with a minimal, non-sensitive issue. Do not assume an invented email address works.

Include the affected revision/version and paths, prerequisites and trust boundary,
expected versus actual behavior, a minimal sanitized reproduction, impact and any
workaround. Use synthetic data. A dependency issue affecting this project is in
scope: coordinate upstream as appropriate without delaying notification here.
This policy does not authorize testing third-party or live deployments, service
disruption, credential use, persistence or access to other people's data.

Existing response targets are retained below as maintainer goals, not guaranteed
service levels. Coordinate disclosure and advisory timing with the maintainer;
urgent active exploitation or credential exposure should be identified immediately.

## Contributor security requirements

Follow [AGENTS.md](AGENTS.md) for secure coding, dependency/CI integrity, verification,
STPA and threat-analysis requirements. Preserve deployment trust boundaries and
document exceptions, residual risk and recovery. Never suppress a security finding
merely to pass CI. For fixes, capture a reproducer, add a meaningful regression,
check adjacent paths, assess affected versions and coordinate remediation/advisories.
Code review and CI do not prove deployed configuration or legal compliance.

## Support and response targets

Only main receives security fixes. Existing targets: acknowledgement within
5 business days and a remediation timeline within 14 days.

## Scope and state safety

Report credential/state/plan exposure, provider/bootstrap injection, unsafe
network or privilege defaults, broken isolation and missing backend safeguards.
Sensitive variable/output flags redact display; they do not encrypt persisted
state or saved plans. Protect backend access, encryption, locking, backups and
plan artifacts; use short-lived scoped credentials and supported secret-safe
provider arguments. Lab local state is an explicit single-operator exception.

Preserve TLS/SSH identity checks, cloud-init hardening, module/environment
separation, provider provenance and dependency locks. Review replacements/deletes
and recovery before applying an authorized plan. Formatting, validation, mock
tests and a successful plan are not proof of runtime hardening.
See docs/adr/ for state, bootstrap and Talos decisions; a platform baseline mapping
does not establish conformance for another product release.
