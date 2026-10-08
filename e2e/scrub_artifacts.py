#!/usr/bin/env python3
"""Removes the E2E account's credentials and session tokens from the files in
an output directory before they are uploaded as workflow artifacts.

This repository is public, so its artifacts are readable by anyone signed in to
GitHub. GitHub masks secrets in LOGS only, never inside an uploaded file, and
Maestro writes the text it typed (with the password already filled in) into its
debug output, while `adb logcat` can carry session tokens.

What it does, for every file under the directory:
  - text file: replaces E2E_EMAIL and E2E_PASSWORD, and anything shaped like a
    JWT or a bearer/api key header, with a placeholder;
  - binary file (screenshots, video): cannot be edited, so it is DELETED if the
    password bytes appear anywhere inside it.
It never prints a secret, only counts.

usage: scrub_artifacts.py <directory>
env:   every E2E_* variable except E2E_TAGS and E2E_OUT is treated as a secret
"""
import os
import re
import sys

MIN_SECRET_LEN = 4
JWT = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*")
HEADER = re.compile(
    r"(?i)((?:authorization|apikey|x-api-key)[\"']?\s*[:=]\s*[\"']?(?:bearer\s+)?)[A-Za-z0-9._~+/=-]{8,}"
)


def secrets() -> list[str]:
    # Every E2E_* variable except the tag filter is credential-like: the account
    # e-mail and password today, anything the flows get later.
    values = []
    for name, value in os.environ.items():
        if name.startswith("E2E_") and name != "E2E_TAGS" and name != "E2E_OUT":
            if len(value) >= MIN_SECRET_LEN:
                values.append(value)
    return sorted(set(values), key=len, reverse=True)


def scrub_text(text: str, values: list[str]) -> str:
    for value in values:
        text = text.replace(value, "[redacted]")
    text = JWT.sub("[redacted-jwt]", text)
    return HEADER.sub(r"\1[redacted]", text)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: scrub_artifacts.py <directory>", file=sys.stderr)
        return 2
    root = sys.argv[1]
    values = secrets()
    needles = [v.encode() for v in values]
    scrubbed = deleted = 0
    for folder, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(folder, name)
            try:
                with open(path, "rb") as handle:
                    data = handle.read()
            except OSError:
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                if any(n in data for n in needles):
                    os.remove(path)
                    deleted += 1
                continue
            clean = scrub_text(text, values)
            if clean != text:
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write(clean)
                scrubbed += 1
    print(f"Artifacts: {scrubbed} text file(s) scrubbed, {deleted} binary file(s) removed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
