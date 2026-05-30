# ADR-0010: Permit module-local supporting files and ship the graphics override

- **Status**: Accepted
- **Date**: 2026-05-30

## Context

Two earlier decisions need refinement, and the ADR process
([`README.md`](README.md)) requires that refinements to accepted ADRs be
captured in a new ADR rather than edited in place:

1. [ADR-0005](0005-module-and-environment-layout.md) states a module
   **must** contain *exactly* five files (`main.tf`, `variables.tf`,
   `outputs.tf`, `versions.tf`, `README.md`). That rule was already
   inaccurate: `modules/libvirt-vm` ships `cloud_init.cfg`, a template
   referenced from `main.tf`. The audit also adds a native test suite
   (`tests/*.tftest.hcl`, mocking the libvirt provider) — the single
   largest maturity gap the module had — which needs a home inside the
   module directory.
2. [ADR-0008](0008-omit-graphics-from-libvirt-domain-by-default.md)
   omits the `graphics` device by default and explicitly names "expose a
   module input … so operators do not have to fork the module" as the
   *cleaner long-term path*, deliberately deferred. A caller now needs
   graphical console access for a specific VM, so that knob must ship.

## Decision

**1. A module may carry module-local supporting files beyond the five
core files.** Specifically:

- Template files referenced from within the module (e.g.
  `cloud_init.cfg`).
- A `tests/` directory of native OpenTofu tests (`*.tftest.hcl`),
  mocking providers so they run with no live backend.

The five core files remain **required**; this is not licence to split
them prematurely or to add unrelated artifacts. This amends — does not
revoke — the [ADR-0005](0005-module-and-environment-layout.md) module
layout rule; the environment-root layout in ADR-0005 is unchanged.

**2. Ship the optional `graphics` override on `libvirt-vm`.** The module
exposes `variable "graphics"` (an optional object, `default = null`)
threaded into `libvirt_domain.vm` through a `dynamic "graphics"` block
whose `for_each` is empty when the value is `null`. The
[ADR-0008](0008-omit-graphics-from-libvirt-domain-by-default.md) decision
is **unchanged**: the default remains *no graphics device* (the secure
default). The knob only lets a specific caller opt in — the exception
ADR-0008 always envisaged — without forking the module.

## Consequences

**Positive**

- The module's test suite has a sanctioned location, and CI can run
  `tofu test`. Validations, cloud-init templating, and the ADR-0004
  security invariants are now regression-gated.
- `cloud_init.cfg` is retroactively legitimate under the layout rule.
- Operators get graphical access via a typed, validated input instead of
  copying the module.

**Negative**

- "Exactly five files" was a pleasingly simple rule; "five core files
  plus bounded supporting files" is slightly looser and relies on
  reviewer judgement about what belongs.
- The `graphics` object widens the module's input surface; its
  `listen_type`/`type` are validated to a small allow-list to contain
  that.

## References

- [ADR-0005 — Module and environment layout](0005-module-and-environment-layout.md)
- [ADR-0008 — Omit `graphics` from `libvirt_domain` by default](0008-omit-graphics-from-libvirt-domain-by-default.md)
- [ADR-0004 — Cloud-init bootstrap conventions](0004-cloud-init-bootstrap-conventions.md)
- [OpenTofu tests](https://opentofu.org/docs/cli/commands/test/)
