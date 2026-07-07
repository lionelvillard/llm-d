#!/usr/bin/env bash
# Extract HTML-comment-tagged bash blocks from a guide README.
# A tag is:  <!-- local:step id=<id> [ignore="..."] -->
# and binds to the ```bash fenced block immediately following it.

if awk --version 2>/dev/null | grep -qi 'gnu awk'; then AWK=awk
elif command -v gawk >/dev/null 2>&1; then AWK=gawk
else echo "tags.sh requires GNU awk (gawk); install via 'brew install gawk'." >&2; return 1 2>/dev/null || exit 1
fi

_tags_tagline_re='^<!--[[:space:]]*local:step[[:space:]]+id=([A-Za-z0-9_-]+)'

tags_ids() {
  local readme="$1"
  grep -oE "$_tags_tagline_re" "$readme" 2>/dev/null | sed -E 's/.*id=//'
}

tags_ignored_ids() {
  local readme="$1"
  grep -E '^<!--[[:space:]]*local:step[[:space:]].*ignore=' "$readme" 2>/dev/null \
    | sed -E 's/.*id=([A-Za-z0-9_-]+).*/\1/'
}

# Print the body of the ```bash block that immediately follows the tag for <id>.
tags_block() {
  local readme="$1" want="$2"
  "$AWK" -v want="$want" '
    match($0, /^<!--[[:space:]]*local:step[[:space:]]+id=([A-Za-z0-9_-]+)/, m) {
      cur = m[1]; expecting = 1; next
    }
    expecting && /^```bash[[:space:]]*$/ { if (cur == want) { infence = 1 }; expecting = 0; next }
    expecting && /^```/ { expecting = 0 }           # some other fence, not bash
    infence && /^```[[:space:]]*$/ { exit }
    infence { print }
  ' "$readme" | { local found; found="$(cat)"; [[ -n "$found" ]] || return 1; printf '%s' "$found"; }
}
