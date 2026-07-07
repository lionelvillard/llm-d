# Local Autoscaling Guide Runner (HPA + EPP, v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runner that executes the workload-autoscaling HPA+EPP guide as-written on a Kind cluster (no GPU) or a real cluster, proves the steps reconcile and a scale event happens, and verifies the guide and the runner's recipe stay in sync.

**Architecture:** A deterministic bash runner (`run.sh`) drives two orthogonal axes — environment (`kind`/`existing`/`ocp`) and modelserver (`sim`/`vllm`). It extracts HTML-comment-tagged `bash` blocks from a README, applies recipe-declared substitutions, runs them against the active `kubectl` context, drives a scale event via light traffic through the EPP, and asserts HPA replicas moved. A pure-text `lint` subcommand checks that README tags and recipe step-ids match. A `sim` kustomize overlay (arm64-native `llm-d-inference-sim`) plugs into the existing optimized-baseline modelserver structure.

**Tech Stack:** bash, kustomize, kind, kubectl, helm, yq, jq, `ghcr.io/llm-d/llm-d-inference-sim` (multi-arch), kube-prometheus-stack, Prometheus adapter. Tests are a dependency-free bash assertion harness (bats is not installed).

## Global Constraints

- All new artifacts live under `guides/workload-autoscaling/` (verify tooling under `guides/workload-autoscaling/verify/`, sim overlay under `guides/workload-autoscaling/modelserver/sim/`). Do not create files under `docs/`.
- v1 scope is the **HPA + EPP path only** (`README.hpa-epp.md`). WVA / replica-rebalancing recipes are follow-ups — do not build them here.
- No GPU resource requests anywhere in v1 manifests.
- Simulator image: `ghcr.io/llm-d/llm-d-inference-sim` (multi-arch amd64+arm64). Pin the tag to `v0.9.0` via a single variable in the sim overlay's image component so it is trivially bumpable.
- The simulator serves `/health/ready` (not `/health`) and `/v1/models`, listens on port `8000` by default, and takes `--model <id>` (required) + `--served-model-name <id>`.
- Runner operates on the **active kubectl context**; `existing`/`ocp` profiles must never mutate cluster infra they did not provision — verify and fail with an actionable message.
- Reject `--env kind --modelserver vllm` up front (no GPU on a laptop).
- The `test` subcommand runs `lint` first and aborts if out of sync.
- Follow existing repo kustomize conventions: overlays layer on `guides/recipes/modelserver/base/single-host/default` + an image `Component` under `guides/recipes/modelserver/components/images/`, with a `namePrefix` and `labels` block (mirror `guides/optimized-baseline/modelserver/cpu/vllm/kustomization.yaml`).
- Shell: `set -Eeuo pipefail` at the top of every script (matches `.github/scripts/e2e/e2e-validate.sh`).

---

## File Structure

**Create:**
- `guides/workload-autoscaling/verify/run.sh` — CLI entrypoint (`lint`, `test`).
- `guides/workload-autoscaling/verify/lib/tags.sh` — extract tagged blocks + tag ids from a README.
- `guides/workload-autoscaling/verify/lib/recipe.sh` — parse recipe yaml (via `yq`), apply substitutions.
- `guides/workload-autoscaling/verify/lib/lint.sh` — the sync check (README ids vs recipe ids).
- `guides/workload-autoscaling/verify/lib/assert.sh` — cluster assertions (resource Ready, HPA replicas moved).
- `guides/workload-autoscaling/verify/lib/drive_scale.sh` — traffic + fake-metrics strategies.
- `guides/workload-autoscaling/verify/profiles/kind.sh` — provision Kind + full EPP serving stack.
- `guides/workload-autoscaling/verify/profiles/existing.sh` — verify prereqs only.
- `guides/workload-autoscaling/verify/profiles/ocp.sh` — verify prereqs (UWM/Thanos aware).
- `guides/workload-autoscaling/verify/profiles/kind-config.yaml` — 1-node kind config.
- `guides/workload-autoscaling/verify/recipes/hpa-epp.yaml` — the HPA+EPP recipe.
- `guides/workload-autoscaling/modelserver/sim/kustomization.yaml` — sim overlay.
- `guides/workload-autoscaling/modelserver/sim/patch-sim.yaml` — sim container command/probes patch.
- `guides/recipes/modelserver/components/images/sim/kustomization.yaml` — sim image component.
- `guides/workload-autoscaling/verify/tests/run_tests.sh` — dependency-free test harness + runner.
- `guides/workload-autoscaling/verify/tests/*_test.sh` — per-unit tests (created per task).
- `guides/workload-autoscaling/verify/tests/fixtures/` — sample README + recipe fixtures for offline tests.
- `guides/workload-autoscaling/verify/README.md` — how to use the runner.

**Modify:**
- `guides/workload-autoscaling/README.hpa-epp.md` — add `<!-- local:step ... -->` tags.

**Test tiers:**
- **Offline unit tests** (Tasks 1–7): pure-text/logic, no cluster, run in CI. These are the TDD core.
- **Integration smoke** (Task 12): a real `kind × sim` run, gated behind a `RUN_INTEGRATION=1` env guard so unit CI stays fast.

---

## Task 1: Test harness scaffold

**Files:**
- Create: `guides/workload-autoscaling/verify/tests/run_tests.sh`
- Create: `guides/workload-autoscaling/verify/lib/.gitkeep` (placeholder so path exists)

**Interfaces:**
- Produces: a test runner invoked as `tests/run_tests.sh` that sources every `*_test.sh` in its directory, runs every function named `test_*`, prints `PASS`/`FAIL` per test, and exits non-zero if any failed. Provides two helpers to test files: `assert_eq <expected> <actual> <msg>` and `assert_contains <haystack> <needle> <msg>`.

- [ ] **Step 1: Write the failing test**

Create `guides/workload-autoscaling/verify/tests/harness_selftest_test.sh`:

```bash
#!/usr/bin/env bash
test_assert_eq_passes_on_equal() {
  assert_eq "a" "a" "identical strings are equal"
}
test_assert_contains_finds_substring() {
  assert_contains "hello world" "world" "substring is found"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `run_tests.sh` does not exist yet (`No such file or directory`).

- [ ] **Step 3: Write minimal implementation**

Create `guides/workload-autoscaling/verify/tests/run_tests.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILURES=0
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "    assert_eq failed: $msg (expected='$expected' actual='$actual')"
    return 1
  fi
}
assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "    assert_contains failed: $msg (needle='$needle' not in haystack)"
    return 1
  fi
}

for f in "$DIR"/*_test.sh; do
  [[ -e "$f" ]] || continue
  # shellcheck disable=SC1090
  source "$f"
done

for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
  if ( "$fn" ); then
    echo "PASS $fn"
  else
    echo "FAIL $fn"
    FAILURES=$((FAILURES+1))
  fi
done

echo "----"
if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES test(s) failed"; exit 1
fi
echo "all tests passed"
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: `PASS test_assert_eq_passes_on_equal`, `PASS test_assert_contains_finds_substring`, `all tests passed`.

- [ ] **Step 5: Commit**

```bash
git add guides/workload-autoscaling/verify/tests/run_tests.sh \
        guides/workload-autoscaling/verify/tests/harness_selftest_test.sh \
        guides/workload-autoscaling/verify/lib/.gitkeep
git commit -m "test: add dependency-free bash test harness for guide runner"
```

---

## Task 2: Tag extraction (`lib/tags.sh`)

**Files:**
- Create: `guides/workload-autoscaling/verify/lib/tags.sh`
- Create: `guides/workload-autoscaling/verify/tests/tags_test.sh`
- Create: `guides/workload-autoscaling/verify/tests/fixtures/sample.md`

**Interfaces:**
- Produces:
  - `tags_ids <readme_path>` — prints each tagged step id, one per line, in document order. A tag is a line matching `<!-- local:step id=<id> ... -->`.
  - `tags_ignored_ids <readme_path>` — prints ids of tags that carry an `ignore="..."` attribute.
  - `tags_block <readme_path> <id>` — prints the verbatim contents of the fenced ```` ```bash ```` block immediately following the tag with that id (block body only, without the fence lines). Exits 1 if the id is not found.

- [ ] **Step 1: Write the fixture**

Create `guides/workload-autoscaling/verify/tests/fixtures/sample.md`:

````markdown
# Sample

<!-- local:step id=first -->
```bash
echo first-command
```

Some prose.

<!-- local:step id=second -->
```bash
kubectl apply -f second.yaml
```

<!-- local:step id=informational ignore="just output" -->
```bash
kubectl get pods
```
````

- [ ] **Step 2: Write the failing test**

Create `guides/workload-autoscaling/verify/tests/tags_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/tags.sh"
FX="$DIR/fixtures/sample.md"

test_tags_ids_in_order() {
  local out; out="$(tags_ids "$FX")"
  assert_eq $'first\nsecond\ninformational' "$out" "ids in doc order"
}
test_tags_ignored_ids() {
  local out; out="$(tags_ignored_ids "$FX")"
  assert_eq "informational" "$out" "only ignored ids"
}
test_tags_block_returns_body() {
  local out; out="$(tags_block "$FX" second)"
  assert_eq "kubectl apply -f second.yaml" "$out" "block body for id"
}
test_tags_block_missing_id_fails() {
  if tags_block "$FX" nonexistent >/dev/null 2>&1; then
    echo "    expected failure for missing id"; return 1
  fi
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `tags.sh` not found / functions undefined.

- [ ] **Step 4: Write minimal implementation**

Create `guides/workload-autoscaling/verify/lib/tags.sh`:

```bash
#!/usr/bin/env bash
# Extract HTML-comment-tagged bash blocks from a guide README.
# A tag is:  <!-- local:step id=<id> [ignore="..."] -->
# and binds to the ```bash fenced block immediately following it.

_tags_tagline_re='^<!--[[:space:]]*local:step[[:space:]]+id=([A-Za-z0-9_-]+)'

tags_ids() {
  local readme="$1"
  grep -oE "$_tags_tagline_re" "$readme" 2>/dev/null | sed -E 's/.*id=//'
}

tags_ignored_ids() {
  local readme="$1"
  grep -E '^<!--[[:space:]]*local:step[[:space:]].*ignore=' "$readme" 2>/dev/null \
    | sed -E 's/.*id=([A-Za-z0-9_-]+).*/\1/'
}

# Print the body of the ```bash block that immediately follows the tag for <id>.
tags_block() {
  local readme="$1" want="$2"
  awk -v want="$want" '
    match($0, /^<!--[[:space:]]*local:step[[:space:]]+id=([A-Za-z0-9_-]+)/, m) {
      cur = m[1]; expecting = 1; next
    }
    expecting && /^```bash[[:space:]]*$/ { if (cur == want) { infence = 1 }; expecting = 0; next }
    expecting && /^```/ { expecting = 0 }           # some other fence, not bash
    infence && /^```[[:space:]]*$/ { exit }
    infence { print }
  ' "$readme" | { local found; found="$(cat)"; [[ -n "$found" ]] || return 1; printf '%s' "$found"; }
}
```

> Note: uses GNU awk `match(...,arr)`. macOS ships BSD awk. Add a guard: if `awk --version 2>/dev/null | grep -qi gnu` is false, the script must `command -v gawk` and use it. Include this check at the top of `tags.sh`:
> ```bash
> if awk --version 2>/dev/null | grep -qi 'gnu awk'; then AWK=awk
> elif command -v gawk >/dev/null 2>&1; then AWK=gawk
> else echo "tags.sh requires GNU awk (gawk); install via 'brew install gawk'." >&2; return 1 2>/dev/null || exit 1
> fi
> ```
> and call `"$AWK"` instead of `awk` in `tags_block`.

- [ ] **Step 5: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: all `test_tags_*` PASS. (If FAIL on macOS, `brew install gawk` and re-run — the guard message will say so.)

- [ ] **Step 6: Commit**

```bash
git add guides/workload-autoscaling/verify/lib/tags.sh \
        guides/workload-autoscaling/verify/tests/tags_test.sh \
        guides/workload-autoscaling/verify/tests/fixtures/sample.md
git commit -m "feat: extract tagged bash blocks from guide READMEs"
```

---

## Task 3: Recipe parsing + substitutions (`lib/recipe.sh`)

**Files:**
- Create: `guides/workload-autoscaling/verify/lib/recipe.sh`
- Create: `guides/workload-autoscaling/verify/tests/recipe_test.sh`
- Create: `guides/workload-autoscaling/verify/tests/fixtures/sample-recipe.yaml`

**Interfaces:**
- Consumes: `yq` (v4, confirmed installed).
- Produces:
  - `recipe_step_ids <recipe>` — prints `steps[].id`, one per line, in order.
  - `recipe_readme <recipe>` — prints the `readme:` path (relative to the recipe file's dir), resolved to an absolute path.
  - `recipe_apply_subs <recipe> <text>` — reads `substitutions[]` (`match`/`replace` regex pairs) and applies each with `sed -E` to the given text on stdin→stdout.
  - `recipe_assert_for <recipe> <id>` — prints the assert spec for a step as `kind=<k> name=<n> replicas=<expr> within=<dur>` (empty if the step has no `assert`).

- [ ] **Step 1: Write the fixture**

Create `guides/workload-autoscaling/verify/tests/fixtures/sample-recipe.yaml`:

```yaml
readme: ./sample.md
env:
  NAMESPACE: demo-ns
substitutions:
  - match: 'second\.yaml'
    replace: 'local-second.yaml'
steps:
  - id: first
  - id: second
    assert: {kind: hpa, name: demo-hpa, replicas: ">1", within: 120s}
drive_scale:
  sim:  { load: {generator: builtin-burst, concurrency: 10, duration: 30s} }
```

- [ ] **Step 2: Write the failing test**

Create `guides/workload-autoscaling/verify/tests/recipe_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/recipe.sh"
RX="$DIR/fixtures/sample-recipe.yaml"

test_recipe_step_ids() {
  assert_eq $'first\nsecond' "$(recipe_step_ids "$RX")" "step ids in order"
}
test_recipe_readme_resolves_abs() {
  local out; out="$(recipe_readme "$RX")"
  assert_contains "$out" "/fixtures/sample.md" "readme resolved relative to recipe"
}
test_recipe_apply_subs() {
  local out; out="$(printf 'kubectl apply -f second.yaml' | recipe_apply_subs "$RX" /dev/stdin)"
  assert_eq "kubectl apply -f local-second.yaml" "$out" "substitution applied"
}
test_recipe_assert_for_second() {
  local out; out="$(recipe_assert_for "$RX" second)"
  assert_contains "$out" "name=demo-hpa" "assert name parsed"
  assert_contains "$out" "replicas=>1" "assert replicas parsed"
}
test_recipe_assert_for_first_empty() {
  assert_eq "" "$(recipe_assert_for "$RX" first)" "no assert -> empty"
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `recipe.sh` not found.

- [ ] **Step 4: Write minimal implementation**

Create `guides/workload-autoscaling/verify/lib/recipe.sh`:

```bash
#!/usr/bin/env bash
# Parse a runner recipe (YAML) using yq v4.

recipe_step_ids() { yq -r '.steps[].id' "$1"; }

recipe_readme() {
  local recipe="$1" rel dir
  rel="$(yq -r '.readme' "$recipe")"
  dir="$(cd "$(dirname "$recipe")" && pwd)"
  ( cd "$dir" && cd "$(dirname "$rel")" && printf '%s/%s' "$(pwd)" "$(basename "$rel")" )
}

# recipe_apply_subs <recipe> <file>   (reads text from file, e.g. /dev/stdin)
recipe_apply_subs() {
  local recipe="$1" file="$2" text n i m r
  text="$(cat "$file")"
  n="$(yq -r '.substitutions | length' "$recipe")"
  for (( i=0; i<n; i++ )); do
    m="$(yq -r ".substitutions[$i].match" "$recipe")"
    r="$(yq -r ".substitutions[$i].replace" "$recipe")"
    text="$(printf '%s' "$text" | sed -E "s|$m|$r|g")"
  done
  printf '%s' "$text"
}

recipe_assert_for() {
  local recipe="$1" id="$2"
  yq -r --arg id "$id" '
    .steps[] | select(.id == $id) | select(.assert) | .assert
    | "kind=\(.kind) name=\(.name) replicas=\(.replicas) within=\(.within)"
  ' "$recipe"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: all `test_recipe_*` PASS.

- [ ] **Step 6: Commit**

```bash
git add guides/workload-autoscaling/verify/lib/recipe.sh \
        guides/workload-autoscaling/verify/tests/recipe_test.sh \
        guides/workload-autoscaling/verify/tests/fixtures/sample-recipe.yaml
git commit -m "feat: parse runner recipes and apply substitutions"
```

---

## Task 4: Sync lint (`lib/lint.sh`)

**Files:**
- Create: `guides/workload-autoscaling/verify/lib/lint.sh`
- Create: `guides/workload-autoscaling/verify/tests/lint_test.sh`
- Create: `guides/workload-autoscaling/verify/tests/fixtures/recipe-broken-ref.yaml`
- Create: `guides/workload-autoscaling/verify/tests/fixtures/recipe-missing-step.yaml`

**Interfaces:**
- Consumes: `tags_ids`, `tags_ignored_ids` (Task 2); `recipe_step_ids`, `recipe_readme` (Task 3).
- Produces: `lint_recipe <recipe>` — prints one `✗ ...` line per problem and returns non-zero if any; prints `✓ <n> steps, in sync` and returns 0 when clean. Two problem classes:
  - **broken reference**: a recipe step id not tagged in the README.
  - **untested step**: a README-tagged id that is neither a recipe step nor marked `ignore`.

- [ ] **Step 1: Write the fixtures**

Create `guides/workload-autoscaling/verify/tests/fixtures/recipe-broken-ref.yaml` (references `ghost`, not in `sample.md`):

```yaml
readme: ./sample.md
steps:
  - id: first
  - id: ghost
```

Create `guides/workload-autoscaling/verify/tests/fixtures/recipe-missing-step.yaml` (omits `second`, which is tagged and not ignored):

```yaml
readme: ./sample.md
steps:
  - id: first
```

- [ ] **Step 2: Write the failing test**

Create `guides/workload-autoscaling/verify/tests/lint_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/tags.sh"
source "$DIR/../lib/recipe.sh"
source "$DIR/../lib/lint.sh"

test_lint_clean_recipe_passes() {
  # sample-recipe.yaml references first+second; informational is ignored -> in sync
  if ! lint_recipe "$DIR/fixtures/sample-recipe.yaml" >/dev/null; then
    echo "    expected clean recipe to pass"; return 1
  fi
}
test_lint_broken_reference_fails() {
  local out; out="$(lint_recipe "$DIR/fixtures/recipe-broken-ref.yaml" 2>&1)" && { echo "    expected failure"; return 1; }
  assert_contains "$out" "ghost" "reports the broken id"
}
test_lint_missing_step_fails() {
  local out; out="$(lint_recipe "$DIR/fixtures/recipe-missing-step.yaml" 2>&1)" && { echo "    expected failure"; return 1; }
  assert_contains "$out" "second" "reports the untested id"
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `lint.sh` not found.

- [ ] **Step 4: Write minimal implementation**

Create `guides/workload-autoscaling/verify/lib/lint.sh`:

```bash
#!/usr/bin/env bash
# Requires tags.sh and recipe.sh to be sourced first.

lint_recipe() {
  local recipe="$1" readme problems=0
  readme="$(recipe_readme "$recipe")"

  local -a tagged ignored steps
  mapfile -t tagged  < <(tags_ids "$readme")
  mapfile -t ignored < <(tags_ignored_ids "$readme")
  mapfile -t steps   < <(recipe_step_ids "$recipe")

  _in() { local x="$1"; shift; local e; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }

  # broken reference: recipe step not tagged in README
  local s
  for s in "${steps[@]}"; do
    if ! _in "$s" "${tagged[@]}"; then
      echo "✗ recipe references '$s' — no matching <!-- local:step --> in $(basename "$readme")   (broken reference)"
      problems=$((problems+1))
    fi
  done

  # untested step: tagged, not ignored, not a recipe step
  local t
  for t in "${tagged[@]}"; do
    if ! _in "$t" "${steps[@]}" && ! _in "$t" "${ignored[@]}"; then
      echo "✗ README step '$t' is tagged but not in the recipe and not marked ignore   (untested step)"
      problems=$((problems+1))
    fi
  done

  if [[ "$problems" -gt 0 ]]; then return 1; fi
  echo "✓ ${#steps[@]} steps, in sync"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: all `test_lint_*` PASS.

- [ ] **Step 6: Commit**

```bash
git add guides/workload-autoscaling/verify/lib/lint.sh \
        guides/workload-autoscaling/verify/tests/lint_test.sh \
        guides/workload-autoscaling/verify/tests/fixtures/recipe-broken-ref.yaml \
        guides/workload-autoscaling/verify/tests/fixtures/recipe-missing-step.yaml
git commit -m "feat: add README/recipe sync lint"
```

---

## Task 5: Cluster assertions (`lib/assert.sh`)

**Files:**
- Create: `guides/workload-autoscaling/verify/lib/assert.sh`
- Create: `guides/workload-autoscaling/verify/tests/assert_test.sh`

**Interfaces:**
- Consumes: a `kubectl` shim on `PATH` for tests (`KUBECTL` env var overrides the binary; default `kubectl`).
- Produces:
  - `assert_replicas_gt <namespace> <hpa_name> <min> <within_seconds>` — polls `kubectl get hpa <name> -n <ns> -o jsonpath='{.status.currentReplicas}'` every 5s until it exceeds `<min>` or the deadline; returns 0 on success, 1 on timeout.
  - `_cmp_replicas <expr> <value>` — helper: given an expr like `>1` and an integer value, returns 0 if the comparison holds. Supports `>N`, `>=N`, `==N`.

- [ ] **Step 1: Write the failing test** (tests the pure comparison + polling against a fake `kubectl`)

Create `guides/workload-autoscaling/verify/tests/assert_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/assert.sh"

test_cmp_gt_true() { _cmp_replicas ">1" 2 || { echo "    2>1 should hold"; return 1; }; }
test_cmp_gt_false() { if _cmp_replicas ">1" 1; then echo "    1>1 should fail"; return 1; fi; }
test_cmp_gte_true() { _cmp_replicas ">=2" 2 || { echo "    2>=2 should hold"; return 1; }; }

test_assert_replicas_polls_fake_kubectl() {
  # Fake kubectl that returns 3 immediately.
  local tmp; tmp="$(mktemp -d)"
  cat >"$tmp/kubectl" <<'EOF'
#!/usr/bin/env bash
echo 3
EOF
  chmod +x "$tmp/kubectl"
  KUBECTL="$tmp/kubectl" assert_replicas_gt demo demo-hpa 1 10 \
    || { echo "    expected success with fake replicas=3"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `assert.sh` not found.

- [ ] **Step 3: Write minimal implementation**

Create `guides/workload-autoscaling/verify/lib/assert.sh`:

```bash
#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"

_cmp_replicas() {
  local expr="$1" val="$2"
  case "$expr" in
    ">="*) [[ "$val" -ge "${expr#>=}" ]] ;;
    ">"*)  [[ "$val" -gt "${expr#>}" ]] ;;
    "=="*) [[ "$val" -eq "${expr#==}" ]] ;;
    *) return 2 ;;
  esac
}

assert_replicas_gt() {
  local ns="$1" name="$2" min="$3" within="$4"
  local deadline=$(( SECONDS + within )) cur
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    cur="$("$KUBECTL" get hpa "$name" -n "$ns" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo 0)"
    [[ -z "$cur" ]] && cur=0
    if _cmp_replicas ">$min" "$cur"; then
      echo "  ✓ hpa/$name currentReplicas=$cur (> $min)"
      return 0
    fi
    sleep 5
  done
  echo "  ✗ hpa/$name did not exceed $min replicas within ${within}s (last=$cur)"
  return 1
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: all `test_cmp_*` and `test_assert_replicas_polls_fake_kubectl` PASS (the fake-kubectl test returns within one loop).

- [ ] **Step 5: Commit**

```bash
git add guides/workload-autoscaling/verify/lib/assert.sh \
        guides/workload-autoscaling/verify/tests/assert_test.sh
git commit -m "feat: add HPA replica-scaling assertion with polling"
```

---

## Task 6: Sim image component + overlay

**Files:**
- Create: `guides/recipes/modelserver/components/images/sim/kustomization.yaml`
- Create: `guides/workload-autoscaling/modelserver/sim/kustomization.yaml`
- Create: `guides/workload-autoscaling/modelserver/sim/patch-sim.yaml`
- Create: `guides/workload-autoscaling/verify/tests/sim_overlay_test.sh`

**Interfaces:**
- Consumes: the shared base `guides/recipes/modelserver/base/single-host/default` and the `REPLACE_MODEL_SERVER_IMAGE` image placeholder (confirmed convention).
- Produces: `kubectl kustomize guides/workload-autoscaling/modelserver/sim` renders a `Deployment` named `optimized-baseline-sim-decode` whose container image is `ghcr.io/llm-d/llm-d-inference-sim:v0.9.0`, with `command: ["/app/llm-d-inference-sim"]` args serving the model on port 8000, probes on `/health/ready` and `/v1/models`, and **no GPU resource requests**.

- [ ] **Step 1: Write the failing test** (renders the overlay and greps the output)

Create `guides/workload-autoscaling/verify/tests/sim_overlay_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../../.." && pwd)"   # repo root
OVERLAY="$ROOT/guides/workload-autoscaling/modelserver/sim"

test_sim_overlay_renders_sim_image() {
  local out; out="$(kubectl kustomize "$OVERLAY" 2>&1)" || { echo "    kustomize failed: $out"; return 1; }
  assert_contains "$out" "ghcr.io/llm-d/llm-d-inference-sim:v0.9.0" "sim image present"
  assert_contains "$out" "/health/ready" "readiness path patched for sim"
}
test_sim_overlay_has_no_gpu_request() {
  local out; out="$(kubectl kustomize "$OVERLAY" 2>&1)"
  if [[ "$out" == *"nvidia.com/gpu"* ]]; then echo "    overlay must not request GPUs"; return 1; fi
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — overlay dir does not exist, `kustomize` errors.

- [ ] **Step 3: Write the image component**

Create `guides/recipes/modelserver/components/images/sim/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
images:
  - name: REPLACE_MODEL_SERVER_IMAGE
    newName: ghcr.io/llm-d/llm-d-inference-sim
    newTag: v0.9.0
```

- [ ] **Step 4: Write the overlay kustomization** (mirrors `optimized-baseline/modelserver/cpu/vllm/kustomization.yaml`)

Create `guides/workload-autoscaling/modelserver/sim/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../recipes/modelserver/base/single-host/default

namePrefix: optimized-baseline-sim-

components:
  - ../../../recipes/modelserver/components/images/sim

labels:
  - pairs:
      llm-d.ai/guide: optimized-baseline
      llm-d.ai/model: Qwen3-32B
      llm-d.ai/accelerator-variant: sim
    includeSelectors: true
    includeTemplates: true
patches:
  - path: patch-sim.yaml
```

- [ ] **Step 5: Write the deployment patch** (sim command + probes + tiny resources)

Create `guides/workload-autoscaling/modelserver/sim/patch-sim.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: decode
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: modelserver
          command: ["/app/llm-d-inference-sim"]
          args:
            - "--model=Qwen/Qwen3-32B"
            - "--served-model-name=Qwen/Qwen3-32B"
            - "--port=8000"
          readinessProbe:
            httpGet:
              path: /health/ready
              port: modelserver
          livenessProbe:
            httpGet:
              path: /health/ready
              port: modelserver
          startupProbe:
            httpGet:
              path: /v1/models
              port: modelserver
          resources:
            requests:
              cpu: "100m"
              memory: 256Mi
            limits:
              cpu: "500m"
              memory: 512Mi
```

> The base deployment (`decode-deployment.yaml`) sets `livenessProbe`/`readinessProbe`/`startupProbe` with `httpGet` — a strategic-merge patch of the same fields replaces the paths. If a later error shows the sim entrypoint path is wrong, verify it against `docker run --rm --entrypoint sh ghcr.io/llm-d/llm-d-inference-sim:v0.9.0 -c 'ls /app'`; the plan's assumed path is `/app/llm-d-inference-sim`.

- [ ] **Step 6: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: `test_sim_overlay_*` PASS.

- [ ] **Step 7: Commit**

```bash
git add guides/recipes/modelserver/components/images/sim \
        guides/workload-autoscaling/modelserver/sim \
        guides/workload-autoscaling/verify/tests/sim_overlay_test.sh
git commit -m "feat: add simulator modelserver overlay (no GPU, arm64)"
```

---

## Task 7: `run.sh` CLI wiring (lint path) + arg validation

**Files:**
- Create: `guides/workload-autoscaling/verify/run.sh`
- Create: `guides/workload-autoscaling/verify/tests/cli_test.sh`

**Interfaces:**
- Consumes: all `lib/*.sh`.
- Produces: an executable `run.sh` with:
  - `run.sh lint <recipe>` → sources libs, calls `lint_recipe`, exits with its status.
  - `run.sh test --env <e> --modelserver <m> <recipe>` → validates flags, rejects `kind`+`vllm` with a clear message and exit 2, runs `lint_recipe` first (abort on failure), then dispatches to the profile + steps + drive_scale + assert (profile/exec wired in Tasks 8–11; for this task `test` may stop after lint with a `TODO` marker guarded behind an env var `RUNNER_LINT_ONLY=1` used by the CLI test).

- [ ] **Step 1: Write the failing test**

Create `guides/workload-autoscaling/verify/tests/cli_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$DIR/../run.sh"
RX="$DIR/fixtures/sample-recipe.yaml"

test_cli_rejects_kind_vllm() {
  local out; out="$(bash "$RUN" test --env kind --modelserver vllm "$RX" 2>&1)" && { echo "    should reject"; return 1; }
  assert_contains "$out" "no GPU" "explains why kind+vllm is rejected"
}
test_cli_lint_subcommand_runs() {
  bash "$RUN" lint "$RX" >/dev/null || { echo "    lint should pass on in-sync recipe"; return 1; }
}
test_cli_test_runs_lint_first() {
  # A broken recipe must make `test` abort even in lint-only mode.
  local out; out="$(RUNNER_LINT_ONLY=1 bash "$RUN" test --env kind --modelserver sim "$DIR/fixtures/recipe-broken-ref.yaml" 2>&1)" \
    && { echo "    should abort on out-of-sync recipe"; return 1; }
  assert_contains "$out" "broken reference" "lint ran before execution"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `run.sh` not found.

- [ ] **Step 3: Write minimal implementation**

Create `guides/workload-autoscaling/verify/run.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/tags.sh"
source "$HERE/lib/recipe.sh"
source "$HERE/lib/lint.sh"
source "$HERE/lib/assert.sh"
source "$HERE/lib/drive_scale.sh" 2>/dev/null || true   # added in Task 11

usage() { echo "usage: run.sh lint <recipe> | run.sh test --env <kind|existing|ocp> --modelserver <sim|vllm> <recipe>" >&2; exit 2; }

cmd="${1:-}"; shift || true
case "$cmd" in
  lint)
    [[ $# -eq 1 ]] || usage
    lint_recipe "$1"
    ;;
  test)
    ENV=""; MS=""; RECIPE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --env) ENV="$2"; shift 2 ;;
        --modelserver) MS="$2"; shift 2 ;;
        -*) echo "unknown flag: $1" >&2; usage ;;
        *) RECIPE="$1"; shift ;;
      esac
    done
    [[ -n "$ENV" && -n "$MS" && -n "$RECIPE" ]] || usage
    case "$ENV" in kind|existing|ocp) ;; *) echo "bad --env: $ENV" >&2; usage ;; esac
    case "$MS" in sim|vllm) ;; *) echo "bad --modelserver: $MS" >&2; usage ;; esac
    if [[ "$ENV" == "kind" && "$MS" == "vllm" ]]; then
      echo "error: --env kind --modelserver vllm is unsupported (no GPU in Kind on a laptop)." >&2
      exit 2
    fi
    echo "==> lint"
    lint_recipe "$RECIPE"
    if [[ "${RUNNER_LINT_ONLY:-0}" == "1" ]]; then echo "(lint-only mode)"; exit 0; fi
    # Full execution wired in Tasks 8-11:
    source "$HERE/profiles/$ENV.sh"
    run_env_provision "$MS" "$RECIPE"          # Task 8/9/10
    runner_exec_steps "$RECIPE" "$MS"          # Task 11
    runner_drive_and_assert "$RECIPE" "$MS"    # Task 11
    ;;
  ""|-h|--help) usage ;;
  *) echo "unknown command: $cmd" >&2; usage ;;
esac
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: `test_cli_*` PASS. (The `test` full-execution path is exercised only under integration in Task 12; unit tests use `RUNNER_LINT_ONLY=1` and the reject/lint cases.)

- [ ] **Step 5: Commit**

```bash
git add guides/workload-autoscaling/verify/run.sh \
        guides/workload-autoscaling/verify/tests/cli_test.sh
chmod +x guides/workload-autoscaling/verify/run.sh
git commit -m "feat: add run.sh CLI with lint and arg validation"
```

---

## Task 8: `kind` profile — cluster + monitoring stack

**Files:**
- Create: `guides/workload-autoscaling/verify/profiles/kind-config.yaml`
- Create: `guides/workload-autoscaling/verify/profiles/kind.sh`

**Interfaces:**
- Produces: `run_env_provision <modelserver> <recipe>` (in `kind.sh`) that: creates a kind cluster named `llmd-autoscaling` if absent; installs kube-prometheus-stack with TLS enabled and KEDA + Prometheus adapter into `llm-d-monitoring`; loads the sim image into the cluster; creates the guide namespace `llm-d-optimized-baseline`. Idempotent (safe to re-run). Defines `run_env_verify_monitoring` used by other profiles.

> This task has no offline unit test (it provisions real infra). It is validated by the Task 12 integration smoke. Keep the script small and each action idempotent.

- [ ] **Step 1: Write the kind config**

Create `guides/workload-autoscaling/verify/profiles/kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
```

- [ ] **Step 2: Write the profile**

Create `guides/workload-autoscaling/verify/profiles/kind.sh`:

```bash
#!/usr/bin/env bash
# kind environment profile: provisions a self-contained no-GPU cluster.
CLUSTER="${KIND_CLUSTER:-llmd-autoscaling}"
MON_NS="${MONITORING_NAMESPACE:-llm-d-monitoring}"
GUIDE_NS="${NAMESPACE:-llm-d-optimized-baseline}"
SIM_IMAGE="ghcr.io/llm-d/llm-d-inference-sim:v0.9.0"

run_env_provision() {
  local modelserver="$1"
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    kind create cluster --name "$CLUSTER" \
      --config "$(dirname "${BASH_SOURCE[0]}")/kind-config.yaml"
  fi
  kubectl create namespace "$MON_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "$GUIDE_NS" --dry-run=client -o yaml | kubectl apply -f -

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null

  # kube-prometheus-stack with TLS on the Prometheus web endpoint.
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "$MON_NS" \
    --set prometheus.prometheusSpec.web.tlsConfig.cert.secret.name=prometheus-web-tls \
    --wait --timeout 10m

  helm upgrade --install keda kedacore/keda --namespace "$MON_NS" --wait --timeout 5m
  helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
    --namespace "$MON_NS" --wait --timeout 5m

  # Load the sim image so no pull is needed.
  docker pull "$SIM_IMAGE"
  kind load docker-image "$SIM_IMAGE" --name "$CLUSTER"

  run_env_verify_monitoring
}

run_env_verify_monitoring() {
  kubectl -n "$MON_NS" get deploy >/dev/null
  echo "  ✓ monitoring namespace $MON_NS reachable"
}
```

> **TLS note (design risk):** the guide's `create-tls-secret` step reads secret `prometheus-web-tls` for the CA. The exact `--set` path for enabling TLS in the installed kube-prometheus-stack chart version must be verified against `helm show values prometheus-community/kube-prometheus-stack | grep -A20 tlsConfig` during implementation, and the secret created if the chart does not auto-generate it. Adjust the `--set` block accordingly; do not leave TLS disabled (WVA/guide require HTTPS).

- [ ] **Step 3: Manual smoke (no unit test)**

Run: `bash -c 'source guides/workload-autoscaling/verify/profiles/kind.sh; declare -F run_env_provision'`
Expected: prints `run_env_provision` (function is defined and sourceable without error).

- [ ] **Step 4: Commit**

```bash
git add guides/workload-autoscaling/verify/profiles/kind-config.yaml \
        guides/workload-autoscaling/verify/profiles/kind.sh
git commit -m "feat: add kind environment profile (cluster + monitoring)"
```

---

## Task 9: `kind` profile — EPP serving stack

**Files:**
- Modify: `guides/workload-autoscaling/verify/profiles/kind.sh` (extend `run_env_provision`)

**Interfaces:**
- Consumes: `GAIE_VERSION`, `ROUTER_STANDALONE_CHART`, `ROUTER_CHART_VERSION` from `guides/env.sh` (confirmed values: `GAIE_VERSION=v1.5.0`, chart `oci://ghcr.io/llm-d/charts/llm-d-router-standalone`, `ROUTER_CHART_VERSION=v0.9.0`).
- Produces: after monitoring, `run_env_provision` also installs the GAIE CRDs, the sim modelserver overlay, and the llm-d router standalone + EPP with the `flowControl` feature gate, so the EPP emits `llm_d_epp_flow_control_queue_size`.

- [ ] **Step 1: Extend the profile**

In `guides/workload-autoscaling/verify/profiles/kind.sh`, add before the final `run_env_verify_monitoring` call in `run_env_provision`:

```bash
  # --- EPP serving stack (EPP is the metric source for the HPA+EPP path) ---
  source "${REPO_ROOT:-$(git rev-parse --show-toplevel)}/guides/env.sh"

  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${GAIE_VERSION}/v1-manifests.yaml"

  # sim model server backends
  kubectl apply -k "${REPO_ROOT}/guides/workload-autoscaling/modelserver/sim" -n "$GUIDE_NS"

  # router standalone + EPP with flowControl enabled
  helm upgrade --install optimized-baseline "${ROUTER_STANDALONE_CHART}" \
    -f "${REPO_ROOT}/guides/recipes/router/base.values.yaml" \
    -f "${REPO_ROOT}/guides/optimized-baseline/router/optimized-baseline.values.yaml" \
    --set-json 'epp.featureGates=["flowControl"]' \
    -n "$GUIDE_NS" --version "${ROUTER_CHART_VERSION}" --wait --timeout 10m

  kubectl wait deployment --all -n "$GUIDE_NS" --for=condition=Available --timeout=300s
```

> The exact helm value key for the EPP feature gate (`epp.featureGates` above) must be verified against `helm show values ${ROUTER_STANDALONE_CHART} --version ${ROUTER_CHART_VERSION} | grep -i -A5 featureGate` during implementation. If the chart instead consumes an `EndpointPickerConfig` file, set the gate there. This is the one chart-coupling point; adjust the single `--set-json` line.

- [ ] **Step 2: Manual smoke**

Run: `bash -n guides/workload-autoscaling/verify/profiles/kind.sh`
Expected: no syntax errors (`bash -n` is a parse-only check).

- [ ] **Step 3: Commit**

```bash
git add guides/workload-autoscaling/verify/profiles/kind.sh
git commit -m "feat: deploy GAIE + router/EPP + sim backends in kind profile"
```

---

## Task 10: `existing` and `ocp` profiles — verify only

**Files:**
- Create: `guides/workload-autoscaling/verify/profiles/existing.sh`
- Create: `guides/workload-autoscaling/verify/profiles/ocp.sh`
- Create: `guides/workload-autoscaling/verify/tests/profiles_verify_test.sh`

**Interfaces:**
- Produces: each profile defines `run_env_provision <modelserver> <recipe>` that **only verifies** prereqs and returns non-zero with an actionable message if any is missing — it never installs infra. `existing.sh` checks: Prometheus reachable and KEDA/adapter present. `ocp.sh` additionally checks for the OpenShift monitoring (`openshift-monitoring` namespace / thanos-querier service). Both expose `run_env_verify_prereqs` for direct testing.

- [ ] **Step 1: Write the failing test** (uses a fake kubectl that reports "not found")

Create `guides/workload-autoscaling/verify/tests/profiles_verify_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

test_existing_fails_when_keda_absent() {
  local tmp; tmp="$(mktemp -d)"
  cat >"$tmp/kubectl" <<'EOF'
#!/usr/bin/env bash
# Simulate: no keda CRD, no prometheus
exit 1
EOF
  chmod +x "$tmp/kubectl"
  ( source "$DIR/../profiles/existing.sh"
    KUBECTL="$tmp/kubectl" run_env_verify_prereqs ) >"$tmp/out" 2>&1 \
    && { echo "    expected verify to fail"; rm -rf "$tmp"; return 1; }
  assert_contains "$(cat "$tmp/out")" "KEDA" "message names the missing prereq"
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `existing.sh` not found.

- [ ] **Step 3: Write `existing.sh`**

```bash
#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"
MON_NS="${MONITORING_NAMESPACE:-llm-d-monitoring}"

run_env_verify_prereqs() {
  local ok=1
  if ! "$KUBECTL" get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "  ✗ KEDA not found: install KEDA (see README.md#installing-keda-recommended)"; ok=0
  fi
  if ! "$KUBECTL" get ns "$MON_NS" >/dev/null 2>&1 \
     && ! "$KUBECTL" get svc -A 2>/dev/null | grep -qi prometheus; then
    echo "  ✗ Prometheus not found: install a monitoring stack (see docs/operations/observability/setup.md)"; ok=0
  fi
  [[ "$ok" -eq 1 ]] || return 1
  echo "  ✓ prereqs present"
}

run_env_provision() { run_env_verify_prereqs; }   # never mutates infra
```

- [ ] **Step 4: Write `ocp.sh`**

```bash
#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"

run_env_verify_prereqs() {
  local ok=1
  if ! "$KUBECTL" get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "  ✗ KEDA/Custom Metrics Autoscaler not found (see README.md note for OpenShift)"; ok=0
  fi
  if ! "$KUBECTL" -n openshift-monitoring get svc thanos-querier >/dev/null 2>&1; then
    echo "  ✗ OpenShift monitoring (thanos-querier) not found: enable User Workload Monitoring"; ok=0
  fi
  [[ "$ok" -eq 1 ]] || return 1
  echo "  ✓ OpenShift prereqs present"
}

run_env_provision() { run_env_verify_prereqs; }
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: `test_existing_fails_when_keda_absent` PASS.

- [ ] **Step 6: Commit**

```bash
git add guides/workload-autoscaling/verify/profiles/existing.sh \
        guides/workload-autoscaling/verify/profiles/ocp.sh \
        guides/workload-autoscaling/verify/tests/profiles_verify_test.sh
git commit -m "feat: add existing/ocp profiles (verify prereqs, never mutate)"
```

---

## Task 11: Step execution + drive-scale (`lib/drive_scale.sh` + exec in `run.sh`)

**Files:**
- Create: `guides/workload-autoscaling/verify/lib/drive_scale.sh`
- Create: `guides/workload-autoscaling/verify/lib/exec.sh`
- Modify: `guides/workload-autoscaling/verify/run.sh` (source `exec.sh`; the two functions it calls)
- Create: `guides/workload-autoscaling/verify/tests/exec_test.sh`

**Interfaces:**
- Consumes: `tags_block`, `recipe_apply_subs`, `recipe_step_ids`, `recipe_assert_for`, `assert_replicas_gt`, `recipe_readme`.
- Produces:
  - `runner_exec_steps <recipe> <modelserver>` (in `exec.sh`) — for each non-ignored recipe step, fetch the tagged block, apply substitutions, and run it via `bash` with the recipe's `env` exported. Aborts on first non-zero exit.
  - `runner_drive_and_assert <recipe> <modelserver>` (in `exec.sh`) — reads `drive_scale.<modelserver>`; if it has `load`, calls `drive_scale_load`; if `fake_metrics`, calls `drive_scale_fake_metrics`; then runs each step's `assert` via `assert_replicas_gt`.
  - `drive_scale_load <namespace> <gateway_svc> <concurrency> <duration>` (in `drive_scale.sh`) — launches a burst pod (`builtin-burst`) that sends concurrent `POST /v1/chat/completions` requests through the gateway for `duration`.
  - `render_step_script <recipe> <id>` (in `exec.sh`) — pure function returning the final runnable script for a step (block + substitutions), used for unit testing without a cluster.

- [ ] **Step 1: Write the failing test** (unit-tests the pure `render_step_script`)

Create `guides/workload-autoscaling/verify/tests/exec_test.sh`:

```bash
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/tags.sh"
source "$DIR/../lib/recipe.sh"
source "$DIR/../lib/exec.sh"
RX="$DIR/fixtures/sample-recipe.yaml"

test_render_step_applies_substitution() {
  local out; out="$(render_step_script "$RX" second)"
  assert_eq "kubectl apply -f local-second.yaml" "$out" "block rendered with substitution"
}
test_render_step_first_is_verbatim() {
  local out; out="$(render_step_script "$RX" first)"
  assert_eq "echo first-command" "$out" "no-sub block unchanged"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: FAIL — `exec.sh` not found.

- [ ] **Step 3: Write `lib/exec.sh`**

```bash
#!/usr/bin/env bash
# Requires tags.sh, recipe.sh, assert.sh, drive_scale.sh sourced by caller.

render_step_script() {
  local recipe="$1" id="$2" readme block
  readme="$(recipe_readme "$recipe")"
  block="$(tags_block "$readme" "$id")"
  printf '%s' "$block" | recipe_apply_subs "$recipe" /dev/stdin
}

runner_exec_steps() {
  local recipe="$1" modelserver="$2" id script
  # export recipe env
  while IFS='=' read -r k v; do [[ -n "$k" ]] && export "$k=$v"; done \
    < <(yq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$recipe")
  while read -r id; do
    [[ -z "$id" ]] && continue
    echo "==> step: $id"
    script="$(render_step_script "$recipe" "$id")"
    echo "$script" | bash
  done < <(recipe_step_ids "$recipe")
}

runner_drive_and_assert() {
  local recipe="$1" modelserver="$2"
  local ns="${NAMESPACE:-llm-d-optimized-baseline}"

  local fm; fm="$(yq -r ".drive_scale.$modelserver.fake_metrics // \"\"" "$recipe")"
  if [[ -n "$fm" ]]; then
    drive_scale_fake_metrics "$ns" "$fm"
  else
    local conc dur
    conc="$(yq -r ".drive_scale.$modelserver.load.concurrency // 50" "$recipe")"
    dur="$(yq -r ".drive_scale.$modelserver.load.duration // \"120s\"" "$recipe")"
    drive_scale_load "$ns" "$conc" "$dur" &
  fi

  # Run asserts for each step that declares one.
  local id spec kind name reps within
  while read -r id; do
    spec="$(recipe_assert_for "$recipe" "$id")"
    [[ -z "$spec" ]] && continue
    eval "$spec"    # sets kind= name= replicas= within=  (from recipe_assert_for output)
    # normalize duration like 180s -> 180
    within="${within%s}"
    assert_replicas_gt "$ns" "$name" "${replicas#>}" "$within"
  done < <(recipe_step_ids "$recipe")
  wait 2>/dev/null || true
}
```

> Note: `recipe_assert_for` prints `kind=.. name=.. replicas=.. within=..`; `eval "$spec"` binds those as shell vars. `replicas` holds e.g. `>1`; `assert_replicas_gt` takes the bare min, hence `${replicas#>}`.

- [ ] **Step 4: Write `lib/drive_scale.sh`**

```bash
#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"

# Fake-metrics strategy (WVA path, follow-up recipes). Patches sim pods live.
drive_scale_fake_metrics() {
  local ns="$1" json="$2"
  local pods; pods="$("$KUBECTL" get pods -n "$ns" -l llm-d.ai/role=decode -o name)"
  local p
  for p in $pods; do
    "$KUBECTL" exec -n "$ns" "${p#pod/}" -- \
      curl -sf -X POST localhost:8000/admin/config \
      -H 'content-type: application/json' \
      -d "{\"fake-metrics\": $json}" >/dev/null || true
  done
  echo "  ✓ fake-metrics applied to sim pods"
}

# Traffic strategy (EPP path). Burst requests through the gateway.
drive_scale_load() {
  local ns="$1" concurrency="$2" duration="$3"
  local host
  host="$("$KUBECTL" get gateway -n "$ns" -o jsonpath='{.items[0].status.addresses[0].value}' 2>/dev/null || true)"
  if [[ -z "$host" ]]; then
    # Standalone router: use the router service instead of a Gateway object.
    host="$("$KUBECTL" get svc -n "$ns" -o jsonpath='{.items[?(@.metadata.labels.llm-d\.ai/guide=="optimized-baseline")].metadata.name}' | awk '{print $1}')"
  fi
  echo "  → driving load ($concurrency concurrent for $duration) at $host"
  "$KUBECTL" run llmd-load-$$ -n "$ns" --restart=Never --image=curlimages/curl --command -- \
    sh -c "end=\$(( \$(date +%s) + ${duration%s} )); \
      while [ \$(date +%s) -lt \$end ]; do \
        for i in \$(seq 1 $concurrency); do \
          curl -s -o /dev/null -X POST http://$host/v1/chat/completions \
            -H 'content-type: application/json' \
            -d '{\"model\":\"Qwen/Qwen3-32B\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":128}' & \
        done; wait; \
      done"
}
```

> The gateway-vs-standalone host discovery mirrors `.github/scripts/e2e/e2e-validate.sh`. During integration (Task 12) confirm which applies for the standalone router install and simplify if only one path is real.

- [ ] **Step 5: Run to verify it passes**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: `test_render_step_*` PASS.

- [ ] **Step 6: Commit**

```bash
git add guides/workload-autoscaling/verify/lib/exec.sh \
        guides/workload-autoscaling/verify/lib/drive_scale.sh \
        guides/workload-autoscaling/verify/tests/exec_test.sh
git commit -m "feat: add step execution and drive-scale strategies"
```

---

## Task 12: Tag the README + author the recipe + integration smoke

**Files:**
- Modify: `guides/workload-autoscaling/README.hpa-epp.md` (add tags)
- Create: `guides/workload-autoscaling/verify/recipes/hpa-epp.yaml`
- Create: `guides/workload-autoscaling/verify/README.md`
- Create: `guides/workload-autoscaling/verify/UPDATING.md`

**Interfaces:**
- Consumes: everything above.
- Produces: a lint-clean recipe for `README.hpa-epp.md`, a documented one-command integration run, and a short maintainer doc for keeping guides and recipes in sync.

**Tagging map for `README.hpa-epp.md`** (block ids bind to the fenced bash blocks; YAML-only blocks that the reader saves to a file are marked `ignore` because the runner cannot "apply" a values file that has no command — the corresponding `helm upgrade`/`kubectl apply` command block is what gets tagged and run):

- `### 2` `epp-adapter-values.yaml` YAML block → tag `id=adapter-rules-values ignore="values file authored inline; applied by next step"`.
- `### 2` the `helm upgrade prometheus-adapter ...` block → tag `id=configure-adapter-rules`.
- `### 2` the two `kubectl get --raw ...` verify block → tag `id=verify-external-metric ignore="informational output"`.
- `### 3` the `hpa.yaml` YAML block → tag `id=hpa-manifest ignore="manifest authored inline; applied by next step"`.
- `### 4` the `kubectl apply -f hpa.yaml && kubectl get hpa ...` block → tag `id=apply-hpa`.

- [ ] **Step 1: Add tags to `README.hpa-epp.md`**

Insert the HTML comment on the line immediately above each fenced block per the map above. Example for the apply block (README lines ~158–161):

```markdown
<!-- local:step id=apply-hpa -->
​```bash
kubectl apply -f hpa.yaml
kubectl get hpa qwen-qwen3-32b-hpa -n default
​```
```

- [ ] **Step 2: Author the recipe**

Create `guides/workload-autoscaling/verify/recipes/hpa-epp.yaml`:

```yaml
readme: ../../README.hpa-epp.md
env:
  NAMESPACE: llm-d-optimized-baseline
  MONITORING_NAMESPACE: llm-d-monitoring
substitutions:
  # The guide's sample uses namespace `default` and name `qwen-qwen3-32b`.
  # Local sim deployment is `optimized-baseline-sim-decode` in the guide ns.
  - match: '-n default'
    replace: '-n llm-d-optimized-baseline'
  - match: 'qwen-qwen3-32b-hpa'
    replace: 'optimized-baseline-sim-decode-hpa'
steps:
  - id: configure-adapter-rules
  - id: apply-hpa
    assert: {kind: hpa, name: optimized-baseline-sim-decode-hpa, replicas: ">1", within: 240s}
drive_scale:
  sim:  { load: {generator: builtin-burst, concurrency: 50, duration: 180s} }
  vllm: { load: {generator: inference-perf, rps: 20, duration: 120s} }
```

> The `hpa.yaml` the guide applies targets `Deployment/qwen-qwen3-32b`; add a substitution mapping that Deployment name to `optimized-baseline-sim-decode` too if integration shows the HPA has no scale target. Keep substitutions minimal — only what the local env genuinely requires.

- [ ] **Step 3: Run lint (offline)**

Run: `bash guides/workload-autoscaling/verify/run.sh lint guides/workload-autoscaling/verify/recipes/hpa-epp.yaml`
Expected: `✓ 2 steps, in sync` (every tagged, non-ignored id is either a step or ignored).

- [ ] **Step 4: Run the full unit suite**

Run: `bash guides/workload-autoscaling/verify/tests/run_tests.sh`
Expected: `all tests passed`.

- [ ] **Step 5: Integration smoke (opt-in, requires Docker + kind)**

Run:
```bash
bash guides/workload-autoscaling/verify/run.sh test \
  --env kind --modelserver sim \
  guides/workload-autoscaling/verify/recipes/hpa-epp.yaml
```
Expected: cluster provisions, steps run, load drives the EPP queue metric up, and the assertion prints `✓ hpa/optimized-baseline-sim-decode-hpa currentReplicas=2 (> 1)`; overall exit 0. If a chart-coupling assumption (Task 8 TLS `--set`, Task 9 feature-gate key) is wrong, fix it here — those are the two flagged risk points.

- [ ] **Step 6: Write the usage README**

Create `guides/workload-autoscaling/verify/README.md` documenting: prerequisites (docker, kind, kubectl, helm, yq, gawk), the two subcommands, the env×modelserver matrix, and the "test a PR" workflow (`git checkout <branch>` then `run.sh test ...`).

- [ ] **Step 7: Write the maintainer "when the guide changes" doc**

Create `guides/workload-autoscaling/verify/UPDATING.md` — a short runbook (≈1 page) for anyone editing a workload-autoscaling guide, covering exactly these cases:

1. **You added a new `bash` step to a guide** → the runner does nothing with untagged blocks; `run.sh lint` will fail with `untested step`. Either tag it `<!-- local:step id=<id> -->` and add `- id: <id>` to the recipe (with an `assert` if it should reconcile something), or tag it `ignore="<why>"` if it is informational/output-only.
2. **You renamed or removed a tagged step** → `run.sh lint` fails with `broken reference`; update the matching `- id:` in the recipe (or drop it).
3. **You changed the commands inside a tagged block** (same id) → lint stays green (it only checks ids). Re-run `run.sh test --env kind --modelserver sim <recipe>` to confirm the change still reconciles; if the commands now need different local values, update the recipe's `substitutions:`.
4. **You changed namespaces / resource names / Prometheus URLs** → update `env:` and `substitutions:` in the recipe so the guide's literal commands still resolve locally.
5. **Before opening the PR** → run `run.sh lint <recipe>` (fast, no cluster; the same check CI runs) and, when infra changed, the full `run.sh test --env kind --modelserver sim <recipe>`.

Include a one-paragraph "how the pieces relate" map (README tags ↔ recipe step ids ↔ lint) and point to `README.md` (usage) and `DESIGN.md` (rationale). Keep it terse and imperative.

- [ ] **Step 8: Commit**

```bash
git add guides/workload-autoscaling/README.hpa-epp.md \
        guides/workload-autoscaling/verify/recipes/hpa-epp.yaml \
        guides/workload-autoscaling/verify/README.md \
        guides/workload-autoscaling/verify/UPDATING.md
git commit -m "feat: tag HPA+EPP guide, add recipe, document runner and updating"
```

---

## Self-Review

**1. Spec coverage:**
- Two axes (env × modelserver) → Tasks 7 (validation), 8–10 (envs), 11 (modelserver strategies). ✓
- Sim overlay, arm64, no GPU → Task 6. ✓
- Shared foundation incl. full EPP stack for EPP path → Tasks 8–9. ✓
- Tagged steps → Task 2 + Task 12. ✓
- Recipe manifest + substitutions → Task 3 + Task 12. ✓
- Sync lint (both failure directions), `test` runs `lint` first → Task 4 + Task 7. ✓
- Execution flow + assert replicas moved → Tasks 5, 11. ✓
- Drive-scale: traffic (EPP, both modelservers) + fake-metrics (WVA follow-up) → Task 11. ✓
- verify+fail prereqs, never mutate → Task 10. ✓
- Reject kind×vllm → Task 7. ✓
- PR testing working-tree based → Task 12 README. ✓
- AI helpers, WVA/rebalancing recipes, content-hash lint, vllm real-load → explicitly deferred (design "Follow-ups"); not in this plan. ✓

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" left as work items. Two chart-coupling unknowns (TLS `--set` path in Task 8; EPP feature-gate key in Task 9) are called out with the exact `helm show values` command to resolve them and a named fallback — these are verification steps, not placeholders.

**3. Type/name consistency:** Function names align across tasks: `tags_ids`/`tags_ignored_ids`/`tags_block` (T2) consumed in T4/T11; `recipe_step_ids`/`recipe_readme`/`recipe_apply_subs`/`recipe_assert_for` (T3) consumed in T4/T11; `lint_recipe` (T4) called in T7; `assert_replicas_gt`/`_cmp_replicas` (T5) called in T11; `run_env_provision`/`run_env_verify_prereqs` (T8–T10) called in T7; `render_step_script`/`runner_exec_steps`/`runner_drive_and_assert` (T11) called in T7. HPA name `optimized-baseline-sim-decode-hpa` is consistent between the recipe assert and the substitution in T12.
