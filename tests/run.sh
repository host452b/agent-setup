#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
total=0; failed=0
for t in "$here"/test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $(basename "$t") =="
  rc=$(
    ASSERT_FAILURES=0
    # shellcheck disable=SC1090
    . "$here/lib/assert.sh"
    . "$t"
    echo "$ASSERT_FAILURES"
  )
  rc="${rc##*$'\n'}"
  total=$((total + 1))
  if [ "${rc:-1}" != "0" ]; then failed=$((failed + 1)); echo "  -> $rc failure(s)"; fi
done
echo "Suites: $total  Failed: $failed"
[ "$failed" -eq 0 ]
