# ADR-0017: Adopt `siderolabs/talos` write-only secret arguments

- **Status**: Accepted
- **Date**: 2026-06-09

## Context

[ADR-0015](0015-talos-machineconfig-as-code-and-secrets.md) accepts that the
Talos cluster's secret material lives in OpenTofu state and constrains the
backend accordingly (encrypted remote backend for any non-lab Talos
environment). The 2026-05-31 audit added a defense-in-depth follow-up, tracked
as **BL-2** in [`BACKLOG.md`](../../BACKLOG.md): evaluate the
`siderolabs/talos` provider's **write-only** secret arguments
(`client_configuration_wo`, `machine_configuration_input_wo`) to keep the
*rendered* machine configuration out of state, and note the outcome in
[ADR-0014](0014-pin-siderolabs-talos-provider.md).

Write-only attributes are an OpenTofu **1.11+** language feature: an argument
that can be set in configuration but is never persisted — it is written to
plan and state as `null`, and it may reference regular or ephemeral values.
The pinned provider line (`~> 0.11.0`, ADR-0014) ships write-only variants on
two of the resources this repo uses:

| Resource | Write-only arguments (0.11.x) |
|----------|-------------------------------|
| `talos_machine_configuration_apply` | `client_configuration_wo`, `machine_configuration_input_wo` |
| `talos_machine_bootstrap` | `client_configuration_wo` |
| `talos_cluster_kubeconfig` | *(none — `client_configuration` is required and persisted)* |

The provider enforces **exactly one of** each persisted/`_wo` pair
(`ValidateConfig` on both resources). Because a write-only value is invisible
to state, the provider detects drift in the write-only machine-config input
through a persisted **`machine_configuration_hash`** — a SHA256 of the
rendered configuration, recomputed during plan — and, when the write-only path
is used, deliberately sets the computed (and otherwise state-persisted)
`machine_configuration` attribute to `null` so the rendered document never
lands in state. Both behaviours were verified by reading the provider source
at the `v0.11.0` tag (`pkg/talos/talos_machine_configuration_apply_resource.go`:
`ValidateConfig`, `setPlanMachineConfiguration`), which the provider's own
write-only acceptance tests cover.

**What sits in state without `_wo`** (a cluster of *N* nodes):

- the rendered machine configuration: once per machine-configuration data
  source (control-plane and worker), **plus 2×N copies** on the apply
  resources (`machine_configuration_input` and the computed
  `machine_configuration`, both per node);
- the Talos client TLS credentials (`client_configuration`: CA certificate,
  client certificate, client key): at their source
  (`talos_machine_secrets`), in `data.talos_client_configuration`, **plus
  N copies** on the apply resources, one on the bootstrap resource, and one
  on the kubeconfig resource.

## Decision

1. **Adopt the write-only arguments** in `modules/talos-cluster`:
   - `talos_machine_configuration_apply.node` passes
     `client_configuration_wo` and `machine_configuration_input_wo`
     (eliminating the 2×N rendered-config copies and N client-credential
     copies);
   - `talos_machine_bootstrap.this` passes `client_configuration_wo`
     (eliminating one more client-credential copy).
2. **Raise the OpenTofu floor to `>= 1.11`** in
   `modules/talos-cluster/versions.tf` and
   `environments/talos-lab/versions.tf` — write-only attributes are an
   OpenTofu 1.11 feature. The other roots (`lab` `>= 1.10`, `production`
   `>= 1.10.4`) are unaffected and keep their floors; `.opentofu-version`
   (1.12.1) already satisfies the new floor.
3. **`talos_cluster_kubeconfig` keeps the persisted `client_configuration`**:
   the 0.11.x provider offers no `_wo` variant there (the argument is
   required). This is the one remaining per-resource copy of the client
   credentials, on a resource whose entire purpose is to persist the
   (equally sensitive) kubeconfig.
4. **`on_destroy.reset = true` now requires reverting to the persisted
   credential.** Write-only values are not in state, so the provider cannot
   re-read the client credentials during destroy; its Delete handler errors
   if `reset = true` is set while `client_configuration_wo` is in use
   (provider source: "Users must use client_configuration (non-write-only)
   if they need on_destroy.reset"). The module ships `reset = false`
   (destroy is a provider no-op), so the default behaviour is unchanged —
   but enabling destroy-time resets is now a documented two-line change:
   flip `reset` **and** switch that resource back to the persisted
   `client_configuration`, re-accepting the per-node credential copy in
   state. The `main.tf` comment and module README carry the same warning.
5. **The provider pin is unchanged** (`~> 0.11.0`, ADR-0014). The change is
   config-shape only; the committed `.terraform.lock.hcl` files are untouched.
6. **ADR-0015 stands, unweakened.** The cluster trust root
   (`talos_machine_secrets`), the rendered machine configuration (in the two
   machine-configuration data sources), and the talosconfig
   (`data.talos_client_configuration`) **remain in state by design** — the
   write-only arguments remove *duplication*, not the source material. The
   encrypted-remote-backend constraint for non-lab Talos environments is
   unchanged, as is the lab posture (local, gitignored state).

### Evaluated and deferred: ephemeral resources

Provider 0.11.x also ships **ephemeral** resource variants
(`talos_cluster_kubeconfig`, `talos_client_configuration`,
`talos_cluster_health`). Ephemeral kubeconfig/talosconfig retrieval would keep
those documents out of state entirely — but an ephemeral value cannot feed the
module's persisted `kubeconfig`/`talosconfig` outputs, and the documented
operator workflow depends on them (`tofu output -raw kubeconfig > kubeconfig`,
see `environments/talos-lab/README.md` and the `runbooks` repo). Adopting them
means moving credential retrieval out of the module contract (e.g. to
`talosctl kubeconfig` against the cluster). That is a larger interface change
with its own trade-offs — **deferred** to the next provider-pin review
(ADR-0014's 0.12.x migration plan), not silently bundled here.

### Migration note (existing state)

Switching an existing deployment to the write-only arguments is an **in-place
update**, not a replace: the plan shows the persisted arguments and the
computed `machine_configuration` nulling out and `machine_configuration_hash`
being set; the node receives an idempotent re-apply of an identical rendered
config. Until that first apply lands, every plan repeats the same per-node
diff (the hash is computed at plan time but only persisted by an apply) — a
plan-only pipeline run against unmigrated state will keep showing it. Values already written by previous applies remain in state history
(and any state backups) until rotated or recycled — for `talos-lab` the
cluster is reproducible (destroy + re-apply), which also recycles the lab
secrets. Production defines no Talos resources, so nothing else migrates.

### Evidence (this change)

- `tofu validate` clean on `environments/{lab,talos-lab,production}` against
  the pinned providers (OpenTofu 1.12.1).
- `tofu test` green: `talos-cluster` **46/46** — including a new
  `secret_arguments_are_write_only` run pinning that the persisted twin
  arguments stay unset — and `libvirt-vm` 17/17. The mock-provider suites
  load the **real** v0.11.x provider schema, so the write-only attribute
  names and the exactly-one-of shape are validated mechanically.
- Provider-side semantics (hash-based drift detection, `machine_configuration`
  nulled in plan when `_wo` is used) verified in the provider source at
  `v0.11.0`, not on a live cluster in this session. As with ADR-0016,
  schema-correct is not host-correct: review the first real `tofu plan`
  against a live `talos-lab` as usual. The provider's write-only paths are
  exercised by its own acceptance tests.

## Consequences

**Positive**

- The rendered machine config and client credentials no longer fan out per
  node into state: state exposure no longer scales with cluster size, and
  state-file diffs/backups stop carrying 2×N copies of a document that embeds
  the cluster PKI.
- Drift detection is preserved (provider-persisted SHA256 of the rendered
  config) — a config change still produces a reviewable plan diff per node.
- The exactly-one-of provider validation plus the new test run keep a
  regression (someone reverting to the persisted arguments) visible.

**Negative**

- The state no longer contains the *applied* rendered config per node — an
  operator inspecting state (or tooling that greps `tofu state show` for
  `machine_configuration`) sees only its hash. The rendered input remains
  readable from the machine-configuration data sources in state, and
  `talosctl get machineconfig` reads the live document from the node.
- Destroy-time resets lose their one-line opt-in: `on_destroy.reset = true`
  is incompatible with `client_configuration_wo` (Decision 4), so enabling
  it means trading the per-node credential copy back into state.
- OpenTofu floor for the Talos module/environment rises to 1.11; operators on
  1.10 must upgrade (the repo's pinned toolchain is already 1.12.1).
- A mixed floor across roots (`>= 1.10` / `>= 1.10.4` / `>= 1.11`) is mildly
  more to read, but each root states its true minimum rather than inflating
  the repo-wide floor.

## References

- [ADR-0014 — Pin `siderolabs/talos` to `~> 0.11.0`](0014-pin-siderolabs-talos-provider.md)
- [ADR-0015 — Talos machine-config-as-code and secret handling](0015-talos-machineconfig-as-code-and-secrets.md)
- [`BACKLOG.md`](../../BACKLOG.md) — BL-2
- [OpenTofu — write-only attributes](https://opentofu.org/docs/v1.11/language/ephemerality/write-only-attributes/)
- [`siderolabs/terraform-provider-talos` v0.11.0 — `machine_configuration_apply`, `machine_bootstrap` docs and source](https://github.com/siderolabs/terraform-provider-talos/tree/v0.11.0)
