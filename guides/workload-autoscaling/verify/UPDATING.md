# Keeping Guides and Recipes in Sync

This runbook covers the five cases that require updating a recipe when a guide
changes. Read `README.md` for usage and `DESIGN.md` for architecture rationale.

## How the Pieces Relate

Each `<!-- local:step id=<id> -->` comment in a guide README binds a stable id
to the fenced bash block immediately following it. The recipe (`recipes/*.yaml`)
lists those ids under `steps:` (with optional `assert:`) and declares
`substitutions:` to remap sample values to the local test environment. The sync
lint (`run.sh lint <recipe>`) cross-checks the two: every recipe step must have
a matching tag in the README, and every non-ignored tag must appear in the recipe.
A lint failure means the recipe and guide have drifted; fix it before merging.

## Case 1: You added a new bash step to a guide

The runner ignores untagged blocks. `run.sh lint` will not flag it — but the new
step is untested. Decide:

- **Run it:** add `<!-- local:step id=<id> -->` immediately before the fenced
  block, then add `- id: <id>` to the recipe's `steps:` (with an `assert:` if
  the step should reconcile something). Re-run `run.sh lint` to confirm.
- **Skip it:** add `<!-- local:step id=<id> ignore="<reason>" -->` instead (e.g.,
  for informational output blocks or YAML files the reader saves manually). The
  lint will accept the tag without requiring a matching recipe step.

## Case 2: You renamed or removed a tagged step

`run.sh lint` will fail with `broken reference` — the recipe references an id
that no longer exists in the README. Update the matching `- id:` entry in the
recipe (rename it to the new id or remove it if the step was deleted).

## Case 3: You changed the commands inside a tagged block (same id)

Lint stays green — it only checks ids, not content. Re-run the full test to
confirm the changed commands still reconcile:

```bash
bash guides/workload-autoscaling/verify/run.sh test \
  --env kind --modelserver sim <recipe>
```

If the commands now reference different local values (e.g., a new flag, a
different resource name), update `substitutions:` in the recipe accordingly.

## Case 4: You changed namespaces, resource names, or Prometheus URLs

The guide's literal commands will fail to resolve locally. Update `env:` and/or
`substitutions:` in the recipe so the commands resolve in the test environment.
Run `run.sh lint` (fast) to confirm ids still match, then the full test to
confirm execution succeeds.

## Case 5: Before opening a PR

Always run lint first — it is fast (~1 s, no cluster):

```bash
bash guides/workload-autoscaling/verify/run.sh lint <recipe>
```

If any guide steps or cluster values changed, also run the full test:

```bash
bash guides/workload-autoscaling/verify/run.sh test \
  --env kind --modelserver sim <recipe>
```

The same lint check runs in CI, so a local green lint means CI will pass.
