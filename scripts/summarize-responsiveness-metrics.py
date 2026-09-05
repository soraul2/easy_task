#!/usr/bin/env python3
"""Export raw XCTest samples plus nearest-rank p95; never label wall time input latency."""
import argparse
import json
import math
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("result", type=Path, help="Completed .xcresult bundle")
parser.add_argument("output", type=Path, help="New JSON output file")
args = parser.parse_args()
raw = json.loads(subprocess.check_output([
    "xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", str(args.result)
]))
rows = []
for test in raw:
    for run in test["testRuns"]:
        for metric in run["metrics"]:
            samples = metric["measurements"]
            if not samples:
                continue
            ordered = sorted(samples)
            rows.append({
                "test": test["testIdentifier"], "device": run["device"],
                "metric": metric["displayName"], "unit": metric["unitOfMeasurement"],
                "count": len(samples), "mean": statistics.mean(samples),
                "p50": statistics.median(samples),
                "p95": ordered[math.ceil(len(samples) * .95) - 1],
                "max": max(samples), "samples": samples,
            })
report = {
    "result": str(args.result.resolve()),
    "interpretation": "XCTest wall clock includes automation IPC and idle waits; not tap-to-first-frame latency. p95 uses nearest rank; small samples have limited precision.",
    "metrics": rows,
}
with args.output.open("x") as destination:
    json.dump(report, destination, ensure_ascii=False, indent=2)
for row in rows:
    print(f"{row['test']} | {row['metric']} | n={row['count']} | "
          f"p50={row['p50']:.4f} p95={row['p95']:.4f} {row['unit']}")
