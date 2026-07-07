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
  local recipe="$1" id="$2" assert_val
  export _RECIPE_STEP_ID="$id"
  assert_val="$(yq -r '.steps[] | select(.id == env(_RECIPE_STEP_ID)) | .assert' "$recipe")"
  unset _RECIPE_STEP_ID
  [[ "$assert_val" == "null" ]] && return 0
  export _RECIPE_STEP_ID="$id"
  yq -r '.steps[] | select(.id == env(_RECIPE_STEP_ID)) | .assert | "kind=\(.kind) name=\(.name) replicas=\(.replicas) within=\(.within)"' "$recipe"
  unset _RECIPE_STEP_ID
}
