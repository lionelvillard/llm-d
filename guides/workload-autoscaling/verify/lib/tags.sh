#!/usr/bin/env bash
# Extract HTML-comment-tagged bash blocks from a guide README.
# A tag is:  <!-- local:step id=<id> [ignore="..."] [file="<name>"] -->
# and binds to the fenced block immediately following it (any language).

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

# Print the body of the fenced block that immediately follows the tag for <id>.
# Works for any fence language (```bash, ```yaml, bare ```).
# Uses only POSIX/BSD awk (2-arg match + RSTART/RLENGTH + substr; no gawk required).
tags_block() {
  local readme="$1" want="$2"
  awk -v want="$want" '
    /^<!--[[:space:]]*local:step[[:space:]]/ {
      match($0, /id=[A-Za-z0-9_-]+/)
      if (RSTART > 0) { cur = substr($0, RSTART+3, RLENGTH-3); expecting = 1 }
      next
    }
    expecting && /^```/ { if (cur == want) { infence = 1 }; expecting = 0; next }
    infence && /^```[[:space:]]*$/ { exit }
    infence { print }
  ' "$readme" | { local found; found="$(cat)"; [[ -n "$found" ]] || return 1; printf '%s' "$found"; }
}

# Print the file="<name>" attribute for a tag id (empty if none).
# Uses only POSIX/BSD awk (2-arg match + substr; no gawk required).
tags_file() {
  local readme="$1" want="$2"
  awk -v want="$want" '
    /^<!--[[:space:]]*local:step[[:space:]]/ {
      match($0, /id=[A-Za-z0-9_-]+/)
      if (!RSTART) next
      if (substr($0, RSTART+3, RLENGTH-3) != want) next
      if (match($0, /file="[^"]*"/)) print substr($0, RSTART+6, RLENGTH-7)
      exit
    }
  ' "$readme"
}
