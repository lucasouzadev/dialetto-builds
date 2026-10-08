#!/usr/bin/env bash
# Runs on the macOS job: boots an iPhone simulator, installs the unsigned
# simulator build, runs every Maestro flow in e2e/flows, and leaves a report, a
# video and a final screenshot in $E2E_OUT.
#
# Env: APP_ZIP (required), E2E_OUT, E2E_EMAIL / E2E_PASSWORD (optional), E2E_TAGS.
set -euo pipefail

OUT="${E2E_OUT:-e2e-output}"
: "${APP_ZIP:?APP_ZIP is required}"
mkdir -p "$OUT"

work="$(mktemp -d)"
ditto -x -k "$APP_ZIP" "$work"
app="$work/App.app"
test -d "$app" || { echo "::error::App.app not found in $APP_ZIP"; exit 1; }

# Newest iOS runtime, first available iPhone on it.
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def ver(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
for runtime in sorted(devices, key=ver, reverse=True):
    if ver(runtime) == (0, 0):
        continue
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
')" || { echo "::error::No available iPhone simulator on this runner"; exit 1; }
echo "Simulator: $udid"

xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app"
xcrun simctl privacy "$udid" grant all club.dialetto.app || true

xcrun simctl io "$udid" recordVideo --codec=h264 --force "$OUT/e2e.mp4" &
video_pid=$!

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

# bash 3.2 (macOS) treats an empty array as unset under `set -u`, hence the
# ${arr[@]+...} form.
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

xcrun simctl io "$udid" screenshot "$OUT/final-screen.png" || true
kill -INT "$video_pid" 2>/dev/null || true
wait "$video_pid" 2>/dev/null || true
# This repository is public and so are its artifacts: GitHub masks secrets in
# logs only. Strip the test account's credentials and tokens from every file
# first (and drop any screenshot/video that contains them).
python3 -I e2e/scrub_artifacts.py "$OUT" || true
python3 e2e/summarize.py "$OUT/report.xml" "iOS" || true
exit "$code"
