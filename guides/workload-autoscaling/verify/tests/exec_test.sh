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

test_assert_field_parses_replicas_with_gt() {
  local spec="kind=hpa name=demo-hpa replicas=>1 within=120s"
  assert_eq ">1" "$(_assert_field "$spec" replicas)" "replicas value keeps > (no eval redirect)"
  assert_eq "demo-hpa" "$(_assert_field "$spec" name)" "name parsed"
  assert_eq "120s" "$(_assert_field "$spec" within)" "within parsed"
}
