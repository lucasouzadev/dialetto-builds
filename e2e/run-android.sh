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

# The software-rendered emulator is slow enough that the launcher sometimes raises "Pixel Launcher isn't responding"
# over the app, which hides the screen from the flow (seen in run 40953312302). That dialog is about the emulator,
# not the app under test, so do not show system error dialogs.
adb shell settings put global hide_error_dialogs 1 || true

# Security audit S-09/S-20: confirm on a real (emulated) install that the shipped manifest really has backup off, and say
# what the cleartext setting resolved to. Only package flags are printed, nothing about any account.
echo "::group::Manifest hardening"
pkg_dump="$(adb shell dumpsys package club.dialetto.app | tr -d '\r')"
flags_lines="$(printf '%s\n' "$pkg_dump" | grep -E '^\s*(pkgFlags|flags|privateFlags)=' | head -5 || true)"
printf '%s\n' "$flags_lines" | tee "$OUT/manifest-flags.txt"
hardening=0
if printf '%s\n' "$flags_lines" | grep -q 'ALLOW_BACKUP'; then
  echo "HARDENING FAIL: ALLOW_BACKUP is set on the installed app" | tee -a "$OUT/manifest-flags.txt"
  hardening=1
else
  echo "HARDENING PASS: ALLOW_BACKUP is not set" | tee -a "$OUT/manifest-flags.txt"
fi
if printf '%s\n' "$pkg_dump" | grep -qi 'usesCleartextTraffic=true'; then
  echo "HARDENING FAIL: cleartext traffic is allowed" | tee -a "$OUT/manifest-flags.txt"
  hardening=1
elif printf '%s\n' "$pkg_dump" | grep -qi 'usesCleartextTraffic=false'; then
  echo "HARDENING PASS: cleartext traffic is not allowed" | tee -a "$OUT/manifest-flags.txt"
else
  echo "HARDENING INFO: this Android version does not report usesCleartextTraffic" | tee -a "$OUT/manifest-flags.txt"
fi
echo "::endgroup::"

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
# This repository is public and so are its artifacts: GitHub masks secrets in
# logs only. Strip the test account's credentials and tokens from every file
# first (and drop any screenshot/video that contains them).
python3 -I e2e/scrub_artifacts.py "$OUT" || true
python3 e2e/summarize.py "$OUT/report.xml" "Android" || true
if [ "$code" -eq 0 ] && [ "$hardening" -ne 0 ]; then code=1; fi
exit "$code"
