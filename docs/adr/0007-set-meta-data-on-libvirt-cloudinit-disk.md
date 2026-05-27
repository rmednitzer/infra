# ADR-0007: Set `meta_data` on `libvirt_cloudinit_disk`

- **Status**: Accepted
- **Date**: 2026-05-27

## Context

[ADR-0006 Finding 2](0006-code-audit-2026-05.md) recorded that the
`libvirt-vm` module passes `user_data` to `libvirt_cloudinit_disk` but
leaves `meta_data` unset. The cloud-init NoCloud datasource
specification requires `meta-data` to contain an `instance-id`; with
no meta-data, the `dmacvicar/libvirt` 0.8.x provider writes an empty
file. Modern Ubuntu cloud images tolerate this via first-boot
heuristics, but the contract is not guaranteed, and the implicit
`instance-id` is not deterministic across re-creates.

ADR-0006 deferred the fix because applying it forces re-creation of
the `libvirt_cloudinit_disk` resource and consequently a domain
restart for any operator with existing infrastructure.

## Decision

Set `meta_data` explicitly on `libvirt_cloudinit_disk.init` in
`modules/libvirt-vm/main.tf`:

```hcl
locals {
  cloud_init_meta_data = "instance-id: ${var.vm_name}\nlocal-hostname: ${var.vm_name}\n"
}

resource "libvirt_cloudinit_disk" "init" {
  name      = "${var.vm_name}-cloudinit.iso"
  pool      = var.storage_pool
  user_data = local.cloud_init_config
  meta_data = local.cloud_init_meta_data
}
```

`instance-id` is derived from `var.vm_name` so the mapping is
deterministic: the same VM name always produces the same NoCloud
identity. `local-hostname` pairs with the `hostname:` directive
already in `user_data`; the value is consistent at both NoCloud
datasource read and user-data execution.

## Consequences

**Positive**

- The NoCloud contract is honoured explicitly. No reliance on
  provider-side empty-file behaviour or Ubuntu cloud-init's first-boot
  heuristics.
- `instance-id` is deterministic. Re-applying with the same `vm_name`
  produces the same identity; cloud-init does not believe the instance
  has changed.
- [ADR-0006 Finding 2](0006-code-audit-2026-05.md) closes.

**Negative**

- On the first apply after this change, every existing VM sees a
  `libvirt_cloudinit_disk` re-create. The domain restarts because the
  domain's `cloudinit` attribute references the disk ID and the new
  disk has a new ID.
- Because the previous (empty) meta-data had no `instance-id`, the new
  explicit `instance-id` may register as a fresh instance to
  cloud-init's first-boot logic. `ssh_authorized_keys` may be written
  again, `runcmd` may re-run, `package_update` may re-execute.
  Operators with long-running production VMs should plan a maintenance
  window.

## Operator note

For operators who want to stage the disruption:

- Apply in `environments/lab` first; verify the VM survives the
  re-provision cycle and reaches its post-boot state.
- For `environments/production` (when it ships real resources), either
  roll forward and accept one restart per VM, or target individual
  VMs with `tofu taint module.<vm>.libvirt_cloudinit_disk.init` during
  a chosen maintenance window so the rollout is paced.

## Supersedes

This ADR closes the `DEFERRED` status of
[ADR-0006 Finding 2](0006-code-audit-2026-05.md). ADR-0006 itself
remains `Accepted`; it is an audit-record ADR and the historical state
of Finding 2 (deferred at the time, deliberately) is part of that
record.

## References

- [cloud-init NoCloud datasource](https://docs.cloud-init.io/en/latest/reference/datasources/nocloud.html)
- [`libvirt_cloudinit_disk` resource](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/cloudinit)
- [ADR-0004 — Cloud-init bootstrap conventions](0004-cloud-init-bootstrap-conventions.md)
- [ADR-0006 Finding 2](0006-code-audit-2026-05.md)
