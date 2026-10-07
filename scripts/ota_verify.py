#!/usr/bin/env python3
"""Checks what the installed apps would receive over the air.

The OTA bundle is NOT built here. Every production deploy of the site on Vercel
also publishes /ota/latest.json and the zip it points at (the app only accepts
them from the production origin), so "publishing an OTA" means getting main
deployed on Vercel. This script answers: did that happen, and is it intact?

  - the manifest's version equals the commit that should be live;
  - the zip's sha256 equals the manifest's checksum (what the app verifies);
  - minNativeBuild in the manifest equals the one in frontend/ota.config.json.

usage: ota_verify.py --sha <full commit sha> [--ota-config path] [--wait SECONDS] [--strict]
  --wait    keep polling the manifest until it matches (up to SECONDS)
  --strict  exit 1 when the OTA is not up to date (default: only warn)
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

ORIGIN = "https://dialetto.club"


def fetch(url: str, timeout: int = 60) -> bytes:
    request = urllib.request.Request(
        url, headers={"Cache-Control": "no-cache", "User-Agent": "dialetto-builds-ota-verify"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def read_manifest() -> dict:
    return json.loads(fetch(f"{ORIGIN}/ota/latest.json"))


def zip_url(manifest: dict) -> str:
    """Same rule the app applies: the production origin, under /ota/, nothing else."""
    url = urllib.parse.urlparse(urllib.parse.urljoin(ORIGIN + "/", manifest["url"]))
    if f"{url.scheme}://{url.netloc}" != ORIGIN or not url.path.startswith("/ota/"):
        raise ValueError(f"manifest points outside {ORIGIN}/ota/: {manifest['url']}")
    return url.geturl()


def expected_min_native(path: str | None) -> int | None:
    if not path or not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return int(json.load(handle).get("minNativeBuild", 0))


def summarise(rows: list[tuple[str, str]], verdict: str) -> None:
    lines = ["### OTA check", "", "| | |", "|---|---|"] + [f"| {a} | {b} |" for a, b in rows]
    lines += ["", f"**{verdict}**"]
    text = "\n".join(lines)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sha", required=True)
    parser.add_argument("--ota-config")
    parser.add_argument("--wait", type=int, default=0)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    deadline = time.time() + args.wait
    while True:
        manifest = read_manifest()
        if manifest.get("version") == args.sha or time.time() >= deadline:
            break
        print(f"live is {str(manifest.get('version'))[:7]}, waiting for {args.sha[:7]} ...", flush=True)
        time.sleep(20)

    data = fetch(zip_url(manifest), timeout=180)
    actual = hashlib.sha256(data).hexdigest()
    min_expected = expected_min_native(args.ota_config)

    version_ok = manifest.get("version") == args.sha
    checksum_ok = actual == manifest.get("checksum")
    min_ok = min_expected is None or manifest.get("minNativeBuild") == min_expected

    mark = lambda ok: "ok" if ok else "MISMATCH"  # noqa: E731
    rows = [
        ("Live version", f"`{str(manifest.get('version'))[:7]}` (built {manifest.get('builtAt')})"),
        ("Expected version", f"`{args.sha[:7]}` -- {mark(version_ok)}"),
        ("Zip size", f"{len(data) / 1_048_576:.1f} MiB"),
        ("Zip checksum matches the manifest", mark(checksum_ok)),
        (
            "minNativeBuild",
            f"live {manifest.get('minNativeBuild')} / repo "
            f"{'n/a' if min_expected is None else min_expected} -- {mark(min_ok)}",
        ),
    ]

    healthy = checksum_ok and min_ok
    if version_ok and healthy:
        verdict = "Up to date: installed apps will receive this build."
    elif not healthy:
        verdict = "The bundle is NOT intact (checksum or minNativeBuild mismatch): apps will refuse it."
    else:
        verdict = "Behind: the live OTA is not this commit yet (the Vercel deploy has not finished, or failed)."
    summarise(rows, verdict)

    if not (version_ok and healthy):
        print(f"::warning title=OTA::{verdict}")
        return 1 if args.strict else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
