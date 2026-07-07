#!/usr/bin/env bash
KUBECTL="${KUBECTL:-kubectl}"

run_env_verify_prereqs() {
  local ok=1
  if ! "$KUBECTL" get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "  ✗ KEDA/Custom Metrics Autoscaler not found (see README.md note for OpenShift)"; ok=0
  fi
  if ! "$KUBECTL" -n openshift-monitoring get svc thanos-querier >/dev/null 2>&1; then
    echo "  ✗ OpenShift monitoring (thanos-querier) not found: enable User Workload Monitoring"; ok=0
  fi
  [[ "$ok" -eq 1 ]] || return 1
  echo "  ✓ OpenShift prereqs present"
}

run_env_provision() { run_env_verify_prereqs; }
