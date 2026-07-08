#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/tags.sh"
FX="$DIR/fixtures/sample.md"

test_tags_ids_in_order() {
  local out; out="$(tags_ids "$FX")"
  assert_eq $'first\nsecond\ninformational\namanifest' "$out" "ids in doc order"
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
test_tags_block_extracts_yaml_block() {
  local out; out="$(tags_block "$FX" amanifest)"
  assert_contains "$out" "kind: Thing" "yaml block body extracted"
  assert_contains "$out" "name: demo" "yaml block body extracted (line 2)"
}
test_tags_file_returns_filename() {
  assert_eq "thing.yaml" "$(tags_file "$FX" amanifest)" "file= attribute parsed"
}
test_tags_file_empty_for_plain_step() {
  assert_eq "" "$(tags_file "$FX" first)" "no file= on a plain step"
}
