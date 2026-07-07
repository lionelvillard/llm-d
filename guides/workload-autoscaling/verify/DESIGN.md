# Local Autoscaling Guide Runner — Design

**Date:** 2026-07-07
**Status:** Approved (design), pending implementation plan

## Problem

The `guides/workload-autoscaling` guides (HPA + EPP metrics, HPA + WVA metrics,
replica rebalancing) can only be exercised on GPU clusters today. There is **no
harness that tests a guide as written**: CI uses separate, GPU-only
`nightly-deploy-*.sh` scripts that have already drifted from the README steps.
A contributor without GPUs cannot:

1. Run the autoscaling guides locally (e.g. a Kind cluster on a macOS ARM laptop).
2. Test a PR to these guides by "running" the changed steps and observing that
   the stack reconciles and a scale event actually happens.

## Goals

- Run the autoscaling guides with **no GPU**, on a laptop, and **also on real
  clusters** (an existing cluster, or OpenShift).
- Prove **both** that the guide's steps reconcile to Ready **and** that a real
  scale event occurs end-to-end (`wva_desired_replicas` / EPP metric moves →
  HPA replicas change).
- Provide a **generic, repeatable way to test PRs** to this guides repo,
  including structural changes such as the in-flight HPA→KEDA conversion PR.
- Keep the guide **copy-pasteable by a human reader** — the runner executes the
  guide's own commands, it does not replace them.
- Provide a **cheap, deterministic way to verify the guide and the runner's
  recipe are in sync**, gateable in CI without a cluster.

## Non-Goals

- Replacing the existing GPU CI / nightly e2e workflows.
- A full natural-language doc interpreter that infers steps from prose
  (that was "Approach B"; rejected as too brittle).
- A fully autonomous AI agent that freestyles the run (that was "Approach D";
  rejected — not gate-able, nondeterministic).
- Making the x86 CPU vLLM backend run on a laptop (needs 64 cores / 64 GB;
  out of scope — the simulator covers the no-GPU case).

## Key Findings That Shape the Design

- **The autoscaling chain is shared by all paths:** model server emits vLLM
  metrics → Prometheus scrapes (TLS) → adapter exposes them
  (Prometheus-adapter for the EPP path; WVA controller + KEDA for the WVA path)
  → HPA scales the Deployment.
- **`ghcr.io/llm-d/llm-d-inference-sim` is multi-arch (amd64 + arm64)** →
  runs natively on Apple Silicon, no emulation. Already validated on Kind by the
  replica-rebalancing guide.
- **The simulator emits exactly the metrics the guides consume**
  (`vllm:num_requests_waiting`, `vllm:num_requests_running`,
  `vllm:kv_cache_usage_perc`) and its `--fake-metrics` flag accepts **generator
  functions** (`oscillate:start:end:period`, `ramp`, `rampreset`, `squarewave`)
  plus **live updates via `POST /admin/config`**. This lets the runner drive a
  **deterministic scale-up/scale-down with no GPU and no load generator**.
- **CPU vLLM is a dead end on a laptop** (64 cores / 64 GB, x86 images).
- **No existing harness tests a guide as-written** — the drift between the
  READMEs and the `nightly-deploy-*.sh` scripts is exactly what a local runner
  should catch.

## Architecture — Two Orthogonal Axes

The runner decouples **where** you run from **what** emits metrics, so one recipe
runs unchanged across combinations. It always operates on the **active
`kubectl` context**.

| Axis | Options | Absorbs the differences in |
|---|---|---|
| **Environment** (where) | `kind` · `existing` · `ocp` | cluster provisioning, image loading, monitoring-stack install, prereq verification |
| **Modelserver** (what) | `sim` · `vllm` | the workload emitting vLLM metrics, and how a scale event is driven |

Supported combinations:

- **`kind` × `sim`** — portable, no-GPU, deterministic core. Runs on macOS ARM.
- **`existing` × `sim`** and **`ocp` × `sim`** — same determinism against a real
  cluster you are already pointed at.
- **`existing` × `vllm`** and **`ocp` × `vllm`** — real model server, real load,
  GPU cluster only.
- **`kind` × `vllm`** — **rejected up front** (no GPU on a laptop).

This maps onto conventions already in the repo: `wva-config/platform/{k8s,ocp}`
exists → add `kind`; `modelserver/{gpu,cpu}` overlays exist → add `sim`.

## Layout

```
guides/workload-autoscaling/
  verify/
    run.sh                       # runner: `lint` and `test` subcommands
    profiles/
      kind.sh                    # provision cluster + load sim image + install stack, then verify
      existing.sh                # verify prereqs only (never mutates the cluster)
      ocp.sh                     # verify prereqs (User Workload Monitoring / Thanos aware)
    recipes/
      hpa-epp.yaml               # first path (v1 scope)
      wva.yaml                   # follow-up
      replica-rebalancing.yaml   # follow-up
  modelserver/sim/               # simulator overlay (mirrors existing gpu/cpu overlays)
  wva-config/platform/kind/      # new platform overlay (mirrors platform/k8s and platform/ocp)
```

## Shared Foundation

The `kind` profile provisions a self-contained stack:

- `kind create cluster` (1 control-plane node, no GPU) using `profiles/kind-config.yaml`.
- `kind load docker-image` for the simulator (arm64-native).
- Lightweight `kube-prometheus-stack` with **TLS enabled** (WVA requires HTTPS to
  Prometheus), plus **KEDA** and/or the **Prometheus adapter**, at small replica
  counts with **no GPU resource requests**.

The `existing` and `ocp` profiles **only verify** prereqs (Prometheus reachable
over TLS, KEDA/adapter present) and **fail with an actionable message** if
something is missing. They never mutate a cluster the user did not ask to
provision. `ocp` additionally understands User Workload Monitoring / Thanos, to
match the guide's OpenShift path.

## Tagged Steps in the README

READMEs get HTML-comment tags. A tag binds a stable `id` to the fenced `bash`
block **immediately following** it. Untagged blocks are invisible to the runner.
A block can be explicitly marked as not-to-run so the sync check does not flag it:

```markdown
<!-- local:step id=create-tls-secret -->
​```bash
kubectl create secret generic prometheus-tls-cert ...
​```

<!-- local:step id=apply-hpa -->
​```bash
kubectl apply -k optimized-baseline-autoscaling/hpa -n ${NAMESPACE}
​```

<!-- local:step id=verify-metrics ignore="informational output, nothing to execute" -->
​```bash
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1"
​```
```

Tags coexist with the existing `llm-d-cicd:skip` markers; the runner honors both.

## Recipe Manifest

The recipe references step `id`s (not block indices), declares local
substitutions applied to every executed block, and declares a
**modelserver-keyed scale strategy**:

```yaml
readme: ../../README.hpa-epp.md
env:
  NAMESPACE: llm-d-optimized-baseline
substitutions:
  - match: 'thanos-querier.openshift-monitoring.*:9091'
    replace: 'prometheus-operated.llm-d-monitoring:9090'
steps:
  - id: create-tls-secret
  - id: apply-hpa
    assert: {kind: hpa, name: optimized-baseline-nvidia-gpu-vllm-decode, replicas: ">1", within: 180s}
drive_scale:
  sim:  { fake_metrics: '{"waiting-requests":"ramp:0:400:60s"}' }
  vllm: { load: {generator: inference-perf, rps: 20, duration: 120s} }
```

The recipe is the only artifact touched when a path's structure changes
(~15 lines per path).

## Sync Lint — `run.sh lint <recipe>`

A pure-text, **no-cluster**, ~1s, CI-gateable check. It computes:

- **A** = every `id` tagged in the README.
- **B** = every `id` the recipe references (as a `step` or a `drive_scale` anchor).

and fails on either mismatch:

- **broken reference** — recipe references an `id` the README no longer tags →
  recipe is stale.
- **untested step** — README tags a step the recipe neither runs nor marks
  `ignore` → coverage gap; forces a conscious "test it or mark `ignore`"
  decision (this is what catches a PR that *adds* a step, e.g. the KEDA
  ScaledObject block).

`run.sh test` runs `lint` first and **refuses to execute if out of sync**, so a
green run proves the guide and recipe describe the same steps.

**Optional, off by default:** per-block content hashes recorded in the recipe,
so the lint additionally flags when a step's *commands* changed even though its
`id` did not (semantic drift). More maintenance (hashes churn on edits); document
it as an escalation, do not enable by default.

## Execution Flow — `run.sh test --env <e> --modelserver <m> <recipe>`

1. `lint` the recipe; abort if out of sync.
2. Reject invalid combos (`kind × vllm`).
3. Profile step: `provision` (kind) or `verify_prereqs` (existing/ocp).
4. Apply the shared foundation + the `modelserver/<m>` overlay.
5. Execute the recipe's tagged steps **in order**, applying substitutions to each
   block verbatim (running the guide's own commands).
6. `drive_scale` per modelserver:
   - `sim` — force metrics via `--fake-metrics` generators; may `POST
     /admin/config` for live updates.
   - `vllm` — run a **pluggable** load generator. Default is self-contained (no
     dependency on the external reusable CI workflow, whose `inference-perf` /
     `guidellm` profiles live outside this repo); those remain optional.
7. **Assert resources Ready AND HPA replicas moved** — identical assertion on
   both modelservers.
8. Exit 0 on success. On failure, print the failing command + `kubectl
   describe` / events / pod logs.

## Where AI Is Used (Approach C — two narrow, off-critical-path spots)

1. **PR adaptation.** When a PR changes a tagged block, diff README ↔ recipe and
   **propose** the updated substitution (or flag it as needing a human) as a
   **reviewable diff**. Keeps the runner generic across PRs without a brittle
   full parser. The proposal is reviewed, never silently applied.
2. **Failure triage.** On a failed assertion, hand Claude the failing command +
   cluster state for a one-paragraph likely-cause / likely-fix summary. Pure
   convenience.

The **deterministic core** (steps 1–5, 7) is what gets gated and trusted. A bad
AI suggestion surfaces as a diff or a note — **never a silent pass**.

## PR Testing

**Working-tree based:** the user checks out the branch, then runs the recipe:

```bash
git checkout <pr-branch>
guides/workload-autoscaling/verify/run.sh test --env kind --modelserver sim \
  guides/workload-autoscaling/verify/recipes/hpa-epp.yaml
```

A `gh pr checkout <n>` convenience wrapper is noted but not core.

## Implementation Scope

**v1:**

- Shared Kind foundation + `wva-config/platform/kind/` overlay + `modelserver/sim/` overlay.
- `run.sh` with `lint` and `test`, the three environment profiles
  (`kind`, `existing`, `ocp`), both modelserver strategies (`sim` via
  `--fake-metrics`; `vllm` via a pluggable load generator), and the assertion.
- The **HPA + EPP** recipe and its README tags.
- HTML-comment step tags in `README.hpa-epp.md`.

**Follow-ups:**

- `wva.yaml` and `replica-rebalancing.yaml` recipes + their README tags.
- The two AI helpers (PR adaptation, failure triage).
- Optional per-block content hashing in the sync lint.

## Risks / Open Questions

- **Substitution maintenance.** The `substitutions` list must track real
  cluster-specific values (Prometheus URLs, names). The sync lint catches *id*
  drift but not substitution correctness; failure triage helps here.
- **TLS Prometheus on Kind.** The `kube-prometheus-stack` TLS setup must produce
  a CA cert usable by the guide's `prometheus-tls-cert` secret step; the kind
  profile owns wiring this.
- **`vllm` load generator default.** Must be self-contained to avoid depending on
  the external reusable CI workflow; exact default generator is an
  implementation detail for the plan.
