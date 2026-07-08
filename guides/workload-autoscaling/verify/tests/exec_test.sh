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

test_render_step_file_block_returns_yaml_body() {
  # Verify render_step_script on a file= yaml block returns the block body (pure, no cluster).
  local out; out="$(render_step_script "$RX" amanifest)"
  assert_contains "$out" "kind: Thing" "yaml body returned by render_step_script"
  assert_contains "$out" "name: demo" "yaml body line 2 returned"
}

test_tags_file_on_amanifest_returns_thing_yaml() {
  local readme; readme="$(recipe_readme "$RX")"
  assert_eq "thing.yaml" "$(tags_file "$readme" amanifest)" "tags_file returns file= value for amanifest"
}

test_tags_file_on_plain_step_returns_empty() {
  local readme; readme="$(recipe_readme "$RX")"
  assert_eq "" "$(tags_file "$readme" first)" "tags_file returns empty for plain step"
}
