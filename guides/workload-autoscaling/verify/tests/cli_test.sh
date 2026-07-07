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
test_cli_env_missing_value_exits_2() {
  bash "$RUN" test --env >/dev/null 2>&1; local rc=$?
  assert_eq 2 "$rc" "--env with no value exits 2 (usage), not a set -u crash"
}
test_cli_modelserver_missing_value_exits_2() {
  bash "$RUN" test --env kind --modelserver >/dev/null 2>&1; local rc=$?
  assert_eq 2 "$rc" "--modelserver with no value exits 2 (usage)"
}
