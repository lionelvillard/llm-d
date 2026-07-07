#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

test_existing_fails_when_keda_absent() {
  local tmp; tmp="$(mktemp -d)"
  cat >"$tmp/kubectl" <<'EOF'
#!/usr/bin/env bash
# Simulate: no keda CRD, no prometheus
exit 1
EOF
  chmod +x "$tmp/kubectl"
  ( source "$DIR/../profiles/existing.sh"
    KUBECTL="$tmp/kubectl" run_env_verify_prereqs ) >"$tmp/out" 2>&1 \
    && { echo "    expected verify to fail"; rm -rf "$tmp"; return 1; }
  assert_contains "$(cat "$tmp/out")" "KEDA" "message names the missing prereq"
  rm -rf "$tmp"
}
