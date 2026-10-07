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
#   DEPLOY_KEY   the secret (required). The private key, as the file's text or
#                as base64 of the file.
#   REF          branch, tag or full commit sha (default main)
#   REPO         owner/name (default lucasouzadev/dialetto)
#   DEST         where to clone (default src)
#   REMOTE_URL   override the remote (tests only)
# Writes `sha` and `short` to $GITHUB_OUTPUT when it is set.
set -euo pipefail

: "${DEPLOY_KEY:?DEPLOY_KEY is empty -- create the secret DIALETTO_DEPLOY_KEY (see README.md)}"
REF="${REF:-main}"
REPO="${REPO:-lucasouzadev/dialetto}"
DEST="${DEST:-src}"
REMOTE_URL="${REMOTE_URL:-git@github.com:${REPO}.git}"

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

case "$first" in
  ssh-*|ecdsa-*|"-----BEGIN PUBLIC KEY-----"*)
    fail "DIALETTO_DEPLOY_KEY holds the PUBLIC key. The secret must be the PRIVATE key (the file without .pub); the public one goes in the dialetto repository's Deploy keys." ;;
  ghp_*|github_pat_*|gho_*|ghs_*)
    fail "DIALETTO_DEPLOY_KEY holds a GitHub token, not an SSH key. Generate a key pair with: ssh-keygen -t ed25519 -N \"\" -f dialetto-builds-key" ;;
  "-----BEGIN OPENSSH PRIVATE KEY-----"|"-----BEGIN RSA PRIVATE KEY-----"|"-----BEGIN EC PRIVATE KEY-----") ;;
  *)
    fail "DIALETTO_DEPLOY_KEY does not start with a private-key header (it starts with '${first:0:5}...'). Paste the whole file, from the BEGIN line to the END line, or its base64." ;;
esac

# --- 3. Can OpenSSH read it? -------------------------------------------------
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

# --- 4. Clone, trusting only GitHub's published host key ---------------------
# Fingerprint SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
# (https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
echo 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' > "$dir/known_hosts"

export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$dir/known_hosts -o HostKeyAlgorithms=ssh-ed25519"
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
