#!/usr/bin/env bash
ASSERT_FAILURES=${ASSERT_FAILURES:-0}
assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "${3:-eq}" "$1" "$2" >&2
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}
assert_contains() {
  case "$1" in
    *"$2"*) : ;;
    *) printf 'FAIL: %s\n  %s\n  does not contain: %s\n' "${3:-contains}" "$1" "$2" >&2
       ASSERT_FAILURES=$((ASSERT_FAILURES + 1)) ;;
  esac
}
assert_ok() {
  if ! "$@" >/dev/null 2>&1; then
    printf 'FAIL: expected success: %s\n' "$*" >&2
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}
assert_fail() {
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL: expected failure: %s\n' "$*" >&2
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}
