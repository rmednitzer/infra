# Backlog — deferred and tracked work

Explicitly-deferred items that are not yet GitHub issues. Each was raised by an
audit or an ADR and intentionally postponed; this file keeps deferred work from
silently rotting (the 2026-05-27 engagement flagged that there was no such
tracker). Close an item by linking the PR/commit (or issue) that resolves it and
moving it to **Resolved**.

## Open

*(none)*

### F13 evidence (2026-08-13) — closed

`ai-stack` was the one fleet repository where a merge could land with no CI:
every PR-triggered workflow was `paths`-filtered, so no check was guaranteed to
report, and a check that never reports cannot be required. Combined with
repository-level `allow_auto_merge: true`, an ordinary pull request could be
auto-merged with nothing having run. Renovate was already covered by a
`platformAutomerge: false` override; the non-Renovate path was not.

Closed in two steps.

**1. The requireable check** (`ai-stack` PR #200). The path filter moved off the
`on:` trigger into a `changes` job, the nine chart-validation jobs are gated on
its output, and the workflow ends in an `if: always()` `ci-success` aggregate
that fails when any dependency is anything other than `success` or `skipped`.
This is the pattern `agents` and `aiops-mcp` already require under the same
name. Both paths are verified live:

| Pull request | `changes` | Validation jobs | `ci-success` |
|---|---|---|---|
| #200 (touches `lint.yaml`, in the filter list) | `chart=true` | all 9 ran, all green | success |
| #201 (touches only `renovate.json5` + `CHANGELOG.md`) | `chart=false` | all 9 skipped | success |

The second row is the one that matters for safety: it proves requiring the
context cannot wedge a change that touches no chart path.

Recorded because it is the obvious fix and it does **not** work: a trivial
always-green unconditional job would give native auto-merge something to wait
on while going green in seconds regardless of the diff, converting the gap into
the *appearance* of a gate. The aggregate's verdict is a function of the real
jobs' results, including the case where the `changes` job itself fails, in which
every gated job skips and `ci-success` still fails.

**2. The required context.** `ci-success` added to ruleset `15857143` as a
full-object read-modify-write, because the rulesets API replaces the whole
object and a partial `PUT` would have stripped the other rules. Verified
immediately after the write:

```
prepared: 4 existing rules preserved, +1 required_status_checks
VERIFY OK: rules=['deletion', 'non_fast_forward', 'pull_request',
                  'required_linear_history', 'required_status_checks']
           bypass=[] enforcement=active contexts=['ci-success']
```

The `platformAutomerge: false` override was then dropped (`ai-stack` PR #201),
so the repository uses the shared preset default like the rest of the fleet. The
ordering was load-bearing: dropping it before the context was required would
have handed merging to native auto-merge while there was still nothing required
to wait on, which is the exact failure the override existed to prevent.

**All eleven fleet repositories now have at least one required status check.**

### F12 evidence (2026-08-12)

Partially advanced. `GET /repos/{owner}/{repo}/branches` exposes a `protected`
boolean, which the 2026-05-27 engagement could not reach. Observed across the
eleven reachable fleet repositories:

| Protected | Repositories |
|---|---|
| yes | `infra`, `core-graph`, `agents`, `relay-shell`, `6dof-ascent-sim`, `aiops-mcp`, `ai-stack`, `automation`, `rmednitzer.github.io`, `runbooks`, `renovate-config` |
| no | none |

**Closed later the same day.** `renovate-config` was the one gap at first
observation: it publishes a Renovate preset that any repository may extend, so
an unreviewed push to its `main` propagated fleet-wide dependency policy.
Nothing automerges there (it has no dependencies of its own), so the exposure
was unreviewed change rather than unreviewed merge. The maintainer applied a
ruleset and `protected` was re-verified as true, so all eleven reachable
repositories now protect `main`.

The boolean is necessary but not sufficient. What remains unverified is the
required-checks list, and it matters more than "Info" implied when F12 was
raised. `renovate-preset.json` automerges
minor, patch, digest, pin and pinDigest updates with `platformAutomerge: true`,
and its own description states the property as "automerge low-risk updates once
required checks pass". That property is delegated, not self-enforced:

- Renovate's **branch** automerge waits for passing status checks it observes,
  independent of branch protection ("By default, Renovate will not automerge
  until it sees passing status checks / check runs for the branch",
  [Renovate automerge docs](https://docs.renovatebot.com/key-concepts/automerge/)).
- **`platformAutomerge: true` hands merging to GitHub's native auto-merge**,
  which waits for *required* reviews and status checks. If a protected branch
  declares no required checks, there is nothing for it to wait on.

So the required-checks list is a precondition of the preset's stated safety
property, not an independent hardening nicety. Confirming it is what closes F12.

The repositories where that actually bites are the ones Renovate automerges
into: `ai-stack`, `aiops-mcp`, `core-graph`, `agents`, `relay-shell`. A
protected branch there with no required checks would let an automerged update
land without CI having passed. `renovate-config` has no dependencies of its
own, so its own protection is about unreviewed change, not unreviewed merge.

Also unverified from here, and worth recording when an admin next has the UI
open: whether the ruleset bypass list is empty, and whether **Allow auto-merge**
is enabled per repository, since `platformAutomerge` is a no-op without it.

### F12 evidence (2026-08-13) — contents verified, F12 closed

Read with an authenticated `gh api` from the Vertex control plane, which is not
subject to the egress policy that blocked `api.github.com` from earlier
sessions. Two read-only operations, both recorded in the MCP broker log:
`op-9a17fbde789036a9d16f658b` (protection endpoint, rulesets index, repo flags)
and `op-cfb3cb50b92ecd2341d0fc31` (ruleset contents).

**Protection is implemented as rulesets, not legacy branch protection.** This is
the detail that made F12 hard to close and is the first thing to know when
re-verifying: `GET /repos/{owner}/{repo}/branches/main/protection` returns
**404 on all eleven repositories**. Read alone, that 404 reads as "`main` is
unprotected", which is the opposite of the truth. The protection lives at
`GET /repos/{owner}/{repo}/rulesets/{id}`.

#### The four questions F12 asked

| Question | Answer | Confidence |
|---|---|---|
| No admin bypass? | **Yes, verified.** `bypass_actors` is `[]` on all eleven rulesets. Nobody bypasses, including the owner | Direct read |
| Required review? | **Not required anywhere.** `required_approving_review_count: 0` and `require_code_owner_review: false` on all eleven. A pull request *is* required (direct push to `main` is blocked), but no approval is | Direct read |
| Required checks? | **Configured on ten of eleven.** `ai-stack` has no `required_status_checks` rule at all. Full list below | Direct read |
| Signed commits? | **Not required anywhere.** No `required_signatures` rule on any of the eleven | Direct read |

`CODEOWNERS` files exist fleet-wide but are advisory: with
`require_code_owner_review: false` they assign a reviewer and do not gate the
merge. That is a deliberate single-operator posture, not an oversight, but it
should be stated rather than assumed from the file's presence.

#### Per-repository

Every ruleset is `enforcement: active`, targets `branch`, and carries
`deletion` + `non_fast_forward` (so branch deletion and force-push to `main`
are blocked server-side) plus a `pull_request` rule. All except
`renovate-config` also carry `required_linear_history`.

| Repository | Ruleset | Required status checks | `allow_auto_merge` |
|---|---|---|---|
| `infra` | `main-protection` (15857150), strict | 16: `Format Check`, `Lint`, `Pre-commit (hygiene + EditorConfig)`, `Secret Scan (gitleaks)`, `Security Scan (Trivy)`, `Trivy`, `CodeQL`, `Analyze (actions)`, `Module Tests (modules/{libvirt-vm,talos-cluster})`, `Validate (environments/{lab,production,talos-lab})`, `Validate (modules/{libvirt-vm,talos-cluster})`, `Validate renovate preset` | true |
| `agents` | `main-protection` (17307994) | `lint`, `type-check`, `ci-success` | true |
| `relay-shell` | `main-protection` (17307996) | `check (py3.12)`, `check (py3.13)`, `check (py3.14)`, `gitleaks (secret scan)` | true |
| `runbooks` | `main-protection` (15857152) | `pre-commit (shellcheck + shfmt + hygiene)`, `bats (script behaviour tests)`, `secret scan (gitleaks)` | true |
| `automation` | `main-protection` (15857151) | `Lint`, `Syntax Check`, `Pre-commit (hygiene + EditorConfig)`, `Secret Scan (gitleaks)`, `Molecule (common)`, `Molecule (users)`, `Molecule (ssh_hardening)`, `Molecule (auditd)` | true |
| `ai-stack` | `main-protection` (15857143) | **none** | true |
| `6dof-ascent-sim` | `main-protection` (15857138) | `lint`, `typecheck`, `test (3.11)`, `test (3.12)`, `test (3.13)` | true |
| `rmednitzer.github.io` | `main-protection` (15857146) | `validate` | true |
| `core-graph` | `main-protection` (15857142) | `python-lint`, `typecheck`, `python-test`, `schema-and-rls-test`, `policy-test`, `secret-scan`, `lockfile-check`, `actionlint` | true |
| `aiops-mcp` | `main-protection` (17385194) | `ci-success` | true |
| `renovate-config` | `protect-default-branch` (20737544), strict | `Validate re-export` | **false** |

`infra` and `renovate-config` set
`strict_required_status_checks_policy: true` (branch must be current with
`main` before merge); the other nine set it false.

Two of `infra`'s sixteen contexts are not job names and are worth recording so
a future reader does not delete them as stale: `Trivy` is the code-scanning
check produced by the `upload-sarif` step in `ci.yml` (category
`trivy-config`), and `CodeQL` / `Analyze (actions)` come from CodeQL **default
setup**, which has no workflow file in the repository. All sixteen reported on
PR #62, which merged under the strict policy with an empty bypass list, so none
of them is a permanently-blocking phantom context.

**Matrix contexts are correctly expanded.** A required check named for an
unexpanded matrix expression (`Molecule (${{ matrix.role }})`) would never
match a reported check and would block merges forever. `automation`,
`relay-shell` and `6dof-ascent-sim` all name the expanded values. No action
needed; noted because the failure mode is silent and the fix is invisible once
correct.

#### The one gap: `ai-stack`

`ai-stack` is the single repository where the preset's "automerge low-risk
updates once required checks pass" property is **not** backed by a required
check, which is exactly the case the 2026-08-12 evidence above predicted would
matter. It is also the one repository where that is a deliberate design:

- Every PR-triggered workflow (`docs.yaml`, `lint.yaml`,
  `sync-image-artifacts.yml`) carries a `paths` filter, so no check is
  guaranteed to run and any required check would permanently block a PR that
  touches none of those paths.
- The live mitigation is in `ai-stack/renovate.json5`, which overrides
  `platformAutomerge: false` for minor, patch, digest, pin and pinDigest with a
  comment naming this exact hazard. Renovate therefore falls back to evaluating
  the checks that did report, rather than handing the merge to GitHub.

So the Renovate path is covered. **The residual is the non-Renovate path**: with
`allow_auto_merge: true` at the repository level and no required check, anyone
enabling GitHub auto-merge on an ordinary `ai-stack` PR lands it with no CI
gate at all, subject only to `required_review_thread_resolution`. That is
tracked as **F13** below rather than held inside F12.

One trap worth recording, because it is the obvious fix and it does not work:
adding a trivial unconditional job that always exits 0 and requiring it gives
native auto-merge something to wait on, but that check goes green in seconds
regardless of the diff, so auto-merge still lands the PR without any chart
validation having run. It converts the gap into the appearance of a gate. The
effective shape is an **aggregate** check that is itself conditional on the
real jobs, which is what `agents` and `aiops-mcp` already require as
`ci-success`, and it means restructuring `lint.yaml` rather than adding a
file beside it.

#### Other observations, recorded not actioned

- **Signed commits are not required on any repository.** F12 asked about this
  conditionally ("if intended"). Recorded as a decision, not a finding: adopting
  it fleet-wide is a separate change with key-management consequences.
- **`renovate-config` lacks `required_linear_history`** while the other ten
  carry it, and it is the only repository with `allow_auto_merge: false` and
  `delete_branch_on_merge: false`. The auto-merge setting is consistent with its
  deliberate no-automerge posture; the linear-history difference looks like
  drift from it having been created later (2026-08-12) than the others.
- **`allow_auto_merge: true` on ten repositories** confirms `platformAutomerge`
  is not a no-op there, which the 2026-08-12 evidence listed as unverified.

## Resolved

| Id | Item | Origin | Resolved by |
|----|------|--------|-------------|
| F13 | Give `ai-stack` a requireable aggregate status check, so the repository is not the one fleet member where a merge can land with no CI | F12 evidence 2026-08-13 (this file) | "F13 evidence (2026-08-13)" above. `ai-stack` PR #200 (the `changes` job + `ci-success` aggregate, both the run and skip paths verified) and PR #201 (dropping the now-unnecessary `platformAutomerge` override), plus `ci-success` added to ruleset 15857143 with all four pre-existing rules and the empty bypass list preserved |
| F12 | Verify the *contents* of `main` branch protection (which checks are required, required review, no admin bypass, signed commits if intended) | [audit/2026-05-27-engagement.md](audit/2026-05-27-engagement.md) §8.1 (F12) | "F12 evidence (2026-08-13)" above. All four questions answered by direct read of the eleven rulesets: bypass lists empty, no required approvals, required checks present on ten of eleven, signed commits not required. The `ai-stack` exception is carried forward as F13 |
| BL-1 | Execute the libvirt 0.9.x migration evaluation gates against a real lab host, then author the successor pin-bump ADR | [ADR-0009](docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md) gates 2–5; [ADR-0012](docs/adr/0012-libvirt-0.9-schema-diff-inventory.md) | [ADR-0016](docs/adr/0016-migrate-libvirt-provider-to-0.9.md) (PR #29, merged 2026-06-04): gates 2–5 host-verified by the maintainer, pin bumped to `~> 0.9.0`, ADR-0002/0009/0012 superseded |
| BL-2 | Evaluate `siderolabs/talos` write-only secret arguments (`client_configuration_wo`, `machine_configuration_input_wo`) to keep rendered machine config out of state | audit 2026-05-31 | [ADR-0017](docs/adr/0017-adopt-talos-write-only-secret-arguments.md) (PR #38, 2026-06-09): adopted on `talos_machine_configuration_apply` + `talos_machine_bootstrap`; outcome noted in [ADR-0014](docs/adr/0014-pin-siderolabs-talos-provider.md) |
