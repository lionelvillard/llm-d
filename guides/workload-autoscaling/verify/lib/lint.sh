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
