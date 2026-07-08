#!/usr/bin/env bash
# Requires tags.sh, recipe.sh, assert.sh, drive_scale.sh sourced by caller.

# render_step_script <recipe> <id>
# Pure: returns the final runnable script for a step (block + substitutions).
render_step_script() {
  local recipe="$1" id="$2" readme block
  readme="$(recipe_readme "$recipe")"
  block="$(tags_block "$readme" "$id")"
  printf '%s' "$block" | recipe_apply_subs "$recipe" /dev/stdin
}

# _assert_field "<k1=v1 k2=v2 ...>" <key>  ->  prints v for the requested key
# Safe, no eval; handles > in values (plain string ops, word-split on spaces is safe
# because assert values — hpa names, >1, 120s — contain no spaces).
_assert_field() {
  local spec="$1" key="$2" tok
  for tok in $spec; do
    case "$tok" in
      "$key"=*) printf '%s' "${tok#"$key"=}"; return 0 ;;
    esac
  done
}

# runner_exec_steps <recipe> <modelserver>
# For each non-ignored recipe step, fetch the tagged block, apply substitutions,
# and run it via bash with the recipe's env exported. Aborts on first non-zero exit.
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

# runner_drive_and_assert <recipe> <modelserver>
# Drive a scale event then assert HPA replicas moved.
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

  local id spec name replicas within
  while read -r id; do
    spec="$(recipe_assert_for "$recipe" "$id")"
    [[ -z "$spec" ]] && continue
    name="$(_assert_field "$spec" name)"
    replicas="$(_assert_field "$spec" replicas)"
    within="$(_assert_field "$spec" within)"
    within="${within%s}"
    assert_replicas_gt "$ns" "$name" "${replicas#>}" "$within"
  done < <(recipe_step_ids "$recipe")
  wait 2>/dev/null || true
}
