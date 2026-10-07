#!/usr/bin/env bash
# Runs INSIDE the Android emulator job (android-emulator-runner's `script:`).
# Installs the APK, runs every Maestro flow in e2e/flows, and leaves a report,
# a log and a final screenshot in $E2E_OUT for the artifact upload.
#
# Env: APK_PATH (required), E2E_OUT, E2E_EMAIL / E2E_PASSWORD (optional: without
# them the flows that sign in are skipped), E2E_TAGS (optional include-tags).
set -euo pipefail

OUT="${E2E_OUT:-e2e-output}"
: "${APK_PATH:?APK_PATH is required}"
mkdir -p "$OUT"

adb wait-for-device
# -g grants the runtime permissions (notifications, microphone, ...) up front,
# so no system dialog gets in the way of a flow.
adb install -r -g "$APK_PATH"
adb logcat -c || true

env_args=()
exclude=()
if [ -n "${E2E_EMAIL:-}" ] && [ -n "${E2E_PASSWORD:-}" ]; then
  env_args+=(-e "EMAIL=${E2E_EMAIL}" -e "PASSWORD=${E2E_PASSWORD}")
else
  echo "::notice::E2E_EMAIL / E2E_PASSWORD are not set: skipping the flows tagged 'login'."
  exclude+=(--exclude-tags=login)
fi
include=()
if [ -n "${E2E_TAGS:-}" ]; then include+=(--include-tags="${E2E_TAGS}"); fi

set +e
maestro test e2e/flows \
  ${env_args[@]+"${env_args[@]}"} \
  ${exclude[@]+"${exclude[@]}"} \
  ${include[@]+"${include[@]}"} \
  --format=JUNIT --output="$OUT/report.xml" \
  --debug-output="$OUT/debug" --flatten-debug-output \
  --test-output-dir="$OUT/artifacts"
code=$?
set -e

adb logcat -d -v time > "$OUT/logcat.txt" || true
adb exec-out screencap -p > "$OUT/final-screen.png" || true
python3 e2e/summarize.py "$OUT/report.xml" "Android" || true
exit "$code"
