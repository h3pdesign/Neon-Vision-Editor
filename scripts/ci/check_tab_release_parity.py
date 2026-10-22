#!/usr/bin/env python3
"""Fail closed when complete native-tab benchmark runs regress from a release.

Usage: check_tab_release_parity.py RELEASE_LOG... --native NATIVE_LOG...
Run both builds on the same machine/toolchain with identical fixtures/settings.
This compares recorded workloads, not universal or physical-device performance.
"""
import argparse
import json
import math
import pathlib
import statistics

PREFIX = "TAB_RELEASE_PARITY "
FILES = ("Small.swift", "Unicode.json", "Large.md", "Large.swift")
METRICS = {"startup_editor_draw_ms", "warm_switch_ms", "close_dispatch_ms",
           "retained_editor_resident_growth_bytes", "batch_12_all_loaded_ms"} | {
    f"{operation}_{name}_ms" for name in FILES
    for operation in ("open", "typing", "resize", "scroll", "save")
}
MIN_SAMPLES = {metric: 8 if metric.startswith("typing_") else
               3 if metric.startswith("resize_") else
               4 if metric.startswith("scroll_") or metric == "close_dispatch_ms" else
               11 if metric == "warm_switch_ms" else 1 for metric in METRICS}


def read_runs(paths, variant, minimum_runs=3):
    if len(paths) < minimum_runs:
        raise ValueError(f"{variant}: requires at least {minimum_runs} complete runs")
    combined = {}
    for path in paths:
        text = pathlib.Path(path).read_text()
        if text.count("TAB_RELEASE_PARITY_COMPLETE") != 1 or "TAB_RELEASE_PARITY_ERROR" in text or "TAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE" in text:
            raise ValueError(f"{path}: incomplete or failed run")
        run = {}
        modes = set()
        for line in text.splitlines():
            if not line.startswith(PREFIX):
                continue
            record = json.loads(line[len(PREFIX):])
            if record.get("evidence_version") != 2:
                raise ValueError(f"{path}: missing toolbar-qualified first-draw evidence")
            if record["variant"] != variant:
                raise ValueError(f"{path}: wrong benchmark variant")
            modes.add(record["preview"])
            samples = record["samples"]
            if not samples or any(type(x) not in (int, float) or not math.isfinite(x) or x < 0 for x in samples):
                raise ValueError(f"{path}: invalid samples")
            run.setdefault(record["metric"], []).extend(samples)
        if set(run) != METRICS or len(modes) != 1:
            raise ValueError(f"{path}: missing metrics or inconsistent preview mode")
        if any(len(run[metric]) < count for metric, count in MIN_SAMPLES.items()):
            raise ValueError(f"{path}: incomplete workload sample counts")
        mode = modes.pop()
        if mode not in ("preview", "edit", "read"):
            raise ValueError(f"{path}: unknown preview mode")
        for metric, samples in run.items():
            combined.setdefault((mode, metric), []).extend(samples)
    if len({mode for mode, _ in combined}) != 1:
        raise ValueError("Compare each preview mode separately with complete repeated runs")
    return combined


def summarize(samples):
    ordered = sorted(samples)
    return statistics.median(ordered), ordered[math.ceil(len(ordered) * 0.95) - 1]


def compare(release, native):
    if release.keys() != native.keys():
        raise ValueError("Release and native workloads/settings do not match")
    rows = []
    for key in sorted(release):
        baseline = summarize(release[key])
        candidate = summarize(native[key])
        rows.append({"preview": key[0], "metric": key[1],
                     "release_median": baseline[0], "native_median": candidate[0],
                     "release_p95": baseline[1], "native_p95": candidate[1],
                     "regressed": any(new > old for old, new in zip(baseline, candidate))})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", nargs="+")
    parser.add_argument("--native", nargs="+", required=True)
    args = parser.parse_args()
    try:
        rows = compare(read_runs(args.release, "release"), read_runs(args.native, "native"))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"Invalid parity evidence: {error}\n")
    print(json.dumps({"passed": not any(row["regressed"] for row in rows), "metrics": rows}, indent=2))
    return int(any(row["regressed"] for row in rows))


if __name__ == "__main__":
    raise SystemExit(main())
