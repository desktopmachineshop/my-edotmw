#!/usr/bin/env bash
# Union driver: merge the named PRs, in order, at their CURRENT heads.
# Stops at the first conflict so it can be looked at rather than guessed.
#
#   bash union.sh 222 380 324 ...
set -u
HEADS=C:/Users/dmaso/AppData/Local/Temp/heads2.tsv
LOG=union.tsv

for pr in "$@"; do
  head=$(awk -F'\t' -v n="$pr" '$1==n {print $2}' "$HEADS")
  if [ -z "$head" ]; then
    echo "!! #$pr has no open head — skipped"
    printf '%s\t?\tMISSING\t\n' "$pr" >> "$LOG"
    continue
  fi
  before=$(git rev-parse HEAD)
  if git merge --no-edit --no-ff "origin/$head" >/dev/null 2>&1; then
    if [ "$(git rev-parse HEAD)" = "$before" ]; then
      echo "== #$pr $head : ALREADY"
      printf '%s\t%s\tALREADY\t\n' "$pr" "$head" >> "$LOG"
    else
      n=$(git diff --name-only "$before" HEAD | wc -l | tr -d ' ')
      echo "== #$pr $head : CLEAN ($n files)"
      printf '%s\t%s\tCLEAN\t%s\n' "$pr" "$head" "$n" >> "$LOG"
    fi
  else
    conf=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
    echo "!! #$pr $head : CONFLICT"
    echo "   $conf"
    printf '%s\t%s\tCONFLICT\t%s\n' "$pr" "$head" "$conf" >> "$LOG"
    exit 2
  fi
done
echo "-- batch complete --"
