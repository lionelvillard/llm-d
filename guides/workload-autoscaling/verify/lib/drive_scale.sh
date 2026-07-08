#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"

# Fake-metrics strategy (WVA path, follow-up recipes). Patches sim pods live.
drive_scale_fake_metrics() {
  local ns="$1" json="$2"
  local pods; pods="$("$KUBECTL" get pods -n "$ns" -l llm-d.ai/role=decode -o name)"
  local p
  for p in $pods; do
    "$KUBECTL" exec -n "$ns" "${p#pod/}" -- \
      curl -sf -X POST localhost:8000/admin/config \
      -H 'content-type: application/json' \
      -d "{\"fake-metrics\": $json}" >/dev/null || true
  done
  echo "  ✓ fake-metrics applied to sim pods"
}

# Traffic strategy (EPP path). Burst requests through the gateway.
drive_scale_load() {
  local ns="$1" concurrency="$2" duration="$3"
  local host
  host="$("$KUBECTL" get gateway -n "$ns" -o jsonpath='{.items[0].status.addresses[0].value}' 2>/dev/null || true)"
  if [[ -z "$host" ]]; then
    # Standalone router: use the router service instead of a Gateway object.
    host="$("$KUBECTL" get svc -n "$ns" -o jsonpath='{.items[?(@.metadata.labels.llm-d\.ai/guide=="optimized-baseline")].metadata.name}' | awk '{print $1}')"
  fi
  echo "  → driving load ($concurrency concurrent for $duration) at $host"
  "$KUBECTL" run llmd-load-$$ -n "$ns" --restart=Never --image=curlimages/curl --command -- \
    sh -c "end=\$(( \$(date +%s) + ${duration%s} )); \
      while [ \$(date +%s) -lt \$end ]; do \
        for i in \$(seq 1 $concurrency); do \
          curl -s -o /dev/null -X POST http://$host/v1/chat/completions \
            -H 'content-type: application/json' \
            -d '{\"model\":\"Qwen/Qwen3-32B\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":128}' & \
        done; wait; \
      done"
}
