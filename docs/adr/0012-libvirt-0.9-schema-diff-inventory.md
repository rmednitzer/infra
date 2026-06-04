# ADR-0012: `dmacvicar/libvirt` 0.9.x schema-diff inventory

- **Status**: Superseded by [ADR-0016](0016-migrate-libvirt-provider-to-0.9.md) (inventory host-verified and absorbed)
- **Date**: 2026-05-30

> **Note (2026-06-04):** carried forward by
> [ADR-0016](0016-migrate-libvirt-provider-to-0.9.md), which host-doc-verifies
> the deltas below against the real v0.9.8 provider (re-shaping both modules,
> `tofu validate`/`tofu test` clean) and proposes the pin bump. The desk
> inventory here proved accurate against the released schema; ADR-0016 carries
> the remaining ADR-0009 host gates.

## Context

[ADR-0009](0009-begin-libvirt-0.9-migration-evaluation.md) opened a
structured evaluation of the `dmacvicar/libvirt` 0.8.x → 0.9.x
migration. Its evaluation step (1) is a **schema-diff inventory**: for
each resource we use (`libvirt_domain`, `libvirt_volume`,
`libvirt_cloudinit_disk`), document the attribute deltas between the
0.8.x line (Terraform SDK v2) and the 0.9.x line (a ground-up rewrite on
the Terraform Plugin Framework).

This ADR records that inventory as a **desk exercise** against the
provider's own documentation and design notes. It is a draft input for
the eventual migration ADR. It is explicitly **Proposed**, not Accepted:
it does **not** change the `~> 0.8.0` pin (ADR-0002), and it does not
itself complete the ADR-0009 evaluation — the lab apply-cycle test
(step 2), the state-migration walk-through (step 3), and the functional
smoke test (step 4) still require a real libvirtd host and have **not**
been run here. Those gates remain open.

The 0.9.x line could not be exercised in the authoring environment (no
libvirtd, no ability to install the 0.9.x provider against a live host).
The deltas below are sourced from the provider repository's
documentation, `README.md` migration notes, and `AGENTS.md` design
principles, cross-checked via DeepWiki on
`dmacvicar/terraform-provider-libvirt`. Treat them as **to be confirmed
on a real host** before any pin bump.

## Inventory

### Framework / structural change (applies to all resources)

| Aspect | 0.8.x | 0.9.x |
|--------|-------|-------|
| SDK | Terraform SDK v2 | Terraform Plugin Framework |
| Modelling | Provider abstractions over libvirt | "Close API modelling, no abstraction" — mirrors `libvirtxml` schemas directly |
| Block vs attribute | Most config as nested **blocks** (`disk {}`, `network_interface {}`) | Most config as nested **attributes**, mirroring the libvirt XML tree |
| State | SDK v2 state shape | Plugin-framework state shape — **state migration required** |

### `libvirt_volume`

| Concern | 0.8.x | 0.9.x | Migration note |
|---------|-------|-------|----------------|
| Image source URL/path | `source = "http://…"` / local path | `create.content.url = "http://…"` | Attribute move; rewrite the call site |
| `format` | Often auto-detected | **Required** when creating from a URL | Must set `format` explicitly |
| `capacity` / `size` | `size` in bytes | `capacity` (+ unit attrs); auto-computed from `Content-Length` / file size for URL/file sources | Size semantics + units change; verify byte math |
| Backing store | `base_volume_id` | `backing_store` nested attribute | Attribute rename/reshape |

### `libvirt_domain`

| Concern | 0.8.x | 0.9.x | Migration note |
|---------|-------|-------|----------------|
| IP address read | `libvirt_domain.x.network_interface[0].addresses[0]` | `data.libvirt_domain_interface_addresses` **or** `wait_for_ip` on the interface | Our `ip_address` output (and the Talos node-IP wiring) would change shape |
| NIC config | `network_interface {}` block | nested interface attributes; `wait_for_ip` replaces `wait_for_lease` semantics | Block → attribute; flag rename |
| Disk attach | `disk { volume_id = … }` block | `disk` with nested `source` / `target` attributes (+ `wwn`) | Block → attribute reshape |
| `console` / `graphics` | top-level blocks | nested attributes under the devices tree | Block → attribute reshape (affects ADR-0008 graphics knob + serial console) |
| Memory / CPU units | `memory` (MiB implied) | `memory` + explicit `memory_unit` / `current_memory_unit` | Unit attributes are new; verify defaults |
| Lifecycle | implicit | new `create` / `update` / `destroy` nested attributes (paused start, shutdown behaviour, timeouts) | New capability; opt-in, not required |
| `cloudinit` | `cloudinit = libvirt_cloudinit_disk.x.id` | depends-on relationship retained | See cloudinit row below |

### `libvirt_cloudinit_disk`

| Concern | 0.8.x | 0.9.x | Migration note |
|---------|-------|-------|----------------|
| Status | First-class provider resource (`user_data`, `meta_data`, `network_config`, `pool`) | Provider-specific **convenience**, explicitly **deprioritized** ("NOT Priority 1") in the 0.9.x rewrite | **Highest-risk item.** ADR-0004/0007 depend on `user_data` + `meta_data`. Must confirm 0.9.x parity (or a replacement path) on a real host before bumping |

## Impact on this repo

- **`modules/libvirt-vm`** uses `libvirt_volume.source`,
  `libvirt_volume.base_volume_id`, `libvirt_volume.size` (bytes),
  `libvirt_domain` `disk {}` / `network_interface {}` / `console {}` /
  `graphics {}` blocks, `wait_for_lease`, and `libvirt_cloudinit_disk`
  with `user_data` + `meta_data`. **Every one of these is touched** by
  the deltas above.
- **`modules/talos-cluster`** (ADR-0013) uses the same 0.8.x surface
  (`libvirt_volume.source`, `libvirt_domain` `disk`/`network_interface`
  blocks, static IPs via `libvirt_network` DHCP host reservations). A
  0.9.x bump would re-touch both modules; they must move together.
- The `ip_address` output and the Talos node-IP wiring would both need
  reworking around `data.libvirt_domain_interface_addresses` /
  `wait_for_ip`.

## Decision (proposed)

1. Record the inventory above as the ADR-0009 step (1) artifact.
2. **Do not** change the `~> 0.8.0` pin. ADR-0002 stands.
3. Gate the remaining ADR-0009 steps (lab apply-cycle, state-migration
   walk-through, functional smoke test, maintenance-horizon check) on a
   real libvirtd host. They are **not** satisfied by this desk exercise.
4. The successor migration ADR (the next free number when the
   evaluation closes positively) supersedes ADR-0002's migration plan,
   bumps the pin to `~> 0.9.0` in **both** `libvirt-vm` and
   `talos-cluster` modules and all environment roots in one change, and
   refreshes every `.terraform.lock.hcl`.

## Consequences

**Positive**

- ADR-0009 step (1) now has a concrete, reviewable artifact instead of
  "to be done."
- The `libvirt_cloudinit_disk` deprioritization is surfaced as the
  single highest-risk migration item ahead of any bump — it would block
  both modules if 0.9.x lacks parity.

**Negative**

- The inventory is documentation-sourced, not host-verified; the
  concrete attribute names and byte/unit semantics must be re-checked on
  a real 0.9.x install before they can be trusted for a state-migration
  recipe.
- Status stays **Proposed**: this is an input, not a closed decision.

## References

- [ADR-0002 — Pin `dmacvicar/libvirt` to `~> 0.8.0`](0002-pin-libvirt-provider-to-0.8.md)
- [ADR-0009 — Begin libvirt 0.9.x migration evaluation](0009-begin-libvirt-0.9-migration-evaluation.md)
- [ADR-0013 — Adopt Talos Linux for the Kubernetes layer](0013-adopt-talos-linux.md)
- [`dmacvicar/terraform-provider-libvirt` README / docs](https://github.com/dmacvicar/terraform-provider-libvirt)
- DeepWiki: `dmacvicar/terraform-provider-libvirt` (0.8.x vs 0.9.x schema diff, queried 2026-05-30)
