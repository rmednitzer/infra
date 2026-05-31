# Changelog

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Audit remediation (2026-05-31)

- **Kubelet `event-qps` corrected `"0"` → `"5"`** in
  `modules/talos-cluster/machineconfig/common.yaml.tftpl`. As the
  `eventRecordQPS` config field, `"0"` means *unlimited* (a kubelet-event DoS
  vector); CIS v1.24+ recommends ≥ 1 (kubelet default 5). Updated the
  CIS-Kubernetes mapping doc and added a `tofu test` assertion for the positive
  value.
- **Production OpenTofu floor `>= 1.10` → `>= 1.10.4`**
  (`environments/production/versions.tf`): 1.10.0–1.10.3 omit the
  server-side-encryption header on the S3 `.tflock` write (opentofu#2970), which
  fails `init` on the SSE-enforced bucket the production backend mandates.
- **OpenTofu pin `1.12.0` → `1.12.1`** (`.opentofu-version`); lab README floor
  `≥ 1.6` → `≥ 1.10` (matching `versions.tf`).
- **`gitleaks` added to pre-commit** (`v8.30.1`, matching the automation/runbooks
  repos) — closes infra having no secret-detection hook at all.
- **`BACKLOG.md` added** to track explicitly-deferred work (F12 branch-protection
  verification; the libvirt 0.9.x migration gates; the talos `_wo` secret-arg
  evaluation) — the 2026-05-27 engagement flagged the absence of such a tracker.
- **Annotated stale ADR forward-references** in ADR-0002 and ADR-0009 (they named
  successor numbers that other ADRs since took) per the immutable-ADR process.

### Talos Linux Kubernetes integration

- Add the **`talos-cluster`** module (`modules/talos-cluster/`):
  provisions a Talos Linux Kubernetes cluster on KVM/libvirt. It creates
  the VMs with `dmacvicar/libvirt` (a module-owned NAT network with
  static DHCP reservations, a shared Talos base image, per-node overlay
  volumes, and per-node domains that boot the Talos image directly —
  **no cloud-init**) and drives the cluster with the partner-verified
  `siderolabs/talos` provider: `talos_machine_secrets`,
  `data.talos_machine_configuration` (control-plane + worker),
  `talos_machine_configuration_apply`, `talos_machine_bootstrap`,
  `talos_cluster_kubeconfig` (the resource form — the same-named data
  source is deprecated in the provider), and
  `data.talos_client_configuration`. Parameterizes control-plane +
  worker counts (maps of node → IP/MAC/specs), cluster name, endpoint,
  Talos/Kubernetes versions, and network CIDR. Outputs `kubeconfig`
  (sensitive), `talosconfig` (sensitive), and node IPs. New
  **ADR-0013** (adopt Talos, coexists with libvirt/Ubuntu, intentionally
  NOT Ansible-managed).
- Ship a hardened, config-as-code machine-config baseline under
  `modules/talos-cluster/machineconfig/` (`common.yaml.tftpl`,
  `controlplane.yaml.tftpl`), threaded into the machine configuration
  via `config_patches`: Pod Security Admission (`enforce: restricted` —
  tighter than Talos's `baseline` default), Kubernetes API audit policy
  (`audit.k8s.io/v1`), API-server profiling/anonymous-auth off, KSPP
  `machine.sysctls`, kubelet hardening (anonymous-auth off, webhook
  authz, TLS 1.3, `podPidsLimit`), Talos `features` (rbac, KubePrism,
  host DNS), NTP, and optional registry mirrors. Validated against the
  Talos hardening guides and the CIS Kubernetes Benchmark. New
  **ADR-0015** (machine-config-as-code + secret handling).
- Pin `siderolabs/talos` to `~> 0.11.0` (patch-level, pre-1.0, per the
  ADR-0002 rule) in the module and the new environment; committed
  `.terraform.lock.hcl` records 0.11.0 with `h1` hashes for
  `linux_amd64`, `darwin_amd64`, `darwin_arm64`, `linux_arm64`. 0.11.0
  is the current stable release on the Terraform registry (0.12.0 is
  alpha). New **ADR-0014** (pin rationale + verified resource schema).
- Add the **`talos-lab`** environment (`environments/talos-lab/`): 1
  control-plane + 2 workers, local backend, sensitive
  kubeconfig/talosconfig outputs. Secrets kept out of git via a
  directory `.gitignore` (`kubeconfig`, `talosconfig`, …); the
  `talos_machine_secrets` in state are gitignored by the root
  `.gitignore`. A production Talos cluster must instead use the
  encrypted remote backend (ADR-0011/0015).
- Add `docs/talos-cis-kubernetes.md` mapping the Talos baseline to the
  CIS Kubernetes Benchmark v1.10 (control-plane, etcd, worker/kubelet,
  policies/RBAC/PSS — a different control set from the host-CIS
  benchmark), including the documented `kube-bench` architectural
  false-positive skip-lists.
- Add native OpenTofu tests for `modules/talos-cluster` mocking **both**
  the libvirt and talos providers (`mock_provider`), so they need no
  libvirtd, no talosctl, and no cluster: node-count → resource fan-out,
  bootstrap targeting, derived Kubernetes minor, static-IP wiring,
  config-patch ordering, and the PSA/audit/KSPP-sysctl/kubelet hardening
  invariants in the rendered patches (24 assertions). Wired into CI.

### Talos module review hardening (PR review, round 2)

- **Security/correctness — real static DHCP reservations** (`main.tf`,
  `network-dhcp-hosts.xslt.tftpl`): the network previously declared node
  IPs only as `dns` **A records**, not MAC→IP DHCP reservations, so dnsmasq
  was free to lease any address while `talos_machine_configuration_apply`
  targeted each node's declared IP — the first apply could hang or hit an
  address the VM never received. dmacvicar/libvirt 0.8.x exposes no native
  HCL block for DHCP host reservations (verified against the 0.8.3 provider
  schema: the `dhcp` block only carries `enabled`), so the module now
  injects libvirt-native `<dhcp><host mac= name= ip=/>` reservations via an
  XSLT transform on the network XML. The transform is unit-checked with
  `xsltproc` (reservations land inside `<dhcp>`; the auto `<range>` and the
  DNS records survive) and asserted in `tofu test`.
- **Optional node reset on scale-down** (`main.tf`): `talos_machine_configuration_apply`
  now sets an explicit `on_destroy { reset = false, graceful = true,
  reboot = false }`. Default **off** (a no-op) so `tofu destroy` never blocks
  on an unreachable node's etcd leave; flip `reset = true` for clean
  scale-down of a healthy cluster (documented, with the unreachable-node
  caveat). Kept a literal rather than a variable because the talos provider
  types `on_destroy.reset` as a bool that rejects unknown values and
  `tofu validate` evaluates variables as unknown — a `var` here fails
  validate.
- **Node-key RFC 1123 validation** (`variables.tf`): each
  `control_plane_nodes` / `worker_nodes` key becomes a libvirt
  domain/volume name (`<cluster_name>-<key>`) and the interface/DHCP
  hostname, so each is now validated as an RFC 1123 label (same rule as
  `cluster_name`) — a key like `cp_01` or `rack/01` now fails at plan
  instead of erroring in libvirt at apply. Negative tests for both maps.
- **Unique node MACs** (`main.tf`, `node_invariants` precondition):
  added a case-folded cross-map distinct-MAC invariant alongside the
  existing unique-IP / disjoint-name ones — duplicate NIC MACs collide on
  the MAC-keyed DHCP lease (one node steals the other's lease, hanging
  `wait_for_lease`) even when IPs are unique. Negative test added.
- **Reject network-reserved node IPs** (`main.tf`, `node_invariants`
  precondition): a node IP inside `network_cidr` could still be the
  network address (`cidrhost 0`), the libvirt/dnsmasq gateway (first host,
  `cidrhost 1`), or the broadcast (`cidrhost -1`) — none leaseable to a
  VM, so `wait_for_lease` hangs. Each node IP is canonicalised and checked
  against that reserved set. Negative test (node at the gateway) added.
  `tofu test`: 43 passed (+4).

### Talos module review hardening (PR review)

- **Security — audit-policy ordering** (`controlplane.yaml.tftpl`):
  Kubernetes audit rules are first-match-wins. The broad
  `level: None` `get/list/watch` rule preceded the `RequestResponse`
  rule for secrets/configmaps/RBAC, so **reads of those sensitive
  resources were matched by `None` first and never audited** — a real
  audit-coverage gap. Reordered so the sensitive-resource
  `RequestResponse` rule comes first; the broad `None` rule now only
  catches the remaining read noise. Updated
  `docs/talos-cis-kubernetes.md` (§3.2.1) and the module README, and
  added two `tofu test` assertions (the `RequestResponse` rule index is
  before the `None` rule index; the rule matching `secrets` is at
  `RequestResponse`, not `None`).
- **Plan-time guard for cross-variable node invariants**
  (`main.tf`, `terraform_data.node_invariants` preconditions): a single
  variable `validation` cannot reference another variable, so these run
  as resource preconditions that hard-fail the plan before any
  libvirt/talos resource is created. They reject (a) **overlapping
  control-plane/worker node names** — previously a same-named worker
  silently overrode a control-plane entry in `merge()` while
  `bootstrap_node_*` still pointed at the dropped node; (b) **duplicate
  node IPs** across both maps (duplicate static leases → `wait_for_lease`
  timeout); and (c) **node IPs outside `network_cidr`** (compared via
  each IP's host-network under the CIDR prefix vs the CIDR network
  address). Three negative `tofu test` runs cover them.
- **Real IPv4 validation** for the `control_plane_nodes` / `worker_nodes`
  `ip` fields (`variables.tf`): replaced the dotted-quad regex (which
  accepted out-of-range octets like `999.999.999.999`) with
  `can(cidrnetmask("${ip}/32"))`. Applied to both node maps; negative
  tests added.
- **Real IPv4 CIDR validation** for `network_cidr` (`variables.tf`):
  replaced the string-shape regex (which accepted `10.5.0.0/99` and
  `999.../24`) with `can(cidrhost(var.network_cidr, 0))`, rejecting both
  bad octets and out-of-range prefix lengths; negative tests added.
- **VM-sizing validations** for the per-node `vcpus` / `memory_mib` /
  `disk_gib` overrides on both node maps (`variables.tf`), mirroring
  `modules/libvirt-vm`: `vcpus >= 1` (integer), `memory_mib >= 512`
  (integer), `disk_gib >= 10` (integer — the Talos system-disk minimum).
  Previously zero/negative/fractional values passed straight to libvirt.
  Negative tests added.
- **Configurable base-image format**: added a `talos_image_format`
  variable (default `qcow2`, validated `qcow2`|`raw`) and used it for the
  `libvirt_volume.talos_base` `format` (was hardcoded `qcow2`), so a raw
  factory image is no longer misread by libvirt/qemu. The base-volume
  name extension follows the format. Threaded through the `talos-lab`
  environment (variable + module call + tfvars); README/tfvars/docs and a
  negative test updated.

### Ubuntu 26.04 dual-support

- Make the `base_image` variable descriptions version-neutral across
  Ubuntu 24.04 LTS (noble) **and** 26.04 LTS (resolute, kernel 7.0,
  `cloud-images.ubuntu.com/resolute/`) in
  `modules/libvirt-vm/variables.tf` and
  `environments/lab/variables.tf`. Added a commented 26.04 `base_image`
  example to `environments/lab/terraform.tfvars`. The shipped
  `cloud_init.cfg` is distro-neutral (netplan/cloud-init unchanged
  across the two LTS releases) — verified and noted in the module
  README; no change to the secure cloud-init defaults. Added a
  `tofu test` assertion that a 26.04-style (resolute) `base_image`
  threads into the base volume and the cloud-init security baseline
  still renders.

### Production remote state backend (ADR-0011)

- Replace the production placeholder `backend "local"` with the real
  `backend "s3"` in `environments/production/backend.tf`:
  `use_lockfile = true` (OpenTofu 1.10+ native locking, not
  `dynamodb_table`), `endpoints = { s3 = "…" }` (not the deprecated
  top-level `endpoint`), `encrypt = true`, `use_path_style = true`. All
  values are non-secret config; credentials are injected via `AWS_*`
  env in CI/prod. CI keeps using `-backend=false`, so
  `tofu validate -backend=false` still passes (verified: a real
  `tofu init` correctly attempts S3 and fails on missing credentials).
  `required_version` was already `>= 1.10` (verified, no bump needed).
  Updated `environments/production/README.md` and `scripts/init-backend.sh`
  (the placeholder warning becomes a regression guard; a new guard warns
  when the S3 backend is configured but no AWS credentials are present).
  New **ADR-0011** realizes the ADR-0003 production decision.

### libvirt 0.9.x evaluation (ADR-0012, Proposed)

- Add **ADR-0012** (`dmacvicar/libvirt` 0.9.x schema-diff inventory,
  **Proposed**): the ADR-0009 step-(1) desk exercise comparing the
  0.8.x (SDK v2) and 0.9.x (plugin-framework rewrite) schemas for
  `libvirt_domain`, `libvirt_volume`, `libvirt_cloudinit_disk`
  (source → `create.content.url`, IP read via
  `libvirt_domain_interface_addresses`/`wait_for_ip`, size `_unit`
  attributes, new lifecycle controls, the deprioritized
  `libvirt_cloudinit_disk`). **No pin change** — the pin stays
  `~> 0.8.0`; the remaining ADR-0009 gates need a real libvirtd host.

### Docs / CI

- CI: add `modules/talos-cluster` and `environments/talos-lab` to the
  `validate` matrix, and turn the `test` job into a matrix over
  `modules/libvirt-vm` + `modules/talos-cluster` (`tofu test`). Mirrors
  the existing SHA-pins, concurrency, and `timeout-minutes`.
- `.tflint.hcl`: note that no official TFLint ruleset exists for
  `siderolabs/talos` either (as with libvirt); the core terraform
  ruleset still lints both modules. `tflint --recursive` passes.
- Update `README.md` and `CLAUDE.md` to describe the Talos subsystem
  (and that it is intentionally NOT Ansible-managed), the realized
  production S3 backend, and Ubuntu 26.04 dual-support; refresh the ADR
  tables (0011–0015), repository structure, environments table, and the
  OpenTofu version prerequisite (≥ 1.10).

- Fix the documented pre-commit environment variable. `README.md`,
  `CONTRIBUTING.md`, and the comment in `.pre-commit-config.yaml` told
  contributors to `export TFTOOL=tofu`, but `antonbabenko/pre-commit-terraform`
  reads `PCT_TFPATH`. `TFTOOL` was a no-op, so on an OpenTofu-only machine
  the documented hooks silently did not run against `tofu`. All three
  occurrences now read `PCT_TFPATH=tofu`.
- Add a native OpenTofu test suite for the `libvirt-vm` module under
  `modules/libvirt-vm/tests/` (`validation.tftest.hcl`,
  `module.tftest.hcl`). The suite mocks the provider
  (`mock_provider "libvirt"`) so it needs no libvirtd. It covers the
  negative input validations (bad hostnames, malformed/empty
  `ssh_public_key`, sub-floor `memory_mib`, duplicate `additional_disks`
  names) and positive assertions: deterministic NoCloud meta-data
  (ADR-0007), GiB-to-byte disk math, one volume per additional disk, and
  the ADR-0004 cloud-init security invariants (`ssh_pwauth: false`,
  `disable_root: true`, `lock_passwd: true`) — closing the M4
  security-enforcement gap. A `test` job (`Module Tests`) runs
  `tofu test` in CI, SHA-pinned and bounded by `timeout-minutes`.
- Record `h1` hashes for `linux_amd64`, `darwin_amd64`, `darwin_arm64`,
  and `linux_arm64` in every `.terraform.lock.hcl`
  (`modules/libvirt-vm`, `environments/lab`, `environments/production`)
  via `tofu providers lock`, so contributors and CI runners on any of
  those platforms do not hit a missing-hash error. Documented the
  command in `CONTRIBUTING.md` ("Provider bumps").
- Raise `required_version` from `>= 1.6` to `>= 1.10` across the
  `libvirt-vm` module and **both environment roots** (`environments/lab`,
  `environments/production`) so the runnable root constraints match the
  module they instantiate — a root advertising `>= 1.6` while calling a
  `>= 1.10` module would fail child-module init on OpenTofu 1.6–1.9. The
  old floor was never exercised (CI runs 1.12) and `>= 1.10` aligns with
  the production `use_lockfile = true` target (ADR-0003). Noted in the
  module README Requirements.
- Expose two new outputs on the `libvirt-vm` module: `data_disk_ids`
  (map of `additional_disks` name to libvirt volume ID) and
  `cloudinit_disk_id`. Added a module-README note that partitioning,
  formatting, and mounting data disks is the configuration-management
  (Ansible) layer's job, consistent with ADR-0004; no `fs_setup` is
  injected into cloud-init.
- Add an optional `graphics` input to the `libvirt-vm` module, threaded
  into `libvirt_domain.vm` via a `dynamic "graphics"` block. Default is
  `null`, preserving the secure no-graphics default from ADR-0008; a
  caller can opt a specific VM into SPICE/VNC without forking the module.
  The additive override is recorded in new **ADR-0010**; ADR-0008 is left
  intact (its secure-by-default decision is unchanged) per the
  immutable-ADR process. Module README inputs table and console/graphics
  section updated; tests assert both null-default and override behaviour.
- Factor the GiB-to-bytes magic number `1073741824` into
  `locals { bytes_per_gib }` in `modules/libvirt-vm/main.tf` and use it
  for both the root-disk and additional-disk byte computations (was
  inlined twice).
- Soften the CLAUDE.md HCL rule from "no hardcoded values in resource
  blocks" to "no **environment-specific** hardcoded values", matching
  the ADR-0005 intent. Structural constants intrinsic to the module's
  contract (`format = "qcow2"`, `qemu_agent = true`, the serial-console
  literals) stay inline rather than being promoted to variables.
- Add **ADR-0010** (Permit module-local supporting files and ship the
  graphics override). It permits template files (`cloud_init.cfg`) and a
  `tests/` directory beyond the five core files — amending the "exactly
  five files" rule of ADR-0005, whose body is left intact with only its
  status annotated to point at ADR-0010 (immutable-ADR process). The old
  wording already conflicted with the shipped `cloud_init.cfg`. CLAUDE.md
  module-structure note clarified to match.
- Note in `environments/production/README.md` that `TF_VAR_libvirt_uri`
  is mandatory in production (no default, unlike lab's `qemu:///system`).
- Guard `scripts/init-backend.sh`: warn (not fail) when run for
  `production` while `environments/production/backend.tf` still declares
  the placeholder `backend "local"`, pointing at ADR-0003, to prevent
  silently initializing local state in production.
- Pin the TFLint `terraform` ruleset to `0.14.1` in `.tflint.hcl`
  (explicit `source` + `version` instead of the bundled preset) so lint
  results do not shift when the tflint binary is upgraded; `0.14.1`
  matches the version bundled with tflint 0.62.1. Added a comment noting
  there is no official libvirt TFLint ruleset, so provider-specific
  issues are lint-blind. The CI lint job's `tflint --init` now passes
  `GITHUB_TOKEN` so the ruleset download is not rate-limited.
- Add `timeout-minutes` to every job in `.github/workflows/ci.yml`
  (10 for format/validate/lint/pre-commit/test, 15 for the Trivy
  security scan) to bound hung runs, for parity with the companion
  repos.
- Add a repo-neutral `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1,
  maintainer-email reporting) synced from the `automation` repo, and a
  root-level `SECURITY.md` stub pointing at `.github/SECURITY.md` for
  root-scanning tooling (OpenSSF Scorecard). Both added to the README
  governance table.
- Add `audit/2026-05-27-engagement.md` -- senior-assurance-engineer
  pass over the repo, captured per the engagement contract's Phase 6
  format. Documents the 12-commit engagement (Tier 1 items #1, #2,
  #3, #4, #6, #9, #10, #11 plus deferred-then-authorised D1 / D5 /
  D3), the four audit findings that remain deferred (F12 branch
  protection, F13 production `required_version` bump, F14 production
  S3 backend wiring, F11 libvirt 0.9.x migration), and the
  cross-checked rationale for every change.
- Open the structured evaluation of the `dmacvicar/libvirt` 0.8.x to
  0.9.x migration as
  [ADR-0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md).
  No pin change. The ADR captures gating criteria (schema-diff
  inventory, lab apply-cycle test, state-migration walk-through,
  functional smoke test, maintenance-horizon check); the actual bump
  lands in ADR-0010 when those gates close.
- Remove the SPICE `graphics` block from `libvirt_domain.vm` in the
  `libvirt-vm` module. The default-shaped VM no longer creates a
  SPICE (or any) graphics listener. Serial console
  (`virsh console <vm>`) remains as the out-of-band recovery path.
  Rationale in new
  [ADR-0008](docs/adr/0008-omit-graphics-from-libvirt-domain-by-default.md).
  Operators on existing infra see an in-place domain update; the
  graphics element is removed from the XML on the next domain
  restart.
- Set `meta_data` on `libvirt_cloudinit_disk.init` to
  `instance-id: ${vm_name}\nlocal-hostname: ${vm_name}\n`. Honours
  the cloud-init NoCloud contract for `instance-id` explicitly rather
  than relying on the provider's empty-file fallback. Closes
  [ADR-0006 Finding 2](docs/adr/0006-code-audit-2026-05.md) (status
  was DEFERRED); rationale and operator migration note in new
  [ADR-0007](docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md).
  Operators with existing VMs see a one-time cloudinit-disk re-create
  + domain restart on the first apply after upgrading.
- SHA-pin every `uses:` in `.github/workflows/ci.yml`. Major-version
  refs (`@v6`, `@v3`, etc.) re-resolve on every run; SHA pins are
  immutable. Each line carries a `# vX.Y.Z` (or equivalent) trailing
  comment so reviewers can see what version the SHA represents,
  matching the format Dependabot expects when bumping. Affects
  `actions/checkout`, `opentofu/setup-opentofu`,
  `terraform-linters/setup-tflint`, `aquasecurity/trivy-action`,
  `github/codeql-action/upload-sarif`, `actions/setup-python`, and
  `pre-commit/action`. Dependabot's `github-actions` ecosystem
  continues to track each line weekly. Aligns with NIST SSDF
  SP 800-218 PW.4 and SLSA Source Track guidance on third-party
  dependency pinning.
- Track Python tooling via Dependabot. Add `requirements-dev.txt`
  pinning `pre-commit==4.6.0` -- the only direct Python dependency
  the repo cares about -- and extend `.github/dependabot.yml` with a
  `pip` ecosystem entry that watches it weekly (label: `python`).
  `README.md` and `CONTRIBUTING.md` switched from
  `pip install pre-commit` to `pip install -r requirements-dev.txt`.
  No CI change.
- Extend `.gitignore` secret coverage: add `*.crt`, `*.cer`, `*.p12`,
  `*.pfx`, `.env`, `.env.local`, `.envrc`, and `.envrc.*`. The repo
  currently has none of these files; the additions are defensive so
  operator-side direnv files, local env files, and certificate
  bundles cannot accidentally be staged.
- Align `.claude/settings.json` permission allowlist with the
  OpenTofu-only policy from CLAUDE.md and ADR-0001. Drop the eight
  `Bash(terraform …)` entries (the active-tool policy says never use
  the `terraform` binary). Add read-only `tofu state list`, `tofu
  state show`, `tofu version`, the safe `tofu init -backend=false`
  prefix (so CI-equivalent validation runs without a permission
  prompt), and `trivy config` (the security gate from CI). No new
  state-mutating commands granted.
- Validate `var.libvirt_uri` in `environments/production/variables.tf`
  against the libvirt QEMU URI grammar. Accepts `qemu:///system`,
  `qemu:///session`, and the remote transports
  (`qemu+ssh`, `qemu+tls`, `qemu+tcp`, `qemu+unix`, others). A
  malformed URI now fails at plan time with a clear error rather than
  surfacing as a provider connection error at apply.
- Emit Trivy results as SARIF and upload them to the GitHub Security
  tab. The `security` job in `.github/workflows/ci.yml` now writes
  `trivy.sarif` and a follow-up step calls
  `github/codeql-action/upload-sarif@v3` with `if: always()` so
  findings surface even when Trivy's `exit-code: "1"` blocks the job.
  Job-level `permissions: security-events: write` granted; the
  workflow-level `contents: read` stays in place. No change to which
  severities block CI (still HIGH and CRITICAL).
- Add workflow-level `concurrency:` block to `.github/workflows/ci.yml`.
  Concurrent runs for the same `github.ref` cancel any in-progress run,
  so rapid pushes to a PR branch no longer pile up runners. Pushes to
  `main` after merge are infrequent (branch is protected; merges happen
  one PR at a time) so the same policy is safe there.
- Pin CI's OpenTofu version via `tofu_version_file: .opentofu-version`
  on both `Setup OpenTofu` steps in `.github/workflows/ci.yml`. The
  `opentofu/setup-opentofu` action defaults to `latest` when no version
  input is supplied, so the `.opentofu-version` pin (`1.12.0`) was
  previously informational only. CI now installs the same version
  declared in the file. No behaviour change on this push; protects
  against silent drift on the next OpenTofu release.
- Optimise and rewrite every `.md` file end-to-end for tighter prose,
  consistent voice, and uniform structure across the three companion
  repos: `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `.github/SECURITY.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/copilot-instructions.md`, `docs/adr/README.md`, all six
  ADRs (`0001`–`0006`), `environments/lab/README.md`,
  `environments/production/README.md`, and
  `modules/libvirt-vm/README.md`. ADR Status / Date / Decisions /
  Consequences shape preserved per the Michael Nygard template;
  all factual content — decisions, dates, deprecations, version
  numbers, finding states (FIXED / DEFERRED / NO CHANGE / DOCUMENTED) —
  preserved verbatim. No module, environment, or CI behaviour change.
  `tofu fmt -check -recursive`, `tofu validate` per environment, and
  `tflint --recursive` all pass.
- Trim placeholder boilerplate in `environments/production/`: removed the
  example-module comment block in `main.tf`, the three commented-out
  variable stubs in `variables.tf`, the placeholder comment in
  `outputs.tf`, the commented-out tfvars examples, and the long inline
  S3-backend example in `backend.tf` (the backend example, native S3
  locking with `use_lockfile = true`, and the `endpoints = { s3 = "…" }`
  guidance live in ADR-0003 and the production env README — single source
  of truth). The working local placeholder backend stays in place so
  `tofu init -backend=false && tofu validate` still works in CI;
  `tofu fmt -check`, `tofu validate`, and `tflint --recursive` all pass.
- Sync governance docs (SECURITY policy shape, PR template structure,
  copilot instructions, README Governance table) with the companion
  `runbooks` and `automation` repos. No module, environment, or CI
  behavior change.

## [0.0.0]

### Scaffolding (PR #12)

- Governance: `NOTICE`, `CHANGELOG.md`, `CONTRIBUTING.md`,
  `.github/CODEOWNERS`, `.editorconfig`, `.opentofu-version` (`1.12.0`).
- Per-environment READMEs for `lab/` and `production/`.
- `.pre-commit-config.yaml` running `terraform_fmt`, `terraform_validate`,
  `terraform_tflint`, `terraform_trivy`, EditorConfig, hygiene.
- CI: Trivy IaC misconfiguration scan (fails on HIGH / CRITICAL) and
  pre-commit hygiene job.

### Initial OpenTofu structure

- `libvirt-vm` module with cloud-init, validated inputs, committed lock
  files.
- `lab/` and `production/` environments scaffolded (production: local
  placeholder backend, no resources yet).
- ADR-0001..0006 — OpenTofu choice, libvirt pin (`~> 0.8.0`), state
  backend strategy, cloud-init conventions, module / environment layout,
  2026-05 code-audit findings.
- CI: `tofu fmt`, `tofu validate`, `tflint`.
- `.github/SECURITY.md`, PR / issue templates, Dependabot.
