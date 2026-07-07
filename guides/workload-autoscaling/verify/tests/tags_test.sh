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
