#!/usr/bin/env bash
# Runs a command, prints its output, and on failure turns the important lines
# into GitHub annotations (readable from the public API without a login).
#
#   tool/ci_annotate.sh <title> <grep-pattern> <command...>
#
# GitHub shows at most 10 error annotations per step, so lines are packed
# 20 per annotation (up to 200 lines).
set -u
title="$1"
pattern="$2"
shift 2

out="$(mktemp)"
"$@" >"$out" 2>&1
code=$?
cat "$out"

if [ "$code" -ne 0 ]; then
  lines="$(mktemp)"
  grep -E "$pattern" "$out" | head -200 >"$lines"
  if [ ! -s "$lines" ]; then
    tail -n 60 "$out" >"$lines"
  fi
  for part in 0 1 2 3 4 5 6 7 8 9; do
    chunk="$(sed -n "$((part * 20 + 1)),$((part * 20 + 20))p" "$lines" |
      sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}')"
    if [ -n "$chunk" ]; then
      echo "::error title=${title} ($((part + 1)))::${chunk}"
    fi
  done
fi
exit "$code"
