#!/usr/bin/env bash
# Runs a command from the private source WITHOUT echoing its output: this
# repository is public, and test/compiler output can quote source lines.
# Prints only the exit status, counters and failing file/test names. Set
# VERBOSE=1 to print the whole log (author's explicit choice, per run).
# Usage: quiet-run.sh "<label>" <command...>
set -uo pipefail
label="$1"; shift
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
"$@" >"$log" 2>&1
code=$?
if [ "$code" -eq 0 ]; then
  echo "PASS  $label"
  grep -E '^\s*(Test Files|Tests)\s' "$log" | cut -c1-120 || true
  exit 0
fi
echo "::error title=$label::failed with exit code $code"
if [ "${VERBOSE:-}" = 1 ]; then cat "$log"; exit "$code"; fi
{
  grep -E '^\s*(Test Files|Tests)\s' "$log"
  grep -E '^\s*(FAIL|×|✗)\s' "$log"
  grep -oE '[^ ]+\([0-9]+,[0-9]+\): error TS[0-9]+' "$log"
  grep -E '^(ERROR|FAILED|AssertionError)' "$log" | cut -c1-100
} 2>/dev/null | cut -c1-200 | head -40
echo "(details withheld: this log is public. Re-run with verbose=true if you accept that.)"
exit "$code"
