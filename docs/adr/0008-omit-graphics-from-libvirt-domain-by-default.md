# ADR-0008: Omit `graphics` from `libvirt_domain` by default

- **Status**: Accepted
- **Date**: 2026-05-27

## Context

The `libvirt-vm` module's `libvirt_domain.vm` declared a graphics
device:

```hcl
graphics {
  type        = "spice"
  listen_type = "address"
  autoport    = true
}
```

With `listen_type = "address"` and no explicit `listen_addresses`,
the bind address falls through to libvirt's `spice_listen` setting in
`/etc/libvirt/qemu.conf`. The upstream default for that setting is
`127.0.0.1`, so on a standard host the SPICE listener is bound to
loopback and not reachable off-host. However, the per-VM listener is
still active, and any operator who has edited `qemu.conf` (or whose
distribution ships a non-default `spice_listen`) inherits whatever
bind they configured.

The VMs this module provisions are server-class workloads: hardened
cloud-init, key-only SSH, locked default user
([ADR-0004](0004-cloud-init-bootstrap-conventions.md)). Cloud-init
plus SSH is the operating path. The graphics device adds no value to
that path; it is unused attack surface.

A serial console is already configured on the domain:

```hcl
console {
  type        = "pty"
  target_type = "serial"
  target_port = "0"
}
```

so `virsh console <vm>` remains as the out-of-band recovery path if
SSH ever stops working.

## Decision

Remove the `graphics { … }` block from `libvirt_domain.vm` in
`modules/libvirt-vm/main.tf`. With the block omitted, the
`dmacvicar/libvirt` provider does not add a `<graphics>` element to
the domain XML and libvirt does not synthesise one.

VMs provisioned by this module have:

- **Primary access**: SSH on the cloud-init-injected key.
- **Recovery access**: serial console via `virsh console <vm>` (the
  domain's `console` block, unchanged).
- **No SPICE listener**, no VNC listener.

Operators who need graphical access for a specific VM can wrap the
module call and add their own `graphics` block, but that is the
exception, not the default.

## Consequences

**Positive**

- One fewer listener per VM. The SPICE attack surface (CVE-grade
  history in QEMU's SPICE server, in-guest privilege escalation
  research) is removed for the default-shaped VM.
- The domain definition no longer depends on host-side
  `spice_listen` configuration to be safe.
- VM XML is smaller; `tofu plan` diffs around graphics changes
  disappear.

**Negative**

- No GUI console. For workflows that expected `virt-manager` or
  `remote-viewer` access, the only option becomes serial console.
- Serial console is sufficient for boot diagnosis, login, and
  recovery, but operators accustomed to graphical SPICE will need to
  adjust.

## Operator note

For existing VMs after this change lands, `tofu plan` shows an
in-place update on the domain: the graphics element is removed from
the XML. The change takes effect on the next domain restart (libvirt
applies graphics-related XML changes at domain boot, not at
hot-update). No `libvirt_cloudinit_disk` re-create, no domain
re-create.

If an operator wants graphical access for a specific VM:

```hcl
# In the env root, wrap the module:
module "workstation" {
  source = "../../modules/libvirt-vm"
  # ... required inputs ...
}

# And add a separate libvirt_domain attribute via -- this is
# illustrative; the cleaner path is to add a module input that
# threads through to libvirt_domain.vm.graphics.
```

The cleaner long-term path is to expose a module input (for example
`graphics = optional(object({ ... }))`) so operators do not have to
fork the module. That is deliberately not included in this ADR --
ship the secure default first; add the override knob when an actual
caller needs it.

## References

- [`libvirt_domain.graphics` reference](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/domain#graphics)
- [libvirt `qemu.conf` documentation](https://libvirt.org/manpages/libvirtd.html)
- [ADR-0004 — Cloud-init bootstrap conventions](0004-cloud-init-bootstrap-conventions.md)
