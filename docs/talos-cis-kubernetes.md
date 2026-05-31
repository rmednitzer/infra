# Talos hardening → CIS Kubernetes Benchmark mapping

How the `modules/talos-cluster` baseline maps to the **CIS Kubernetes
Benchmark** (v1.10, the current line as of 2026-05). This is a *different*
control set from the host-level CIS benchmark that `automation` (Ansible)
applies to Ubuntu hosts: it targets the Kubernetes control plane, etcd,
worker/kubelet, and Kubernetes policies — not the OS.

Talos Linux is hardened-by-design (no SSH/shell/PAM, immutable rootfs,
RBAC + audit + anonymous-auth-off + at-rest encryption + profiling-off by
default). Much of the benchmark is satisfied by the platform; this module
adds the operator-owned controls (Pod Security Admission, an explicit
audit policy, KSPP sysctls, kubelet hardening) as config-as-code and
asserts the platform defaults so they are visible and regression-gated.

**Sources:** [Talos default hardening & CIS compliance](https://docs.siderolabs.com/talos/v1.12/security/talos-default-hardening-and-cis-compliance),
[Talos Pod Security guide](https://docs.siderolabs.com/kubernetes-guides/security/pod-security),
[CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).
Section numbering follows CIS Kubernetes Benchmark v1.10.

## Benchmark sections

| § | Area |
|---|------|
| 1 | Control-plane components (API server, controller-manager, scheduler) |
| 2 | etcd |
| 3 | Control-plane configuration (auth, logging) |
| 4 | Worker nodes (kubelet, config files) |
| 5 | Policies (RBAC, service accounts, Pod Security, network) |

## Section 1 — Control-plane components

| Control (abbrev.) | How it is met | Source |
|---|---|---|
| 1.2.x API server `--anonymous-auth=false` | Talos default; module asserts `anonymous-auth: "false"` in `cluster.apiServer.extraArgs` | controlplane patch |
| 1.2.x `--authorization-mode` includes `Node,RBAC` | Talos default (Node + RBAC always on, cannot be removed) | Talos default |
| 1.2.x `--profiling=false` | module sets `profiling: "false"` in `extraArgs` | controlplane patch |
| 1.2.x audit log path / policy / retention | module sets `cluster.apiServer.auditPolicy` (audit.k8s.io/v1 Policy); Talos wires the apiserver audit flags | controlplane patch |
| 1.2.x `--service-account-key-file`, SA token signing | Talos default (machine secrets generate the SA keypair) | `talos_machine_secrets` |
| 1.2.x TLS cipher suites / TLS 1.3 | Talos default (TLS 1.3 ciphers from v1.12) | Talos default |
| 1.3.x controller-manager `--profiling=false`, bound SA tokens | Talos default | Talos default |
| 1.4.x scheduler `--profiling=false` | Talos default | Talos default |

## Section 2 — etcd

| Control | How it is met | Source |
|---|---|---|
| 2.x etcd client/peer mutual TLS, cert-based auth | Talos default (etcd PKI from machine secrets; mTLS enforced) | `talos_machine_secrets` / Talos default |
| 2.x etcd `--auto-tls=false`, `--peer-auto-tls=false` | Talos default | Talos default |
| Secrets encrypted at rest | Talos default (`secretboxEncryptionSecret`) | Talos default |

## Section 3 — Control-plane configuration

| Control | How it is met | Source |
|---|---|---|
| 3.1.x authn: do not use client-cert-only for users where avoidable | Talos uses its own PKI; cluster admin via talosconfig/kubeconfig issued from machine secrets | `talos_machine_secrets` |
| 3.2.1 a minimal audit policy is set | module sets an explicit `auditPolicy` (first-match-wins order): `RequestResponse` for secrets/RBAC/SA-tokens **first** so their reads are audited, then `None` for remaining read-only verbs, `Metadata` elsewhere | controlplane patch |
| 3.2.2 audit policy covers key security concerns | covered by the `RequestResponse` rule on secrets, configmaps, serviceaccounts/token, and all RBAC objects | controlplane patch |

## Section 4 — Worker nodes (kubelet)

| Control | How it is met | Source |
|---|---|---|
| 4.2.1 kubelet `--anonymous-auth=false` | module sets `anonymous-auth: "false"` in `machine.kubelet.extraArgs` | common patch |
| 4.2.x kubelet `--authorization-mode=Webhook` | module sets `authorization-mode: Webhook` | common patch |
| 4.2.x kubelet TLS / `tls-min-version` | module sets `tls-min-version: VersionTLS13` | common patch |
| 4.2.x kubelet event rate / `event-qps` | module sets `event-qps: "5"` (a positive QPS — `0` means *unlimited* as the `eventRecordQPS` config field; CIS v1.24+ recommends ≥ 1) | common patch |
| 4.2.x rotate kubelet certificates | Talos default (kubelet cert rotation on) | Talos default |
| 4.2.x `podPidsLimit` / process limits | module sets `podPidsLimit: 4096` in `kubelet.extraConfig` | common patch |
| 4.1.x kubelet config file ownership/permissions | **architectural N/A** on Talos (no on-disk kubelet config the operator manages; immutable, API-delivered) | see false positives |

## Section 5 — Policies

| Control | How it is met | Source |
|---|---|---|
| 5.1.x RBAC enabled; least privilege | Talos default (RBAC always on); module asserts Talos apid `rbac: true` | common patch / Talos default |
| 5.2.x Pod Security Standards enforced | module sets `cluster.apiServer.admissionControl` PodSecurity: `enforce: restricted` (Talos default is `baseline`), `audit`/`warn: restricted`, system-namespace exemptions | controlplane patch |
| 5.2.x minimize privileged / hostPath / hostNetwork pods | enforced by the `restricted` PSA profile cluster-wide (outside exempt namespaces) | controlplane patch |
| 5.3.x network policies / default deny | **operator responsibility downstream** — depends on the chosen CNI; not provisioned by this module | deferred |
| 5.7.x seccomp / default profiles | `restricted` PSA requires `RuntimeDefault` seccomp for workloads | controlplane patch (PSA) |

## Kernel hardening (KSPP) — host layer for the Kubernetes node

Not a numbered CIS-Kubernetes control, but part of the node hardening the
benchmark assumes. Talos applies a strong KSPP baseline; the module
asserts the security-relevant sysctls as config-as-code via
`machine.sysctls`:

- `kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`
- `kernel.unprivileged_bpf_disabled=1`, `net.core.bpf_jit_harden=2`
- reverse-path filtering (`rp_filter=1`), redirect + source-route
  hardening, martian logging
- boot/build-time KSPP (`slab_nomerge`, `pti=on`, `init_on_alloc=1`,
  module signature enforcement) are **Talos defaults**, not settable
  here.

## Known architectural false positives

Running `kube-bench` against Talos surfaces false positives because Talos
has no operator-managed on-disk config files and an immutable, API-driven
kubelet. Per the Talos CIS guide, skip:

- **Control plane:** `1.1.1–1.1.8`, `1.1.11–1.1.19`, `1.2.5–1.2.8`
  (config-file path/ownership checks).
- **Worker:** `4.1.1`, `4.1.5–4.1.6`, `4.1.9–4.1.10`, `4.2.1–4.2.3`
  (kubelet config-file location/ownership).

These are reporting artifacts of Talos's design, not gaps. Validate the
*effective* posture via the API (`talosctl`) and the rendered machine
config, not file-on-disk audits.

## What still needs a real cluster

This mapping is desk-derived from the Talos hardening docs + the module's
rendered patches (verified by the mock-provider tests). It has **not**
been confirmed against a running cluster. Before claiming compliance, run
`kube-bench` (or an equivalent CIS-Kubernetes scanner) on a real cluster
built from this module, apply the skip-lists above, and reconcile each
remaining finding. The CNI-dependent controls (§5.3 network policies) are
out of this module's scope and must be addressed by the chosen CNI.
