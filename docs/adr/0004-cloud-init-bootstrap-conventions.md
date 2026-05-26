# ADR-0004: Cloud-init bootstrap conventions

- **Status**: Accepted
- **Date**: 2026-05-24

## Context

The `libvirt-vm` module ships a `cloud_init.cfg` template that becomes
the NoCloud user-data for every VM. This is the module's only mechanism
for configuring a freshly-cloned base image — no Ansible, no Salt, no
post-provision step inside the module. Decisions made here ship to
every VM this module creates.

Security-relevant knobs for a server-class VM:

- Default user creation and password handling
- SSH server configuration (password vs key, root access)
- Package update / upgrade on first boot
- Optional packages and `runcmd` for first-boot configuration
- Meta-data fields (`instance-id`, `local-hostname`) consumed by the
  NoCloud datasource

The NoCloud datasource documentation requires `meta-data` to contain an
`instance-id`. The `dmacvicar/libvirt` provider does not auto-generate
one when `meta_data` is left unset on `libvirt_cloudinit_disk`; it
writes an empty file. Modern Ubuntu cloud images tolerate this via
first-boot heuristics, but the behaviour is implicit rather than
guaranteed.

## Decision

The shipped `cloud_init.cfg` enforces this baseline for every VM:

| Setting | Value | Rationale |
|---------|-------|-----------|
| `hostname` | injected from `vm_name` | Matches the libvirt domain name; one source of truth |
| `manage_etc_hosts: true` | enabled | Keeps `/etc/hosts` consistent with `hostname` across reboots |
| Default user | `ubuntu` | Matches the Ubuntu cloud image convention; no surprise rename |
| `lock_passwd: true` | enabled | No password ever set on the default account |
| `disable_root: true` | enabled | Root SSH refused at the cloud-init level |
| `ssh_pwauth: false` | enabled | sshd refuses password authentication |
| `ssh_authorized_keys` | from `var.ssh_public_key` | One key per VM, validated as an OpenSSH key in `variables.tf` |
| `package_update: true` | enabled | Refresh apt metadata on first boot |
| `package_upgrade: false` | disabled | Avoid surprise reboots and long first-boot times; upgrade is a deliberate operator action |
| `packages: [qemu-guest-agent]` | required | Pairs with `qemu_agent = true` on the domain so libvirt can introspect the guest |
| `runcmd: enable qemu-guest-agent` | required | Ensures the agent starts on first boot |

`var.ssh_public_key` is validated against a regex that accepts modern
OpenSSH key types (Ed25519, FIDO2-backed Ed25519, ECDSA P-256/384/521,
RSA). Empty or malformed keys fail at plan time, not apply time.

`meta_data` on `libvirt_cloudinit_disk` is currently **unset**. ADR-0006
records this as a known gap and recommends setting it explicitly to a
deterministic value derived from `vm_name`.

## Consequences

**Positive**

- Every VM provisioned by this module starts hardened: no passwords, no
  root SSH, no fallback access path.
- The bootstrap is debuggable in two files: `cloud_init.cfg` and the
  calling module block. No external configuration management is required
  to reach a reachable, locked-down VM.
- `qemu_agent = true` + `qemu-guest-agent` installed means
  `libvirt_domain.network_interface[*].addresses` is reliably populated,
  which makes the `ip_address` output useful in NAT setups.

**Negative**

- Operators have **no fallback access path**. Losing or mis-typing
  `ssh_public_key` at provision time means destroying and re-creating
  the VM; no console password, no rescue user.
- `package_upgrade: false` means freshly-provisioned VMs may carry known
  vulnerabilities until an operator runs `apt upgrade`. Deliberate
  trade-off — see Operator note.
- The default `ubuntu` user is well-known. We rely on key-only SSH and
  `lock_passwd` to make this a non-issue; threat models that require
  account-name obscurity will need to override the template.

## Operator note

Hardening on top of the baseline (`unattended-upgrades`, fail2ban,
audit logging, custom user names) belongs to the **configuration
management layer**, not this module. The module's job is to deliver a
reachable, authenticated VM; everything beyond that is downstream.

## References

- [cloud-init NoCloud datasource](https://docs.cloud-init.io/en/latest/reference/datasources/nocloud.html)
- [cloud-init modules reference](https://docs.cloud-init.io/en/latest/reference/modules.html)
- [`libvirt_cloudinit_disk` resource](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/cloudinit)
- `modules/libvirt-vm/cloud_init.cfg` — the shipped template
- ADR-0006 — recorded `meta_data` gap and remediation plan
