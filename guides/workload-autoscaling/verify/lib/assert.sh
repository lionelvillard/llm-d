#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"

_cmp_replicas() {
  local expr="$1" val="$2"
  case "$expr" in
    ">="*) [[ "$val" -ge "${expr#>=}" ]] ;;
    ">"*)  [[ "$val" -gt "${expr#>}" ]] ;;
    "=="*) [[ "$val" -eq "${expr#==}" ]] ;;
    *) return 2 ;;
  esac
}

assert_replicas_gt() {
  local ns="$1" name="$2" min="$3" within="$4"
  local deadline=$(( SECONDS + within )) cur
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    cur="$("$KUBECTL" get hpa "$name" -n "$ns" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo 0)"
    [[ -z "$cur" ]] && cur=0
    if _cmp_replicas ">$min" "$cur"; then
      echo "  ✓ hpa/$name currentReplicas=$cur (> $min)"
      return 0
    fi
    sleep 5
  done
  echo "  ✗ hpa/$name did not exceed $min replicas within ${within}s (last=$cur)"
  return 1
}
