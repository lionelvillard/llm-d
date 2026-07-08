# Workload Autoscaling Guide Runner

A local harness that executes the workload-autoscaling guides as written —
running the guide's own fenced bash blocks — and asserts that a real scale event
occurs. No GPU required for the `sim` modelserver.

## Prerequisites

- **bash 4+** — macOS ships bash 3.2 which is incompatible. Install and use bash
  from Homebrew: `brew install bash`. Then invoke the runner with the full path:
  `/usr/local/bin/bash guides/workload-autoscaling/verify/run.sh ...` or add
  `/usr/local/bin` (Intel) / `/opt/homebrew/bin` (Apple Silicon) before
  `/bin/bash` in your `PATH`.
- **docker** — required for `--env kind`. Used to provision the Kind cluster.
- **kind** — `brew install kind` or download from https://kind.sigs.k8s.io.
- **kubectl** — connected to the target cluster context for `existing` and `ocp`.
- **helm** — used by the kind profile to install monitoring and serving stacks.
- **yq** (v4) — used for recipe parsing. `brew install yq`.

No `gawk` required; all awk usage relies on stock BSD/POSIX awk.

## Subcommands

### `run.sh lint <recipe>`

Offline check (~1 s, no cluster needed). Verifies that every `<!-- local:step -->`
tag in the guide README has a corresponding entry in the recipe, and that every
recipe step references a tagged block. Fails with a clear message on either
mismatch. This is the check that CI runs.

```bash
bash guides/workload-autoscaling/verify/run.sh lint \
  guides/workload-autoscaling/verify/recipes/hpa-epp.yaml
```

Expected output: `✓ 2 steps, in sync`

### `run.sh test --env <env> --modelserver <modelserver> <recipe>`

Provisions or verifies the cluster (depending on `--env`), runs the recipe's tagged
steps in order (applying substitutions), drives a scale event, and asserts that
HPA replicas moved. Runs `lint` first and refuses to proceed if out of sync.

```bash
bash guides/workload-autoscaling/verify/run.sh test \
  --env kind --modelserver sim \
  guides/workload-autoscaling/verify/recipes/hpa-epp.yaml
```

## Environment x Modelserver Matrix

| `--env` | `--modelserver` | Supported | Notes |
|---------|----------------|-----------|-------|
| `kind` | `sim` | Yes | Portable, no GPU. Provisions a fresh Kind cluster. Recommended for local development and PRs. |
| `existing` | `sim` | Yes | Uses your current kubectl context. Only verifies prereqs; never provisions or mutates. |
| `existing` | `vllm` | Yes | Real GPU cluster. Uses your current kubectl context. |
| `ocp` | `sim` | Yes | OpenShift. Understands User Workload Monitoring / Thanos. |
| `ocp` | `vllm` | Yes | Real GPU cluster on OpenShift. |
| `kind` | `vllm` | **Rejected** | Kind has no GPU. Use `existing` or `ocp` with `vllm`. |

The `sim` modelserver uses `ghcr.io/llm-d/llm-d-inference-sim` (multi-arch,
amd64 + arm64) and responds instantly with no GPU. The `vllm` modelserver
requires a real GPU cluster.

## Testing a PR

Check out the branch and run the harness against it. The runner executes the
guide's own commands from the working tree, so any change to the guide's steps
is immediately tested.

```bash
git checkout <pr-branch>
bash guides/workload-autoscaling/verify/run.sh test \
  --env kind --modelserver sim \
  guides/workload-autoscaling/verify/recipes/hpa-epp.yaml
```

A green run confirms:
1. The recipe and guide tags are in sync (lint passes).
2. The guide's commands apply cleanly to a fresh cluster.
3. A real scale event is observed (HPA replicas > 1 within the assertion window).

## Recipes

| Recipe | Guide |
|--------|-------|
| `recipes/hpa-epp.yaml` | `README.hpa-epp.md` — HPA scaling via EPP flow-control metrics |

## Related Docs

- `DESIGN.md` — architecture rationale, two-axis model, sync lint design.
- `UPDATING.md` — runbook for keeping recipes in sync when guides change.
