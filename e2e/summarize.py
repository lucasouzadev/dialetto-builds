#!/usr/bin/env python3
"""Turns Maestro's JUnit report into a table for the job summary, and prints
every failure (name + message) to the log so it can be read without opening
artifacts.

usage: summarize.py <report.xml> <platform label>
"""
import os
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "e2e-output/report.xml"
    label = sys.argv[2] if len(sys.argv) > 2 else "E2E"
    if not os.path.exists(path):
        print(f"::warning::{label}: no report at {path} (Maestro did not get as far as writing one)")
        return 0

    cases = []
    for case in ET.parse(path).getroot().iter("testcase"):
        failure = case.find("failure")
        error = case.find("error")
        problem = failure if failure is not None else error
        status = case.get("status", "")
        failed = problem is not None or status.upper() in ("ERROR", "FAILED", "FAILURE")
        message = ""
        if problem is not None:
            message = (problem.get("message") or problem.text or "").strip()
        cases.append((case.get("name") or case.get("id") or "?", failed, message, case.get("time") or ""))

    passed = sum(1 for _, failed, _, _ in cases if not failed)
    lines = [f"### {label} E2E: {passed}/{len(cases)} flows passed", "", "| Flow | Result | Time |", "|---|---|---|"]
    for name, failed, _, seconds in cases:
        lines.append(f"| {name} | {'FAILED' if failed else 'passed'} | {seconds}s |")
    text = "\n".join(lines)
    print(text)

    for name, failed, message, _ in cases:
        if failed:
            print(f"::error title={label} flow failed::{name}: {message[:500]}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
