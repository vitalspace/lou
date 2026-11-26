#!/usr/bin/env python3
"""Benchmark every tests/compat fixture and report where Lou loses.

Each fixture is run through the profiler with Lou, Node and Bun, then the
medians are aggregated into a markdown report (report.md), a machine readable
report.json and, when matplotlib is available, a ratio chart.

Usage:
    ./bench.sh compat --runs 20
    python3 scripts/bench_compat.py --runs 20 --out bench-results/compat-run
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROFILER = ROOT / "profiler" / "zig-out" / "bin" / "profiler"
LOU = ROOT / "zig-out" / "bin" / "lou"

NOISE = 1.05  # below this a "loss" is measurement noise, not a real regression
NAMES = ("Lou", "Node", "Bun")


def fmt_dur(ns: float) -> str:
    if ns >= 1e9:
        return f"{ns / 1e9:.2f} s"
    if ns >= 1e6:
        return f"{ns / 1e6:.2f} ms"
    return f"{ns / 1e3:.0f} us"


def fmt_ratio(r: float) -> str:
    return f"{r:.2f}x"


def median_wall(samples: list[dict]) -> int | None:
    vals = [s["wall_ns"] for s in samples if s.get("exit_code") == 0]
    return int(statistics.median(vals)) if vals else None


def cpu_ns(runtime: dict) -> int:
    return int(runtime.get("user_cpu_ns") or 0) + int(runtime.get("kernel_cpu_ns") or 0)


def run_profiler(fixture: Path, out_json: Path, runs: int, lou: Path, timeout: int) -> dict:
    cmd = [
        str(PROFILER),
        "--runs", str(runs),
        "--save", str(out_json),
        "--run", f"Lou:{lou} run",
        "--run", "Node:node",
        "--run", "Bun:bun",
        str(fixture),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-5:]
        raise RuntimeError("\n".join(tail) or f"profiler exited {proc.returncode}")
    return json.loads(out_json.read_text())


def collect(fixture: Path, data: dict) -> dict:
    row = {"fixture": fixture, "runtimes": {}, "broken": [], "profiler": data}
    for runtime in data.get("results", []):
        name = runtime["name"]
        wall = median_wall(runtime.get("samples") or [])
        if wall is None:
            wall = int(runtime["wall_time_ns"])
        # With more than one run the top-level exit_code stays 0; the real codes
        # live in the samples, so surface the first failed one.
        failed_codes = [c for c in (s.get("exit_code") or 0 for s in (runtime.get("samples") or [])) if c]
        exit_code = failed_codes[0] if failed_codes else int(runtime.get("exit_code") or 0)
        row["runtimes"][name] = {
            "wall_ns": wall,
            "cpu_ns": cpu_ns(runtime),
            "rss_bytes": int(runtime.get("rss_bytes") or 0),
            "exit_code": exit_code,
            "samples": len(runtime.get("samples") or []),
        }
        if exit_code:
            row["broken"].append(name)
    return row


def load_compat_fails(path: Path | None) -> set[str]:
    if not path:
        return set()
    text = path.read_text()
    fails = set()
    for line in text.splitlines():
        parts = line.split()
        if len(parts) > 1 and parts[0] == "FAIL":
            fails.add(parts[1].removesuffix(".lou").removesuffix(".js"))
    return fails


def summarise(rows: list[dict], fails: set[str]) -> dict:
    valid = [r for r in rows if not r["broken"] and "Lou" in r["runtimes"]]
    losses, ties = [], []
    for row in valid:
        lou = row["runtimes"]["Lou"]["wall_ns"]
        rivals = {n: d["wall_ns"] for n, d in row["runtimes"].items() if n != "Lou"}
        if not rivals:
            continue
        best_name = min(rivals, key=rivals.get)
        best = rivals[best_name]
        row["best_name"] = best_name
        row["best_ns"] = best
        row["ratio"] = lou / best if best else 0.0
        row["status"] = "gap" if row["fixture"].stem in fails else "ok"
        if row["ratio"] > 1.0:
            losses.append(row)
        if row["ratio"] > 0.9:
            ties.append(row)
    losses.sort(key=lambda r: r["ratio"], reverse=True)
    ties.sort(key=lambda r: r["ratio"], reverse=True)
    present = [n for n in NAMES if any(n in r["runtimes"] for r in valid)]
    total = {n: sum(r["runtimes"][n]["wall_ns"] for r in valid) for n in present}
    peak = {n: max((r["runtimes"][n]["rss_bytes"] for r in valid), default=0) for n in present}
    per = {n: int(statistics.median([r["runtimes"][n]["wall_ns"] for r in valid])) for n in present}
    gaps = [r for r in valid if r.get("status") == "gap"]
    worst = max(valid, key=lambda r: r.get("ratio", 0.0)) if valid else None
    return {
        "valid": valid,
        "losses": losses,
        "ties": ties,
        "gaps": gaps,
        "worst": worst,
        "total": total,
        "peak": peak,
        "per_fixture": per,
    }


def write_chart(rows: list[dict], path: Path) -> bool:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return False

    shown = [r for r in rows if r.get("ratio", 0) > 0.9]
    if shown:
        title = "Where Lou is not the fastest (compat fixtures)"
    else:
        # Every fixture is a win: show the closest races so the chart still says
        # something useful.
        shown = sorted([r for r in rows if r.get("ratio")], key=lambda r: r["ratio"], reverse=True)[:20]
        title = "Closest races (Lou wins every fixture)"
    shown.sort(key=lambda r: r["ratio"])
    if not shown:
        return False
    height = max(4.0, 0.26 * len(shown) + 1.4)
    fig, ax = plt.subplots(figsize=(10, height))
    labels = [r["fixture"].stem for r in shown]
    ratios = [r["ratio"] for r in shown]
    colors = ["#d64545" if r > 1.0 else "#3f8f5f" for r in ratios]
    ax.barh(labels, ratios, color=colors)
    ax.axvline(1.0, color="#888888", linewidth=1, linestyle="--")
    ax.set_xscale("log")
    ax.set_xlabel("Lou wall time / fastest rival (log scale, 1.0 = tie)")
    ax.set_title(title)
    for i, row in enumerate(shown):
        text = f"  {row['ratio']:.2f}x  {fmt_dur(row['runtimes']['Lou']['wall_ns'])}"
        ax.text(row["ratio"], i, text, va="center", fontsize=7)
    ax.grid(axis="x", alpha=0.25)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return True


def write_report(out: Path, meta: dict, rows: list[dict], fails: set[str]) -> dict:
    stats = summarise(rows, fails)
    valid, losses, ties = stats["valid"], stats["losses"], stats["ties"]
    broken = [r for r in rows if r["broken"]]

    def cell(row: dict, name: str) -> str:
        rt = row["runtimes"].get(name)
        return fmt_dur(rt["wall_ns"]) if rt else "-"

    lines = [
        "# Compat benchmark - Lou vs Node vs Bun",
        "",
        f"**Fecha:** {meta['date']}  ",
        f"**Fixtures:** {len(rows)} - **Runs por fixture:** {meta['runs']} (mediana) - "
        f"**Duracion:** {meta['elapsed']:.1f} s",
        "",
        "Cada fixture corre con el profiler para los tres runtimes sobre el .js",
        "original (el .lou es una copia con la misma logica). Ojo: la suite de",
        "compatibilidad ejecuta el .lou, asi que un par de fixtures pueden",
        "comportarse distinto aqui (p. ej. destructuring-assign).",
        "",
        "## Resumen",
        "",
    ]
    header = "| Metrica | " + " | ".join(NAMES) + " |"
    sep = "| --- | " + " | ".join(["---:"] * len(NAMES)) + " |"
    lines += [header, sep]
    lines.append("| Tiempo total (suma de medianas) | " + " | ".join(fmt_dur(stats["total"][n]) for n in NAMES) + " |")
    lines.append("| Mediana por fixture | " + " | ".join(fmt_dur(stats["per_fixture"][n]) for n in NAMES) + " |")
    lines.append("| Pico de RSS | " + " | ".join(f"{stats['peak'][n] / 1e6:.1f} MB" for n in NAMES) + " |")
    lines += [
        "",
        f"- Lou es el mas rapido en **{len(valid) - len(losses)}** de **{len(valid)}** fixtures que "
        f"ejecuta sin error; pierde en **{len(losses)}**.",
    ]
    if broken:
        lou_broken = [r for r in broken if "Lou" in r["broken"]]
        lines.append(
            f"- **{len(lou_broken)}** fixtures no las puede ejecutar Lou (exit != 0): ver abajo."
        )
    gaps = stats["gaps"]
    if gaps:
        lines.append(
            f"- De las que ejecuta, **{len(gaps)}** dan una salida distinta a Node (marcadas gap): el "
            "tiempo es real, pero el resultado todavia no es correcto."
        )
    if stats["worst"] is not None:
        worst = stats["worst"]
        lines.append(
            f"- Peor caso de Lou: **{worst['fixture'].stem}** a {fmt_ratio(worst['ratio'])} del rival "
            f"mas rapido ({fmt_dur(worst['runtimes']['Lou']['wall_ns'])})."
        )
    lines += [
        "",
        f"> Un ratio por debajo de {NOISE:.2f}x esta dentro del ruido de medicion.",
        "",
        "## Donde Lou pierde",
        "",
    ]
    if losses:
        lines += [
            "| # | Fixture | Lou | Node | Bun | Mejor rival | Ratio | Delta | Compat |",
            "| ---: | --- | ---: | ---: | ---: | --- | ---: | ---: | --- |",
        ]
        for i, row in enumerate(losses, 1):
            delta = row["runtimes"]["Lou"]["wall_ns"] - row["best_ns"]
            flag = "gap" if row["status"] == "gap" else ""
            lines.append(
                f"| {i} | {row['fixture'].stem} | {cell(row, 'Lou')} | {cell(row, 'Node')} | "
                f"{cell(row, 'Bun')} | {row['best_name']} | {fmt_ratio(row['ratio'])} | "
                f"+{fmt_dur(delta)} | {flag} |"
            )
    else:
        lines.append("Ninguna: Lou es el runtime mas rapido en todas las fixtures.")
    lines.append("")

    near = [r for r in ties if r["ratio"] <= 1.0]
    if near:
        lines += [
            "## Casi empates (victorias ajustadas)",
            "",
            "| Fixture | Lou | Mejor rival | Ratio |",
            "| --- | ---: | --- | ---: |",
        ]
        for row in near[:15]:
            lines.append(f"| {row['fixture'].stem} | {cell(row, 'Lou')} | {row['best_name']} | {fmt_ratio(row['ratio'])} |")
        lines.append("")

    if broken:
        lines += [
            "## Fixtures rotos (exit != 0)",
            "",
            "| Fixture | Lou | Node | Bun | Exit Lou/Node/Bun | Nota |",
            "| --- | ---: | ---: | ---: | --- | --- |",
        ]
        for row in broken:
            codes = "/".join(str(row["runtimes"].get(n, {}).get("exit_code", "-")) for n in NAMES)
            note = "crash (SIGABRT)" if row["runtimes"].get("Lou", {}).get("exit_code") == 134 else ""
            lines.append(
                f"| {row['fixture'].stem} | {cell(row, 'Lou')} | {cell(row, 'Node')} | {cell(row, 'Bun')} | "
                f"{codes} | {note} |"
            )
        lines.append("")

    report_json = {
        "meta": meta,
        "summary": {
            "fixtures": len(rows),
            "valid": len(valid),
            "losses": len(losses),
            "broken": len(broken),
            "total_wall_ns": {k: int(v) for k, v in stats["total"].items()},
            "median_fixture_ns": stats["per_fixture"],
            "peak_rss_bytes": stats["peak"],
        },
        "fixtures": [
            {
                "fixture": r["fixture"].stem,
                "status": r.get("status", "broken"),
                "best": r.get("best_name"),
                "ratio": round(r.get("ratio", 0.0), 4),
                "runtimes": r["runtimes"],
                "broken": r["broken"],
            }
            for r in rows
        ],
    }
    (out / "report.json").write_text(json.dumps(report_json, indent=2) + "\n")
    (out / "report.md").write_text("\n".join(lines) + "\n")
    return stats


def reload_run(out: Path, fixtures: list[Path]) -> list[dict]:
    """Rebuild the row list from an existing run directory (raw/*.json)."""
    rows = []
    for fixture in fixtures:
        path = out / "raw" / f"{fixture.stem}.json"
        if not path.exists():
            continue
        rows.append(collect(fixture, json.loads(path.read_text())))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="Benchmark tests/compat and report Lou losses")
    ap.add_argument("--fixtures", type=Path, default=ROOT / "tests" / "compat")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--runs", type=int, default=20)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--lou", type=Path, default=LOU)
    ap.add_argument("--compat-fails", type=Path, default=None)
    ap.add_argument("--only", action="append", default=[], help="substring filter (repeatable)")
    ap.add_argument("--no-chart", action="store_true")
    ap.add_argument("--report-only", type=Path, default=None, metavar="DIR",
                    help="rebuild report.md and ratios.png from an existing run directory")
    args = ap.parse_args()

    fixtures = sorted(args.fixtures.glob("*.js"))
    if args.only:
        fixtures = [f for f in fixtures if any(o in f.name for o in args.only)]
    if not fixtures:
        print("no fixtures found", file=sys.stderr)
        return 1
    fails = load_compat_fails(args.compat_fails)

    if args.report_only:
        out = args.report_only
        rows = reload_run(out, fixtures)
        if not rows:
            print(f"no raw results under {out / 'raw'}", file=sys.stderr)
            return 1
        meta = {
            "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "runs": 0,
            "elapsed": 0.0,
            "fixtures": len(rows),
            "command": f"./bench.sh compat",
        }
        previous = out / "report.json"
        if previous.exists():
            meta.update(json.loads(previous.read_text()).get("meta", {}))
        stats = write_report(out, meta, rows, fails)
        if not args.no_chart:
            write_chart(rows, out / "ratios.png")
        print(f"{len(stats['losses'])} losses of {len(stats['valid'])} valid fixtures", file=sys.stderr)
        print(f"report: {out / 'report.md'}", file=sys.stderr)
        return 0

    if not PROFILER.exists():
        print(f"missing profiler: {PROFILER}", file=sys.stderr)
        return 1
    if not args.lou.exists():
        print(f"missing Lou binary: {args.lou}", file=sys.stderr)
        return 1

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = args.out or ROOT / "bench-results" / f"compat-{stamp}"
    raw = out / "raw"
    raw.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []
    started = time.monotonic()
    for i, fixture in enumerate(fixtures, 1):
        try:
            data = run_profiler(fixture, raw / f"{fixture.stem}.json", args.runs, args.lou, args.timeout)
            row = collect(fixture, data)
            lou = row["runtimes"].get("Lou", {}).get("wall_ns")
            best = min((d["wall_ns"] for n, d in row["runtimes"].items() if n != "Lou"), default=None)
            extra = ""
            if lou and best:
                extra = f" lou={fmt_dur(lou)} best={fmt_dur(best)} ({lou / best:.2f}x)"
            status = "BROKEN" if row["broken"] else "ok"
            print(f"[{i:3}/{len(fixtures)}] {fixture.stem}: {status}{extra}", file=sys.stderr)
        except Exception as exc:  # a broken fixture must not stop the sweep
            print(f"[{i:3}/{len(fixtures)}] {fixture.stem}: ERROR {exc}", file=sys.stderr)
            row = {"fixture": fixture, "runtimes": {}, "broken": ["profiler"], "profiler": {"results": []}}
        rows.append(row)

    elapsed = time.monotonic() - started
    meta = {
        "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "runs": args.runs,
        "elapsed": round(elapsed, 1),
        "fixtures": len(fixtures),
        "command": f"./bench.sh compat --runs {args.runs}",
    }
    stats = write_report(out, meta, rows, fails)
    if not args.no_chart:
        chart = out / "ratios.png"
        if write_chart(rows, chart):
            print(f"chart:  {chart}", file=sys.stderr)

    losses = stats["losses"]
    print(f"\n{len(losses)} losses of {len(stats['valid'])} valid fixtures", file=sys.stderr)
    for row in losses[:10]:
        print(f"  {row['fixture'].stem:40} {row['ratio']:.2f}x  {fmt_dur(row['runtimes']['Lou']['wall_ns'])}", file=sys.stderr)
    print(f"report: {out / 'report.md'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
