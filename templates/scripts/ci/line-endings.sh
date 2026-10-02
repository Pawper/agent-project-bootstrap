#!/bin/sh
# Fail when any tracked text file has CRLF line endings. Mixed endings are
# the cheapest way to make every diff a conflict. .gitattributes should
# already force LF; this check catches the file that slipped past it.
# Usage: sh scripts/ci/line-endings.sh
bad=$(git grep -I -l "$(printf '\r')" -- . ':!*.png' ':!*.jpg' ':!*.gif' ':!*.ico' ':!*.pdf' 2>/dev/null || true)
if [ -n "$bad" ]; then
  echo "These files have CRLF line endings; convert them to LF and add their type to .gitattributes:" >&2
  printf '%s\n' "$bad" >&2
  exit 1
fi
echo "Line endings are LF everywhere."
