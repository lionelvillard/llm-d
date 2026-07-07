#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/assert.sh"

test_cmp_gt_true() { _cmp_replicas ">1" 2 || { echo "    2>1 should hold"; return 1; }; }
test_cmp_gt_false() { if _cmp_replicas ">1" 1; then echo "    1>1 should fail"; return 1; fi; }
test_cmp_gte_true() { _cmp_replicas ">=2" 2 || { echo "    2>=2 should hold"; return 1; }; }

test_assert_replicas_polls_fake_kubectl() {
  # Fake kubectl that returns 3 immediately.
  local tmp; tmp="$(mktemp -d)"
  cat >"$tmp/kubectl" <<'EOF'
#!/usr/bin/env bash
echo 3
EOF
  chmod +x "$tmp/kubectl"
  KUBECTL="$tmp/kubectl" assert_replicas_gt demo demo-hpa 1 10 \
    || { echo "    expected success with fake replicas=3"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}
