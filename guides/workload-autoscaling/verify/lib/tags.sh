#!/usr/bin/env bash
# Extract HTML-comment-tagged bash blocks from a guide README.
# A tag is:  <!-- local:step id=<id> [ignore="..."] -->
# and binds to the ```bash fenced block immediately following it.

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
# Uses only POSIX/BSD awk (2-arg match + RSTART/RLENGTH + substr; no gawk required).
tags_block() {
  local readme="$1" want="$2"
  awk -v want="$want" '
    /^<!--[[:space:]]*local:step[[:space:]]/ {
      match($0, /id=[A-Za-z0-9_-]+/)
      if (RSTART > 0) { cur = substr($0, RSTART+3, RLENGTH-3); expecting = 1 }
      next
    }
    expecting && /^```bash[[:space:]]*$/ { if (cur == want) { infence = 1 }; expecting = 0; next }
    expecting && /^```/ { expecting = 0 }
    infence && /^```[[:space:]]*$/ { exit }
    infence { print }
  ' "$readme" | { local found; found="$(cat)"; [[ -n "$found" ]] || return 1; printf '%s' "$found"; }
}
