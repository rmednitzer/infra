# Engagement evidence pack — 2026-05-27

Senior assurance-engineer pass over `rmednitzer/infra`. Phases 0
through 5 executed in one session on branch
`claude/upbeat-gauss-YIhQE`; this document is the Phase 6 deliverable
per the engagement contract.

Evidence-tag convention used throughout:
`[V]` verified against an authoritative source or tool result this
session, `[I]` inferred from premises, `[S]` speculation, `[?]`
unknown.

## 1. Scope, dates, branches

| | |
|---|---|
| Engagement window | 2026-05-27 (single session) |
| Repository | `rmednitzer/infra` |
| Default branch | `main` (`protected: true`) |
| Engagement branch | `claude/upbeat-gauss-YIhQE` |
| Branch base | `main` HEAD = `7869e3b` "Rewrite all .md files..." (#16) |
| Commits added | 12 |
| Final HEAD on engagement branch | `113712f` "Open the libvirt 0.9.x migration evaluation as ADR-0009" |
| Diffstat | 17 files changed, 535 insertions, 36 deletions |
| PRs opened in this engagement | one (see git log) |
| Authorization shape used | "Full execution per Section 7.5" (user-confirmed at Phase 1 entry) |

## 2. Phase 0 inventory snapshot

Repo at engagement start (HEAD `7869e3b`):

- 50 tracked files; 640 KiB on disk; 14 `.tf` (339 lines), 17 `.md`
  (1491 lines), 5 `.yml`/`.yaml`, 3 `.hcl`, 1 `.sh`, 1 `.json`. [V]
- One workflow `.github/workflows/ci.yml` with five jobs (`format`,
  `validate` x3 matrix, `lint`, `security`, `pre-commit`). Two
  additional checks observed on PR #16 — `CodeQL` and
  `Analyze (actions)` — sourced from GitHub default code-scanning
  setup, not from any tracked workflow file (search_code in repo
  returned zero CodeQL references). [V]
- Six ADRs (0001-0006). Two open follow-ups from ADR-0006 (Finding 2
  meta_data, Finding 4 production `required_version`). [V]
- 0 open issues, 0 open PRs, 0 in-code TODO/FIXME markers, no
  `BACKLOG.md`. [V]
- All five CI gates passing on `main` HEAD. Baseline re-run locally:
  `tofu fmt -check -recursive` (0), `tofu validate` per env (0x3),
  `tflint --recursive` (0), `trivy config --severity HIGH,CRITICAL
  --skip-dirs '**/.terraform'` (0 findings), `gitleaks detect` (0
  findings, full working tree). [V]
- Container missing `tofu` and `trivy` initially; installed during
  Phase 5 with user authorization. `tofu` 1.12.0 and `trivy` 0.70.0
  installed to `/usr/local/bin/`. [V]
- All pinned upstream versions (GitHub Actions, pre-commit hooks) at
  upstream-latest as of 2026-05-27 — items #7 and #8 from the Phase 1
  plan turned out to be no-ops. [V]

## 3. Phase 1 backlog disposition

The plan numbered 12 Tier-1 items plus five Tier-0 deferred /
confirmation-needed items. Disposition:

| Id | Title | Plan disposition | Final state | Commit |
|----|-------|------------------|-------------|--------|
| #12 | Branch-protection inspection (read-only) | execute | partial: `protected: true` confirmed; specific rules not visible from the MCP surface in this session. Documented as Outstanding (sec 8). | n/a |
| #5 | CodeQL surface investigation | execute | done: confirmed default-setup; no mirror added. Recorded. | n/a |
| #1 | Pin `tofu_version_file` in CI | execute | done | `08e3c05` |
| #2 | Workflow-level `concurrency:` | execute | done | `d651c6e` |
| #3 | Trivy SARIF + upload-sarif | execute | done | `16901c6` |
| #11 | Validate prod `libvirt_uri` | execute | done | `90a3559` |
| #9 | `.claude/settings.json` alignment | execute | done | `fcc45ec` |
| #10 | `.gitignore` defensive additions | execute | done | `70c7149` |
| #7 | Pre-commit hook currency audit | execute | no-op: all pins at upstream-latest as of 2026-05-27. No commit. | n/a |
| #8 | Trivy/pre-commit action currency | execute | no-op: all pins at upstream-latest as of 2026-05-27. No commit. | n/a |
| #6 | Dependabot widen to `pip` | execute | done; added `requirements-dev.txt` pinning `pre-commit==4.6.0` and a `pip` ecosystem entry | `53f3f4c` |
| #4 | SHA-pin every action in ci.yml | execute | done | `e8ef44f` |
| D1 | ADR-0007 + `meta_data` on cloudinit disk | execute | done | `9cc10d7` + `41a6a49` (CLAUDE.md table catch-up) |
| D5 | ADR-0008 + remove `graphics` block | execute | done | `6924816` |
| D3 | ADR-0009 + 0.9.x migration scoping | execute | done | `113712f` |
| D2 | Bump prod `required_version` to `>= 1.10` | deferred | still deferred. Gated on D4 (no work to do until production has an S3 backend). |
| D4 | Production S3 backend wiring | deferred | still deferred. Needs operator-side bucket; secrets touch; will land in its own session when the backend is provisioned. |

Skipped per Phase 1:

| Id | Title | Reason |
|----|-------|--------|
| S1 | Lab var rename to `libvirt_vm_*` | The example in `.github/copilot-instructions.md` is aspirational; the code's flat naming is internally consistent. If anything is wrong it's the doc, not the code. |
| S2 | Lab `main.tf` to `for_each` | Pure refactor, no behavioural change, no acceptance criterion. CLAUDE.md explicitly warns against such refactors. |
| S3 | Add `CODE_OF_CONDUCT.md` | User preference; not requested. |
| S4 | Pre-commit auto-install bootstrap | `CONTRIBUTING.md` already documents the manual step; no demand. |

## 4. Phase 2 audit findings (with status)

Findings raised during Phase 0/1 and their post-engagement status:

| # | Finding | Severity | Status | Resolution |
|---|---------|----------|--------|------------|
| F1 | CI's `opentofu/setup-opentofu@v2` did not pin a tofu version; `.opentofu-version` was informational only | Medium | FIXED | `08e3c05` |
| F2 | No workflow-level concurrency control; rapid pushes pile up runners | Low | FIXED | `d651c6e` |
| F3 | Trivy IaC findings only visible in run logs, not in GitHub Security tab | Medium | FIXED | `16901c6` |
| F4 | Production `var.libvirt_uri` had no validation; typos surfaced as apply-time provider errors | Low | FIXED | `90a3559` |
| F5 | `.claude/settings.json` allowlist contradicted CLAUDE.md/ADR-0001 OpenTofu-only policy by permitting `Bash(terraform ...)` | Low | FIXED | `fcc45ec` |
| F6 | `.gitignore` missed common operator-side secret formats (`.envrc`, `*.crt`, `*.cer`, `*.p12`, `.env`) | Low | FIXED | `70c7149` |
| F7 | Pre-commit floated to whatever pip installed; no Dependabot visibility into Python deps | Low | FIXED | `53f3f4c` |
| F8 | GitHub Actions in `ci.yml` pinned at major-version refs, not SHA; SSDF SP 800-218 PW.4 says use immutable refs | Medium | FIXED | `e8ef44f` |
| F9 | `libvirt_cloudinit_disk.init` left `meta_data` unset; cloud-init NoCloud contract says `instance-id` must be present (ADR-0006 Finding 2) | Medium | FIXED via ADR-0007 | `9cc10d7` |
| F10 | `libvirt_domain.vm` graphics block created a SPICE listener on every server-class VM; unused attack surface | Low | FIXED via ADR-0008 | `6924816` |
| F11 | 0.8.x to 0.9.x migration plan in ADR-0002 was oral tradition; no gating criteria, no scheduled evaluation | Low | TRACKED via ADR-0009 | `113712f` |
| F12 | Branch-protection rules on `main` not inspectable from the MCP surface available in this session | Info | OUTSTANDING | needs admin API |
| F13 | Production `required_version` is `>= 1.6`; should bump to `>= 1.10` when S3 backend (ADR-0003) wires up `use_lockfile = true` | Low | DEFERRED (gated on D4) | none |
| F14 | Production `backend.tf` is a local placeholder; production cannot host real infra until replaced | Medium (only when production has resources to host) | DEFERRED | none; tracked in production env README |

No findings of CRITICAL severity; no security advisories or CVE
exposure observed in the dependency graph (libvirt provider 0.8.3 is
current within the pin range; no CISA KEV entries for the components
in scope).

## 5. Phase 3 cross-check map

Findings backed against authoritative sources opened this session
(`[V]`) or referenced from training (`[I]`):

| Finding | Source | Tag |
|---------|--------|-----|
| F1 (setup-opentofu defaults to `latest` when no input) | README of `opentofu/setup-opentofu` on github.com, fetched 2026-05-27 | [V] |
| F3 (Trivy supports SARIF output; codeql-action upload-sarif is the standard surface) | trivy-action and codeql-action README behaviour; CI patterns common across GitHub-hosted projects | [I] |
| F8 (SHA-pin actions; NIST SSDF SP 800-218 PW.4) | NIST SSDF SP 800-218, GitHub Actions hardening guidance, SLSA Source Track L2 | [I] |
| F9 (NoCloud `instance-id` requirement) | cloud-init NoCloud datasource documentation, cited in ADR-0006 and re-cited in ADR-0007 | [I] from training, cross-referenced ADR-0006 evidence |
| F10 (libvirt `spice_listen` defaults to `127.0.0.1`) | libvirt `qemu.conf` documentation, ADR-0008 references | [I] |
| F11 (0.8.x to 0.9.x is a breaking redesign) | `dmacvicar/libvirt` release notes for 0.9.0; ADR-0002 references; latest tag verified via webfetch | [V] |
| Upstream version baselines for all pinned hooks and actions | github.com release pages, fetched 2026-05-27 via WebFetch | [V] |

The few claims rated `[I]` (codeql-action behaviour, NIST SSDF
verbatim text, libvirt qemu.conf defaults) are conventional and
verifiable in their respective canonical sources; they are not
controversial within this engagement's scope.

## 6. Phase 4 validation suite changes

Pre-engagement gate surface (per `.github/workflows/ci.yml` at base):

- `format` job: `tofu fmt -check -recursive`
- `validate` matrix: `tofu init -backend=false` + `tofu validate` per env
- `lint`: `tflint --recursive`
- `security`: `aquasecurity/trivy-action@v0.36.0` config scan,
  HIGH/CRITICAL, exit 1 on findings
- `pre-commit` (hygiene): SKIP terraform_*

Post-engagement gate surface (cumulative effect of commits):

- `format` and `validate` jobs now pin OpenTofu via
  `tofu_version_file: .opentofu-version` (F1).
- Workflow-level `concurrency:` group + `cancel-in-progress: true`
  (F2).
- `security` job adds `permissions: security-events: write`, emits
  `trivy.sarif`, and uploads via
  `github/codeql-action/upload-sarif` with `if: always()` and
  `category: trivy-config` (F3). Severity gate unchanged (HIGH /
  CRITICAL still block).
- Every `uses:` is now SHA-pinned with a trailing version comment
  (F8). Dependabot's `github-actions` ecosystem keeps SHAs fresh
  weekly.
- New `pip` Dependabot ecosystem watches `requirements-dev.txt`
  (F7).

No CI job was removed. No required check was relaxed.

## 7. Phase 5 execution log

12 commits, in chronological order:

| Commit | Subject | Item(s) | Tier |
|--------|---------|---------|------|
| `08e3c05` | Pin OpenTofu version via tofu_version_file in CI | #1 / F1 | T1 |
| `d651c6e` | Add workflow-level concurrency to CI | #2 / F2 | T1 |
| `16901c6` | Surface Trivy findings in the GitHub Security tab | #3 / F3 | T1 |
| `90a3559` | Validate libvirt_uri shape in environments/production | #11 / F4 | T1 |
| `fcc45ec` | Align Claude permission allowlist with OpenTofu-only policy | #9 / F5 | T1 |
| `70c7149` | Broaden .gitignore secret patterns | #10 / F6 | T1 |
| `53f3f4c` | Track pre-commit via pip + Dependabot | #6 / F7 | T1 |
| `e8ef44f` | SHA-pin every GitHub Action in ci.yml | #4 / F8 | T1 |
| `9cc10d7` | Set meta_data on libvirt_cloudinit_disk per ADR-0007 | D1 / F9 | T0 (authorised) |
| `41a6a49` | Add ADR-0007 row to CLAUDE.md index | D1 catch-up | T0 |
| `6924816` | Omit graphics from libvirt_domain per ADR-0008 | D5 / F10 | T0 (authorised) |
| `113712f` | Open the libvirt 0.9.x migration evaluation as ADR-0009 | D3 / F11 | T0 (authorised) |

After every commit: full Section 6.1 gate run (tofu fmt, tofu
validate per env, tflint, trivy config, plus targeted YAML/JSON lints
for the files touched) reported exit 0. Final cumulative gate run at
`113712f`: same result, plus gitleaks (0 leaks), plus pre-commit
hygiene set (8/8 + editorconfig, terraform_* skipped because they
have dedicated CI jobs).

No Section 7.5 stop-gate was triggered: no CI-secret change, no
branch-protection edit, no CODEOWNERS change, no schema/data
migration, no major dep bump on a published library, no force push,
no history rewrite, no >500-line / >20-file commit, no new
state-mutating tool beyond the authorised `tofu` and `trivy`
installs.

## 8. Outstanding risks and recommended next steps

1. **F12 — Branch-protection rules on `main` are not inspectable**
   from this session. Recommend an out-of-band check that the `main`
   branch enforces: required CI checks (the five workflow jobs plus
   `CodeQL` plus `Analyze (actions)`), required PR review, signed
   commits if that is the intended posture, and "do not allow
   bypassing settings" for admins. Without that check, the PR from
   this engagement merges only if the rules permit.
2. **D4 — Production S3 backend wiring** remains deferred. The
   production environment cannot host real infrastructure until the
   placeholder backend is replaced (encrypted, versioned bucket;
   `use_lockfile = true`; OpenTofu `>= 1.10`). When the operator
   provisions the bucket, the change is a one-PR edit of
   `environments/production/backend.tf` and `versions.tf` (D2 lands
   in the same PR).
3. **D3 follow-through** — ADR-0009 opened the libvirt 0.9.x
   migration evaluation. The actual bump (ADR-0010) needs a dedicated
   session against a real lab libvirt host so the schema-diff and
   state-migration recipes can be captured from running infrastructure
   rather than from docs alone.
4. **CodeQL default-setup** — the gate is invisible to anyone reading
   only the repo. If consistency with "if it gates, it's in the repo"
   matters more than maintenance burden, a follow-up could mirror
   default-setup into `.github/workflows/codeql.yml`. Left as
   "leave default-setup in place" by deliberate decision in this
   engagement; revisit if the gate surface ever needs to evolve.
5. **`requirements-dev.txt` pin** — `pre-commit==4.6.0` is exact.
   Dependabot will propose patch and minor bumps weekly; merging them
   requires only a green CI run.
6. **Local pre-commit terraform hooks** — running `pre-commit run
   --all-files` locally with terraform_* enabled requires the
   `pre-commit-terraform` toolchain to find `tofu` on PATH. The
   `.pre-commit-config.yaml` docstring suggests `TFTOOL=tofu`; the
   current `pre-commit-terraform` documentation prefers `PCT_TFPATH=tofu`.
   The terraform_* hooks were SKIPPED in the local pre-commit run for
   this engagement; CI runs them as dedicated jobs anyway. A small
   future tightening would be to align the docstring with the
   current env var name (cosmetic).

## 9. Stop conditions encountered

None. No previously-green test went red, no secret material was
observed in repo or history, no dependency with an active CISA KEV
entry was found, no sign of prior unauthorised commit, no conflict
between audit findings and policy intent, no tooling unavailable that
would have lowered Phase 4 confidence below 70 after the authorised
installs, no instruction-bearing content in untrusted sources
attempted to reach a tainted sink.

## 10. Confidence summary

- Phase 0 coverage of repo at file level: 100% [V].
- Phase 1 backlog enumeration: complete given the four sources
  authorised (issues, PRs, in-code markers, ADR backlog) [V].
- Phase 4 gate parity local vs CI: all five gates run locally with
  the same arguments CI uses; matches CI behaviour as of HEAD [V].
- Outstanding items (F12, D2, D4, D3 follow-through) are tracked
  with explicit reasons; none of them is silently dropped [V].
- Confidence floor for any executed change: 80; no commit was made
  below the 70 floor.
