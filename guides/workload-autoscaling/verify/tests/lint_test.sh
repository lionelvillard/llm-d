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
