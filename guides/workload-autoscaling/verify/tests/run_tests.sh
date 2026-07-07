#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILURES=0
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "    assert_eq failed: $msg (expected='$expected' actual='$actual')"
    return 1
  fi
}
assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "    assert_contains failed: $msg (needle='$needle' not in haystack)"
    return 1
  fi
}

for f in "$DIR"/*_test.sh; do
  [[ -e "$f" ]] || continue
  # shellcheck disable=SC1090
  source "$f"
done

for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
  if ( "$fn" ); then
    echo "PASS $fn"
  else
    echo "FAIL $fn"
    FAILURES=$((FAILURES+1))
  fi
done

echo "----"
if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES test(s) failed"; exit 1
fi
echo "all tests passed"
