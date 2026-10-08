#!/usr/bin/env bash
# Proves e2e/scrub_artifacts.py removes the test account's credentials and
# tokens from artifact files, using made-up values only.
set -euo pipefail

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Every "secret" below is generated at run time. Nothing secret-shaped is
# written in this file, so secret scanners (this repository is public) have
# nothing to flag, and the values are different on every run.
rand() { head -c 18 /dev/urandom | base64 | tr -d '=+/\n'; }
b64url() { base64 | tr -d '=\n' | tr '+/' '-_'; }
E2E_EMAIL="qa-$(rand | tr '[:upper:]' '[:lower:]')@example.test"
E2E_PASSWORD="pw-$(rand)"
export E2E_EMAIL E2E_PASSWORD
jwt="$(printf '{"alg":"none"}' | b64url).$(printf '{"sub":"%s"}' "$(rand)" | b64url).$(rand)"
bearer="$(rand)$(rand)"

printf '{"inputText":"%s","email":"%s"}\n' "$E2E_PASSWORD" "$E2E_EMAIL" > "$dir/commands.json"
printf 'D/Capacitor: session %s\nauthorization: Bearer %s\n' "$jwt" "$bearer" > "$dir/logcat.txt"
printf 'nothing secret here\n' > "$dir/report.xml"
printf '\x89PNG\r\n\x1a\nxx%sxx' "$E2E_PASSWORD" > "$dir/leaky.png"
printf '\x89PNG\r\n\x1a\nclean-bytes' > "$dir/clean.png"

python3 -I e2e/scrub_artifacts.py "$dir"

grep -rqF "$E2E_PASSWORD" "$dir" && fail "password still present"
grep -rqF "$E2E_EMAIL" "$dir" && fail "email still present"
grep -rqF "$jwt" "$dir" && fail "jwt still present"
grep -rqF "$bearer" "$dir" && fail "bearer value still present"
[ -e "$dir/leaky.png" ] && fail "binary containing the password was kept"
[ -e "$dir/clean.png" ] || fail "an unrelated binary was removed"
grep -q "nothing secret here" "$dir/report.xml" || fail "an unrelated text file was altered"
echo "scrub_artifacts: ok"
