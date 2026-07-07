#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"
MON_NS="${MONITORING_NAMESPACE:-llm-d-monitoring}"

run_env_verify_prereqs() {
  local ok=1
  if ! "$KUBECTL" get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "  ✗ KEDA not found: install KEDA (see README.md#installing-keda-recommended)"; ok=0
  fi
  if ! "$KUBECTL" get ns "$MON_NS" >/dev/null 2>&1 \
     && ! "$KUBECTL" get svc -A 2>/dev/null | grep -qi prometheus; then
    echo "  ✗ Prometheus not found: install a monitoring stack (see docs/operations/observability/setup.md)"; ok=0
  fi
  [[ "$ok" -eq 1 ]] || return 1
  echo "  ✓ prereqs present"
}

run_env_provision() { run_env_verify_prereqs; }   # never mutates infra
