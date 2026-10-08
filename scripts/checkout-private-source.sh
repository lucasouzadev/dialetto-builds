#!/usr/bin/env bash
# Clones the private Dialetto repository into ./src with a read-only deploy key.
#
# Why this is a script and not just actions/checkout with `ssh-key:`: the key
# lives in a GitHub secret, and a secret pasted from a Windows editor easily
# arrives damaged (CRLF line endings, a lost final newline, "\n" typed
# literally). OpenSSH then answers only "error in libcrypto", which says
# nothing. This script repairs those cases, and when the key still cannot be
# used it says which problem it is -- looking only at the SHAPE of the value,
# never printing it.
#
# Env:
#   DEPLOY_KEY   the secret (required). Either
#                - an SSH private key (a read-only deploy key), as the file's text
#                  or as base64 of the file -- the recommended form; or
#                - a fine-grained GitHub token (`github_pat_...`), configured
#                  for this repository only with Contents: read-only. The API
#                  checks visibility and Contents read access, not token scopes:
#                  repository permissions describe the user's role, not the
#                  token's effective permissions. Classic tokens are refused.
#   REF          branch, tag or full commit sha (default main)
#   REPO         owner/name (default lucasouzadev/dialetto)
#   DEST         where to clone (default src)
#   REMOTE_URL   override the remote (tests only)
#   API_BASE     override https://api.github.com (tests only)
# Writes `sha` and `short` to $GITHUB_OUTPUT when it is set.
set -euo pipefail

: "${DEPLOY_KEY:?DEPLOY_KEY is empty -- create the secret DIALETTO_DEPLOY_KEY (see README.md)}"
REF="${REF:-main}"
REPO="${REPO:-lucasouzadev/dialetto}"
DEST="${DEST:-src}"

fail() { echo "::error title=Deploy key::$*"; exit 1; }

if ! [[ "$REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  fail "ref '$REF' has characters a branch, tag or commit never has."
fi

umask 077
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
key="$dir/id"

# --- 1. Repair the usual copy/paste damage -----------------------------------
raw="$DEPLOY_KEY"
# A key stored as base64 of the file (a way around editors that mangle it).
if ! grep -q -- '-----BEGIN' <<<"$raw"; then
  decoded="$(printf '%s' "$raw" | tr -d '[:space:]' | base64 -d 2>/dev/null || true)"
  if grep -q -- '-----BEGIN' <<<"$decoded"; then raw="$decoded"; fi
fi
printf '%s' "$raw" \
  | tr -d '\r' \
  | perl -pe 's/\\n/\n/g; s/^[ \t]+//; s/[ \t]+$//' \
  | sed '/^$/d' > "$key"
[ -n "$(tail -c1 "$key")" ] && echo >> "$key"
chmod 600 "$key"

# --- 2. Say what the value looks like, never what it is ----------------------
first="$(head -1 "$key")"
last="$(tail -1 "$key")"
lines="$(wc -l < "$key" | tr -d ' ')"
echo "Secret shape: first line is a private-key header: $([[ "$first" == -----BEGIN*PRIVATE\ KEY----- ]] && echo yes || echo NO); last line is the END line: $([[ "$last" == -----END*PRIVATE\ KEY----- ]] && echo yes || echo NO); lines: $lines"

mode=""
case "$first" in
  ssh-*|ecdsa-*|"-----BEGIN PUBLIC KEY-----"*)
    fail "DIALETTO_DEPLOY_KEY holds the PUBLIC key. The secret must be the PRIVATE key (the file without .pub); the public one goes in the dialetto repository's Deploy keys." ;;
  ghp_*|github_pat_*|gho_*|ghs_*) mode=token ;;
  "-----BEGIN OPENSSH PRIVATE KEY-----"|"-----BEGIN RSA PRIVATE KEY-----"|"-----BEGIN EC PRIVATE KEY-----") mode=ssh ;;
  *)
    # Never echo any part of the value: this log is public.
    fail "DIALETTO_DEPLOY_KEY does not start with a private-key header or a GitHub token. Paste the whole key file, from the BEGIN line to the END line, or its base64." ;;
esac

if [ "$mode" = token ]; then
  # --- 3a. A fine-grained token: verify repository and Contents read access --
  token="$(tr -d '[:space:]' < "$key")"
  case "$token" in
    github_pat_*) kind="fine-grained" ;;
    ghp_*)        kind="classic" ;;
    *)            kind="other" ;;
  esac
  echo "Credential: a GitHub token ($kind)."
  echo "::warning title=Token as deploy credential::A token is not limited to read access by this script (GitHub does not report a token's scopes). Prefer a read-only SSH deploy key for $REPO; if you keep the token, make it fine-grained, for that repository only, with Contents: read-only."
  if [ "$kind" != fine-grained ]; then
    fail "Use a fine-grained token limited to $REPO with Contents: read-only, or a read-only SSH deploy key. Classic and other token types are not supported."
  fi
  api="${API_BASE:-https://api.github.com}"
  status="$(curl -sS -m 20 -o "$dir/repo.json" -w '%{http_code}' \
    -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
    "$api/repos/$REPO" 2>/dev/null)" || fail "Could not reach the GitHub API to check the token."
  case "$status" in
    200) ;;
    401) fail "GitHub rejected the token (expired or revoked). Create a new one." ;;
    403|404) fail "The token cannot see $REPO. A fine-grained token must list that repository and have Contents: read." ;;
    *) fail "Unexpected answer ($status) from the GitHub API while checking the token." ;;
  esac
  # GET /repos only requires Metadata: read. Checking Contents separately
  # catches a token that can see the repository but cannot fetch its code.
  # Never probe write endpoints to discover a token's scope.
  status="$(curl -sS -m 20 -o "$dir/commits.json" -w '%{http_code}' \
    -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
    "$api/repos/$REPO/commits?per_page=1" 2>/dev/null)" || fail "Could not reach the GitHub API to check Contents read access."
  case "$status" in
    200) ;;
    401) fail "GitHub rejected the token (expired or revoked). Create a new one." ;;
    403|404) fail "The token cannot read the source of $REPO. Grant Contents: read-only for that repository." ;;
    *) fail "Unexpected answer ($status) from the GitHub API while checking Contents read access." ;;
  esac
  echo "Token check: repository visibility and Contents read access verified."
  echo "Token scopes are configured in GitHub: use only $REPO with Contents: read-only. Repository role permissions do not prove token write access."
  header="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $header"
  REMOTE_URL="${REMOTE_URL:-https://github.com/${REPO}.git}"
else
  # --- 3b. An SSH key: can OpenSSH read it? ----------------------------------
  # -P "" answers the passphrase question with an empty one, so a locked key
  # fails at once instead of waiting for someone to type.
  if ! pub="$(ssh-keygen -y -P "" -f "$key" 2>"$dir/err" </dev/null)"; then
    reason="$(tr '\n' ' ' < "$dir/err")"
    if grep -qi "passphrase" <<<"$reason"; then
      fail "The key is protected by a passphrase, and CI cannot type one. Generate a new pair with an EMPTY passphrase: ssh-keygen -t ed25519 -N \"\" -f dialetto-builds-key. ($reason)"
    fi
    fail "OpenSSH cannot parse the key even after repairing line endings. Re-copy the WHOLE private key file (BEGIN to END line) into the secret, or store base64 of the file instead. ($reason)"
  fi
  # The fingerprint of a PUBLIC key is safe to print: compare it with the one
  # GitHub shows for the deploy key in the dialetto repository's settings.
  echo "Deploy key fingerprint: $(ssh-keygen -lf /dev/stdin <<<"$pub")"
  REMOTE_URL="${REMOTE_URL:-git@github.com:${REPO}.git}"
fi

# --- 4. Clone ----------------------------------------------------------------
# SSH: trust only GitHub's published host key. Fingerprint
# SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
# (https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
if [ "$mode" = ssh ]; then
  echo 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' > "$dir/known_hosts"
  export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$dir/known_hosts -o HostKeyAlgorithms=ssh-ed25519"
fi
rm -rf "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin "$REMOTE_URL"
if ! out="$(git -C "$DEST" fetch --depth=1 --no-tags origin "$REF" 2>&1)"; then
  printf '  git: %s\n' "${out//$'\n'/$'\n  git: '}"
  if grep -qi "permission denied\|could not read from remote" <<<"$out"; then
    fail "GitHub rejected this key for $REPO. Add its PUBLIC half under $REPO -> Settings -> Deploy keys (read-only is enough) and check the fingerprint above matches."
  fi
  fail "git fetch of '$REF' failed (see above). Does that branch, tag or full commit sha exist in $REPO?"
fi
git -C "$DEST" -c advice.detachedHead=false checkout -q FETCH_HEAD

sha="$(git -C "$DEST" rev-parse HEAD)"
# Only the hash is printed: this repository is public, so its logs are too.
echo "Source commit: ${sha:0:7}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "sha=${sha}" >> "$GITHUB_OUTPUT"
  echo "short=${sha:0:7}" >> "$GITHUB_OUTPUT"
fi
