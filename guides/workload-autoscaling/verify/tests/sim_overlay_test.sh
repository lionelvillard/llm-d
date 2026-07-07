#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../../.." && pwd)"   # repo root
OVERLAY="$ROOT/guides/workload-autoscaling/modelserver/sim"

test_sim_overlay_renders_sim_image() {
  local out; out="$(kubectl kustomize "$OVERLAY" 2>&1)" || { echo "    kustomize failed: $out"; return 1; }
  assert_contains "$out" "ghcr.io/llm-d/llm-d-inference-sim:v0.9.0" "sim image present"
  assert_contains "$out" "/health/ready" "readiness path patched for sim"
}
test_sim_overlay_has_no_gpu_request() {
  local out; out="$(kubectl kustomize "$OVERLAY" 2>&1)"
  if [[ "$out" == *"nvidia.com/gpu"* ]]; then echo "    overlay must not request GPUs"; return 1; fi
}
