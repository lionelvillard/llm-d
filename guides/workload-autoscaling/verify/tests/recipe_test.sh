#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/recipe.sh"
RX="$DIR/fixtures/sample-recipe.yaml"

test_recipe_step_ids() {
  assert_eq $'amanifest\nfirst\nsecond' "$(recipe_step_ids "$RX")" "step ids in order"
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
