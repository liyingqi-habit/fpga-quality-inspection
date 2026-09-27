"""Check actual PDS 2025.2 XML reports; success is scoped to constrained paths."""
import argparse
import copy
import json
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path


def rows(path):
    root = ET.parse(path).getroot()
    return [[d.text or "" for d in row.findall("data")]
            for row in root.findall("./table/row")]


def verify(timing, issues):
    for corner in ("slow", "fast"):
        for kind in ("setup", "hold", "recovery", "removal", "mpw"):
            key = f"{corner}_{kind}"
            if key not in timing or not timing[key]:
                raise ValueError(f"MISSING:{key}")
            for row in timing[key]:
                if not all(math.isfinite(row[x]) for x in ("slack", "total_slack")):
                    raise ValueError(f"NONFINITE:{key}")
                if row["slack"] < 0 or row["total_slack"] != 0 or row["failing"] != 0:
                    raise ValueError(f"VIOLATION:{key}")
                if row["endpoints"] <= 0:
                    raise ValueError(f"EMPTY:{key}")
    for key in ("no_clock", "loops", "latch_loops", "latchs"):
        if issues.get(key) != 0:
            raise ValueError(f"UNSAFE:{key}")


def inspect(stage):
    tasks = stage / "prj_tasks"
    db = tasks / "pnr_1/report_timing/report_db"
    clocks = rows(db / "report_timing_clock_summary.db")
    if len(clocks) != 1 or clocks[0][0] != "sys_clk" or abs(float(clocks[0][2])-37.037) > 0.0001:
        raise ValueError("CLOCK_PROFILE_CHANGED")
    timing = {}
    for corner in ("slow", "fast"):
        for kind in ("setup", "hold", "recovery", "removal", "mpw"):
            key = f"{corner}_{kind}"
            data = rows(db / f"report_timing_{key}.db")
            offset = 1 if kind == "mpw" else 2
            timing[key] = [dict(slack=float(r[offset]), total_slack=float(r[offset+1]),
                                failing=int(r[offset+2]), endpoints=int(r[offset+3])) for r in data]
    issues = {r[0]: int(r[1]) for r in rows(db / "check_timing_summary.db")}
    verify(timing, issues)
    synthesis = (tasks / "syn_1/synthesize/run.log").read_text(encoding="utf-8", errors="replace")
    resources = {}
    for name, pattern in {
        "LUT": r"Total LUTs: (\d+)", "registers": r"Total Registers: (\d+)",
        "latches": r"Total Latches: (\d+)", "DRM36K_equivalent": r"Total DRMs = ([\d.]+)",
        "APM": r"Total APMs = ([\d.]+)",
    }.items():
        match = re.search(pattern, synthesis)
        if not match:
            raise ValueError(f"MISSING_RESOURCE:{name}")
        resources[name] = float(match[1])
    if resources["latches"] != 0 or "has been successfully synthesized" not in synthesis:
        raise ValueError("SYNTHESIS_INCOMPLETE_OR_LATCH")
    console = (stage / "console.log").read_text(encoding="utf-8", errors="replace")
    for action in ("synthesize -ads -selected_syn_tool_opt 2", "dev_map", "pnr", "report_timing"):
        if f"Executing : {action} successfully." not in console:
            raise ValueError(f"INCOMPLETE:{action}")
    return dict(status="CONSTRAINED_PATHS_PASS_WITH_PROFILE_LIMITATIONS",
                board_status="NOT_VALIDATED", period_ns=37.037, timing=timing,
                check_timing_issues=issues, resources=resources,
                tool_fmax=rows(db / "report_timing_fmax.db"),
                note="Legacy candidate pins, asynchronous input exceptions and zero output delays; not board Fmax.")


def self_test(result):
    tests = ["negative_hold", "missing_setup", "failing_endpoint", "no_clock"]
    for test in tests:
        timing, issues = copy.deepcopy(result["timing"]), dict(result["check_timing_issues"])
        if test == "negative_hold":
            timing["fast_hold"][0]["slack"] = -0.001
            expected = "VIOLATION:fast_hold"
        elif test == "missing_setup":
            del timing["slow_setup"]
            expected = "MISSING:slow_setup"
        elif test == "failing_endpoint":
            timing["slow_setup"][0]["failing"] = 1
            expected = "VIOLATION:slow_setup"
        else:
            issues["no_clock"] = 1
            expected = "UNSAFE:no_clock"
        try:
            verify(timing, issues)
        except ValueError as error:
            if str(error) != expected:
                raise
        else:
            raise AssertionError(f"Negative control escaped: {test}")
    return tests


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    result = inspect(args.stage)
    if args.self_test:
        result["negative_controls_rejected"] = self_test(result)
    print(json.dumps(result, indent=2, ensure_ascii=False))
