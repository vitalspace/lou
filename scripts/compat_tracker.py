#!/usr/bin/env python3
"""Regenerate specs/todos/living-tracker.md from the compat suite.

Runs every tests/compat/*.lou against Node with the same normalisation as
tests/compat/run.sh, records the first divergence, and cross-references the
result with the specs in specs/todos/{pendientes,hechos}.

Usage:
    python3 scripts/compat_tracker.py
    python3 scripts/compat_tracker.py --bin ./zig-out/bin/lou
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMPAT = ROOT / "tests/compat"
TODOS = ROOT / "specs/todos"
OUT = TODOS / "living-tracker.md"

ANSI = re.compile("\x1b\\[[0-9;]*m")
TIMING = re.compile(r"(?m)^[^\n]*:\s*[0-9]+(?:\.[0-9]+)?\s*(?:ns|µs|us|ms|s)\s*$")
BT = chr(96)


def normalize(text: str) -> str:
    text = ANSI.sub("", text)
    text = TIMING.sub("", text)

    def collapse(m):
        items = [t.strip() for t in re.findall(r"[^,\s][^,]*[^,\s]|[^,\s]", m.group(1))]
        return "[" + ",".join(items) + "]"

    text = re.sub(r"\[\s*\n([^\]]*?)\n\s*\]", collapse, text, flags=re.S)
    text = re.sub(r",\s+", ",", text)
    text = re.sub(r"\[\s+", "[", text)
    text = re.sub(r"\s+\]", "]", text)
    return text


def run(cmd: list[str]) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=30, errors="replace")
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, str(exc)
    return p.returncode, p.stdout + p.stderr


def status_of(md: str) -> str:
    m = re.search(r"^## status\s*\n(.*?)(?=^## |\Z)", md, re.S | re.M)
    if not m:
        return "?"
    for line in m.group(1).splitlines():
        line = line.replace("**", "").strip()
        if line:
            return line
    return "?"


def short(s: str, n: int = 70) -> str:
    s = s.replace("|", "\\|")
    return s if len(s) <= n else s[: n - 1] + "…"


def cell(s: str) -> str:
    return BT + s.replace(BT, "") + BT if s else ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bin", type=Path, default=ROOT / "zig-out/bin/lou")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    if not args.bin.exists():
        print(f"missing Lou binary: {args.bin}", file=sys.stderr)
        return 1

    rows = []
    for lou in sorted(COMPAT.glob("*.lou")):
        js = lou.with_suffix(".js")
        name = lou.stem
        if not js.exists():
            rows.append({"name": name, "status": "SKIP"})
            continue
        lou_code, lou_text = run([str(args.bin), "run", str(lou)])
        js_code, js_text = run(["node", str(js)])
        la = normalize(lou_text).splitlines()
        lb = normalize(js_text).splitlines()
        same = la == lb and lou_code == js_code
        first = 0
        while first < min(len(la), len(lb)) and la[first] == lb[first]:
            first += 1
        rows.append({
            "name": name,
            "status": "PASS" if same else "FAIL",
            "lou_code": lou_code,
            "js_code": js_code,
            "line": first + 1,
            "lou": la[first] if first < len(la) else "<EOF>",
            "node": lb[first] if first < len(lb) else "<EOF>",
            "lou_lines": len(la),
            "js_lines": len(lb),
        })

    other = [r for r in rows if r["status"] == "SKIP"]
    passing = [r for r in rows if r["status"] == "PASS"]
    failing = [r for r in rows if r["status"] == "FAIL"]
    results = {r["name"]: r["status"] for r in rows}

    specs = []
    for folder in ("pendientes", "hechos", "completadas"):
        for path in sorted((TODOS / folder).glob("*.md")):
            md = path.read_text()
            refs = sorted(set(re.findall(r"tests/compat/([A-Za-z0-9_.-]+)\.lou", md)))
            specs.append({
                "folder": folder,
                "name": path.name,
                "status": status_of(md),
                "refs": refs,
            })

    def spec_result(refs: list[str]) -> str:
        known = [r for r in refs if r in results]
        if not known:
            return "sin test"
        bad = [r for r in known if results[r] == "FAIL"]
        if bad:
            return "FAIL (" + ", ".join(bad) + ")"
        return "PASS"

    git = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                         capture_output=True, text=True)
    commit = git.stdout.strip() or "?"

    lines = [
        "# Living Tracker — Compat Specs (Auto-Generated)",
        "",
        "## status",
        "",
        "Generado por " + BT + "scripts/compat_tracker.py" + BT + "; no editar a mano.",
        "",
        "| Metrica | Valor |",
        "|---|---|",
        "| Snapshot | " + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + " |",
        "| Commit | " + BT + commit + BT + " |",
        "| Binario | " + BT + str(args.bin.relative_to(ROOT)) + BT + " |",
        "| Fixtures | " + str(len(rows)) + " |",
        "| PASS | " + str(len(passing)) + " |",
        "| FAIL | " + str(len(failing)) + " |",
        "| SKIP | " + str(len(other)) + " |",
        "",
        "## Section 1 — Headline Counts",
        "",
        "| Estado | Count |",
        "|---|---|",
        "| Test files total | " + str(len(rows)) + " |",
        "| **PASS** | " + str(len(passing)) + " |",
        "| **FAIL** | " + str(len(failing)) + " |",
        "| SKIP (sin .js) | " + str(len(other)) + " |",
        "| Specs pendientes | " + str(len([s for s in specs if s["folder"] == "pendientes"])) + " |",
        "| Specs hechos | " + str(len([s for s in specs if s["folder"] == "hechos"])) + " |",
        "",
        "## Section 2 — Failing Tests (first divergence)",
        "",
    ]

    for i, r in enumerate(failing, 1):
        lines += [
            "### " + str(i) + ". " + BT + r["name"] + ".lou" + BT + " - FAIL",
            "",
            "- exit: Lou " + str(r["lou_code"]) + " / Node " + str(r["js_code"]),
            "- Primera divergencia (línea " + str(r["line"]) + ", " + str(r["lou_lines"]) + " vs "
            + str(r["js_lines"]) + " líneas):",
            "  - Lou : " + cell(r["lou"]),
            "  - Node: " + cell(r["node"]),
            "",
        ]

    lines += [
        "## Section 3 — Specs pendientes",
        "",
        "| Spec | Estado declarado | Test | Resultado |",
        "|---|---|---|---|",
    ]
    for s in specs:
        if s["folder"] != "pendientes":
            continue
        refs = ", ".join(cell(r) for r in s["refs"][:3]) or "—"
        lines.append("| " + cell(s["name"]) + " | " + short(s["status"]) + " | " + refs + " | "
                     + spec_result(s["refs"]) + " |")

    drift = [s for s in specs if s["folder"] == "hechos" and spec_result(s["refs"]).startswith("FAIL")]
    lines += [
        "",
        "## Section 4 — Drift: specs en " + BT + "hechos/" + BT + " cuyo test sigue FAIL",
        "",
    ]
    if drift:
        lines += ["| Spec | Estado declarado | Test | Resultado |", "|---|---|---|---|"]
        for s in drift:
            refs = ", ".join(cell(r) for r in s["refs"][:3]) or "—"
            lines.append("| " + cell(s["name"]) + " | " + short(s["status"]) + " | " + refs + " | "
                         + spec_result(s["refs"]) + " |")
    else:
        lines.append("Ninguno.")

    lines += [
        "",
        "## Section 5 — How To Regenerate",
        "",
        BT * 3 + "bash",
        "zig build release",
        "python3 scripts/compat_tracker.py",
        "bash tests/compat/run.sh   # vista rápida PASS/FAIL",
        BT * 3,
        "",
    ]

    args.out.write_text("\n".join(lines))
    print("PASS=" + str(len(passing)) + "  FAIL=" + str(len(failing)) + "  SKIP=" + str(len(other)))
    print("report: " + str(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
