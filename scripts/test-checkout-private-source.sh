#!/usr/bin/env bash
# Tests scripts/checkout-private-source.sh against the ways a deploy-key secret
# really arrives: clean, CRLF, no final newline, "\n" typed literally, base64 --
# and the ways it can be simply wrong: a public key, a token without access, a key with a
# passphrase, garbage. The clone itself is pointed at a local repository
# (REMOTE_URL), so no network and no real key are involved.
#
# usage: bash scripts/test-checkout-private-source.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/checkout-private-source.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

# A local "private repository" with a branch, a tag and a known commit.
git init -q --bare remote.git
git init -q seed
git -C seed -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git -C seed branch -M main
git -C seed tag v1
git -C seed remote add origin "$work/remote.git"
git -C seed push -q origin main v1
head_sha="$(git -C seed rev-parse HEAD)"

ssh-keygen -q -t ed25519 -N "" -f good -C test
ssh-keygen -q -t ed25519 -N "secret-passphrase" -f locked -C test

passed=0
failed=0
check() { # name, expected exit (0/1), expected text (or empty), env... -- run
  local name="$1" expect="$2" text="$3"; shift 3
  local out code
  out="$(env "$@" REMOTE_URL="$work/remote.git" DEST="$work/out" bash "$script" 2>&1)"; code=$?
  local ok=1
  if [ "$expect" = 0 ] && [ "$code" -ne 0 ]; then ok=0; fi
  if [ "$expect" = 1 ] && [ "$code" -eq 0 ]; then ok=0; fi
  if [ -n "$text" ] && ! grep -qF -- "$text" <<<"$out"; then ok=0; fi
  # The private key must never reach the log.
  if grep -q "BEGIN OPENSSH PRIVATE KEY" <<<"$out" && ! grep -q "private-key header" <<<"$out"; then ok=0; fi
  # Valid token values must never reach the log either.
  if grep -qE 'github_pat_|ghp_|gho_|ghs_' <<<"$out"; then ok=0; fi
  if grep -qF 'PRIVATE_COMMIT_MESSAGE' <<<"$out"; then ok=0; fi
  if [ "$ok" = 1 ]; then passed=$((passed + 1)); echo "ok   - $name"
  else failed=$((failed + 1)); echo "FAIL - $name (exit $code)"; printf '       %s\n' "${out//$'\n'/$'\n       '}"; fi
}

key_clean="$(cat good)"
key_crlf="$(sed 's/$/\r/' good)"
key_nonl="$(cat good)"                      # $(...) already drops the final newline
key_literal="$(awk '{printf "%s\\n", $0}' good)"
key_b64="$(base64 -w0 < good 2>/dev/null || base64 < good | tr -d '\n')"
key_indented="$(sed 's/^/   /' good)"

check "clean key"                         0 "Source commit: ${head_sha:0:7}" DEPLOY_KEY="$key_clean"
check "CRLF line endings"                 0 "Source commit:"                 DEPLOY_KEY="$key_crlf"
check "no final newline"                  0 "Source commit:"                 DEPLOY_KEY="$key_nonl"
check "newlines typed as a literal \\n"   0 "Source commit:"                 DEPLOY_KEY="$key_literal"
check "base64 of the key file"            0 "Source commit:"                 DEPLOY_KEY="$key_b64"
check "indented lines"                    0 "Source commit:"                 DEPLOY_KEY="$key_indented"
check "prints the key fingerprint"        0 "Deploy key fingerprint: 256 SHA256:" DEPLOY_KEY="$key_clean"
check "a tag as ref"                      0 "Source commit: ${head_sha:0:7}" DEPLOY_KEY="$key_clean" REF=v1
check "a full commit sha as ref"          0 "Source commit: ${head_sha:0:7}" DEPLOY_KEY="$key_clean" REF="$head_sha"

check "the PUBLIC key by mistake"         1 "holds the PUBLIC key"           DEPLOY_KEY="$(cat good.pub)"
check "a key with a passphrase"           1 "passphrase"                     DEPLOY_KEY="$(cat locked)"
check "garbage"                           1 "does not start with a private-key header" DEPLOY_KEY="hello world"
check "a truncated key"                   1 "cannot parse"                   DEPLOY_KEY="$(head -n 3 good)"
check "an unknown ref"                    1 "failed"                         DEPLOY_KEY="$key_clean" REF=does-not-exist
check "a ref with shell characters"       1 "characters a branch"            DEPLOY_KEY="$key_clean" REF='main;rm -rf /'

# --- GitHub token mode, against a stub of the GitHub API ----------------------
cat > stub_api.py <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        tok = self.headers.get("Authorization", "").replace("Bearer ", "")
        with open("api_requests", "a") as f:
            f.write("GET " + self.path + "\n")
        table = {
            "github_pat_readonly": (200, {"permissions": {"pull": True, "push": False}}),
            # These are account roles, not the token's scope. A read-only PAT
            # from the owner still reports push/admin/maintain here.
            "github_pat_owner_readonly": (200, {"permissions": {"pull": True, "push": True, "admin": True, "maintain": True}}),
            "github_pat_no_contents": (200, {"permissions": {"pull": True, "admin": True}}),
            "github_pat_expired": (401, {"message": "Bad credentials"}),
            "github_pat_noaccess": (404, {"message": "Not Found"}),
            "github_pat_forbidden": (403, {"message": "Forbidden"}),
        }
        code, body = table.get(tok, (500, {}))
        if self.path == "/repos/lucasouzadev/dialetto/commits?per_page=1":
            if tok == "github_pat_no_contents":
                code, body = 403, {"message": "Resource not accessible by personal access token"}
            elif code == 200:
                body = [{"sha": "stub", "commit": {"message": "PRIVATE_COMMIT_MESSAGE"}}]
        elif self.path != "/repos/lucasouzadev/dialetto":
            code, body = 404, {}
        data = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Length", str(len(data))); self.end_headers()
        self.wfile.write(data)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_port, flush=True)
s.serve_forever()
PY
python3 stub_api.py > stub_port &
stub_pid=$!
for _ in $(seq 1 50); do [ -s stub_port ] && break; sleep 0.1; done
api="http://127.0.0.1:$(cat stub_port)"
check "a read-only token"                 0 "Contents read access verified"  DEPLOY_KEY="github_pat_readonly" API_BASE="$api"
check "owner's read-only token despite admin role" 0 "Source commit:"         DEPLOY_KEY="github_pat_owner_readonly" API_BASE="$api"
check "metadata access without Contents"  1 "cannot read the source"          DEPLOY_KEY="github_pat_no_contents" API_BASE="$api"
check "an expired token"                  1 "rejected the token"             DEPLOY_KEY="github_pat_expired" API_BASE="$api"
check "a token without access"            1 "cannot see"                     DEPLOY_KEY="github_pat_noaccess" API_BASE="$api"
check "a forbidden token"                 1 "cannot see"                     DEPLOY_KEY="github_pat_forbidden" API_BASE="$api"
check "a classic token is refused"        1 "not supported"                  DEPLOY_KEY="ghp_unknowntoken" API_BASE="$api"
check "an OAuth token is refused"         1 "not supported"                  DEPLOY_KEY="gho_unknowntoken" API_BASE="$api"
kill "$stub_pid" 2>/dev/null

# The key file must not outlive the run.
if compgen -G "${TMPDIR:-/tmp}/tmp.*/id" > /dev/null; then
  echo "note: a key file may remain under ${TMPDIR:-/tmp} (check manually)"
fi

echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]
