# ADR-0015: Talos machine-config-as-code and secret handling

- **Status**: Accepted
- **Date**: 2026-05-30

## Context

[ADR-0013](0013-adopt-talos-linux.md) adopts Talos Linux, whose entire
configuration is a single declarative *machine configuration* applied
over the Talos API. Two questions follow that the adoption ADR defers
here:

1. **Where does the hardening live, and how is it expressed?** Talos is
   hardened by default, but several security-relevant controls are left
   to the operator (Pod Security Admission profile, the API audit
   policy, KSPP sysctl assertions, kubelet hardening, NTP, registries).
2. **How are the cluster secrets handled?** The `siderolabs/talos`
   provider's `talos_machine_secrets` resource generates the cluster CA,
   the etcd/k8s PKI, and the bootstrap token. These are **stored in
   OpenTofu state**, and the cluster's `kubeconfig`/`talosconfig` are
   provider outputs.

## Decision

### Machine config as code

The `modules/talos-cluster` module ships its hardening baseline as
**version-controlled patch templates** under
`modules/talos-cluster/machineconfig/`, rendered with `templatefile` and
threaded into `data.talos_machine_configuration` via `config_patches`:

- `common.yaml.tftpl` — applied to **every** node: `machine.install.disk`,
  `machine.time` (NTP), `machine.features` (Talos `rbac`, KubePrism,
  host DNS), KSPP `machine.sysctls` (kptr/dmesg restrict, unprivileged
  BPF off, BPF JIT hardening, reverse-path filtering, redirect/source-
  route hardening, martian logging), `machine.kubelet` hardening
  (anonymous-auth off, webhook authz, TLS 1.3, `event-qps=0`,
  `podPidsLimit`), and optional `machine.registries.mirrors`.
- `controlplane.yaml.tftpl` — **control-plane only**:
  `cluster.apiServer.admissionControl` Pod Security Admission with
  `enforce` defaulting to **`restricted`** (Talos's own default is the
  looser `baseline`), `audit`/`warn` at `restricted`, and system-
  namespace exemptions; `cluster.apiServer.extraArgs` (`profiling=false`,
  `anonymous-auth=false`); and an explicit `cluster.apiServer.auditPolicy`
  (`audit.k8s.io/v1`: `None` for read-only verbs, `RequestResponse` for
  secrets/configmaps/SA-tokens/RBAC, `Metadata` elsewhere).

Rationale and validation: the baseline is mapped to the CIS Kubernetes
Benchmark in [`docs/talos-cis-kubernetes.md`](../talos-cis-kubernetes.md)
and validated against the Talos hardening guides. Where the module
*asserts* a Talos default (e.g. `rbac: true`, `anonymous-auth=false`),
that is deliberate: it makes the posture visible as code and survives a
Talos default change.

Caller patches (`extra_control_plane_config_patches`,
`extra_worker_config_patches`) are appended **after** the module's
patches so a specific cluster can extend or override the baseline; Talos
applies patches in order. The module's mock-provider tests assert the
PSA/audit/sysctl/kubelet invariants are present in the rendered patches,
so the hardening is **regression-gated in CI without a live cluster**.

### Secret handling

- **`talos_machine_secrets` lives in state.** Therefore **any non-lab
  Talos environment must use the encrypted, locked, remote backend**
  ([ADR-0011](0011-realize-production-s3-backend.md) realizes the
  production S3 backend per [ADR-0003](0003-state-backend-strategy.md)).
  A production Talos cluster on a local backend is **prohibited** — it
  would write the cluster CA and bootstrap token to an unencrypted local
  file.
- **`environments/talos-lab` uses a local backend** (single-operator
  lab, reproducible from config, ADR-0003). Its state still contains the
  secrets; the state file is gitignored by the root `.gitignore`.
- **`kubeconfig` and `talosconfig` outputs are `sensitive = true`** on
  both the module and the environment. Files written from them
  (`tofu output -raw kubeconfig > kubeconfig`) are gitignored by
  `environments/talos-lab/.gitignore` (`kubeconfig`, `talosconfig`,
  `*.kubeconfig`, `*.talosconfig`, …).
- **No secrets in `terraform.tfvars`.** The machine secrets are
  *generated* by the provider, not supplied; `terraform.tfvars` carries
  only non-secret topology (IPs, MACs, image path, versions), consistent
  with the repo's secrets policy.
- `machine_secrets_id` is exported as a **non-sensitive** handle (the
  computed cluster-secrets ID) for reference; the secret material itself
  is never output.

## Consequences

**Positive**

- The cluster's security posture is config-as-code: reviewable,
  diffable, and regression-gated by tests — not click-ops or tribal
  knowledge.
- The `restricted`-by-default PSA tightens Talos's baseline default to
  the hardened target the CIS mapping calls for, while staying
  overridable per cluster.
- Secret handling is explicit and tied to the backend decision: lab is
  local-but-gitignored; production is forced onto the encrypted remote
  backend.

**Negative**

- `restricted` PSA cluster-wide can break a CNI/CSI that needs
  privileged pods; mitigated by `pod_security_exempt_namespaces`
  (default `kube-system`) and the caller-extra patches, but it is an
  operator responsibility to validate against the chosen CNI on a real
  cluster.
- Keeping `talos_machine_secrets` in state is the provider's model; it
  concentrates the cluster's trust root in the state file, which is why
  the backend constraint above is non-negotiable for production.
- The audit policy and sysctl set are a fixed baseline; clusters with
  stricter needs must extend via the caller patches.

## References

- [ADR-0003 — State backend strategy](0003-state-backend-strategy.md)
- [ADR-0011 — Realize the production S3 remote state backend](0011-realize-production-s3-backend.md)
- [ADR-0013 — Adopt Talos Linux](0013-adopt-talos-linux.md)
- [ADR-0014 — Pin `siderolabs/talos` provider](0014-pin-siderolabs-talos-provider.md)
- [`docs/talos-cis-kubernetes.md`](../talos-cis-kubernetes.md)
- [Talos default hardening & CIS compliance](https://docs.siderolabs.com/talos/v1.12/security/talos-default-hardening-and-cis-compliance)
- `modules/talos-cluster/machineconfig/`, `environments/talos-lab/.gitignore`
