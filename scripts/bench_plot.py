#!/usr/bin/env python3
"""Turn profiler JSON results into charts and a self-contained HTML report.

Reads the JSON written by the Zig profiler (--save). Every chart is a PNG
written to the output directory; an index.html bundles them with a summary
table so the whole run can be reviewed or committed.

Examples:
    scripts/bench_plot.py results.json
    scripts/bench_plot.py bench-results/*.json -o bench-results/latest
    scripts/bench_plot.py results.json --open
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import socket
import sys
import webbrowser
from dataclasses import dataclass, field
from pathlib import Path

try:
    import matplotlib
except ImportError:
    sys.stderr.write(
        "bench_plot: matplotlib is required to draw charts.\n"
        "  pip install --user matplotlib\n"
        "  Arch:    sudo pacman -S python-matplotlib\n"
        "  Debian:  sudo apt install python3-matplotlib\n"
    )
    raise SystemExit(1)

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402

# --- theme ---------------------------------------------------------------

BG = "#0e1116"
PANEL = "#151a21"
FG = "#e7ecf3"
MUTED = "#8b95a7"
GRID = "#242b36"
ACCENT = "#5eead4"
USER_CPU = "#60a5fa"
KERNEL_CPU = "#f472b6"

KNOWN_COLORS = {
    "lou": "#5eead4",
    "node": "#6cc24a",
    "bun": "#f472b6",
    "deno": "#93c5fd",
    "quickjs": "#fbbf24",
    "d8": "#a78bfa",
    "browser": "#38bdf8",
}
FALLBACK_COLORS = [
    "#5eead4", "#6cc24a", "#f472b6", "#fbbf24",
    "#a78bfa", "#38bdf8", "#f87171", "#34d399",
]


# --- formatting ----------------------------------------------------------

def _decimals(value: float) -> int:
    value = abs(value)
    if value >= 100:
        return 0
    if value >= 10:
        return 1
    return 2


def fmt_time(ns: float | None) -> str:
    if ns is None:
        return "-"
    ns = float(ns)
    if ns <= 0:
        return "0"
    if ns < 1_000:
        return f"{ns:.0f} ns"
    if ns < 1_000_000:
        return f"{ns / 1e3:.{_decimals(ns / 1e3)}f} us"
    if ns < 1_000_000_000:
        v = ns / 1e6
        return f"{v:.{_decimals(v)}f} ms"
    v = ns / 1e9
    return f"{v:.{_decimals(v)}f} s"


def fmt_bytes(n: float | None) -> str:
    if n is None:
        return "-"
    n = float(n)
    if n <= 0:
        return "0 B"
    for unit, scale in (("GB", 1024 ** 3), ("MB", 1024 ** 2), ("KB", 1024)):
        if n >= scale:
            v = n / scale
            return f"{v:.{_decimals(v)}f} {unit}"
    return f"{n:.0f} B"


def fmt_count(n: float | None) -> str:
    if n is None:
        return "-"
    n = float(n)
    if n >= 1_000_000:
        return f"{n / 1e6:.1f}M"
    if n >= 10_000:
        return f"{n / 1e3:.1f}k"
    return f"{n:,.0f}"


def human_time_formatter():
    return FuncFormatter(lambda v, _pos: fmt_time(v))


# --- model ---------------------------------------------------------------

@dataclass
class Run:
    name: str
    wall_ns: float
    cpu_ns: float
    user_ns: float
    kernel_ns: float
    rss_bytes: float
    median_rss: float
    min_rss: float
    max_rss: float
    min_wall: float
    max_wall: float
    stddev_wall: float
    faults: float
    minor_faults: float
    major_faults: float
    ctx: float
    vol_ctx: float
    invol_ctx: float
    runs: int
    samples: list = field(default_factory=list)
    perf: dict = field(default_factory=dict)

    @property
    def cpu_pct(self) -> float:
        if self.wall_ns <= 0:
            return 0.0
        return 100.0 * self.cpu_ns / self.wall_ns

    @property
    def sample_wall_ms(self) -> list:
        return [s.get("wall_ns", 0) / 1e6 for s in self.samples if s.get("wall_ns")]

    @property
    def mem_ratio(self) -> float:
        if self.median_rss <= 0:
            return 0.0
        return self.max_rss / self.median_rss


@dataclass
class Report:
    path: Path
    file: str
    mode: str
    winner: str
    speedup: float
    runs: list
    mtime: dt.datetime

    @property
    def label(self) -> str:
        return f"{self.file} ({self.mode})"


def _stat(stats: dict, key: str, fallback: float) -> float:
    value = stats.get(key)
    return float(value) if isinstance(value, (int, float)) else float(fallback)


def load_report(path: Path) -> Report:
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)

    runs = []
    for entry in data.get("results", []):
        stats = entry.get("stats") or {}
        wall = float(entry.get("wall_time_ns") or 0)
        cpu = float(entry.get("cpu_ns") or 0)
        user = float(entry.get("user_cpu_ns") or 0)
        kernel = float(entry.get("kernel_cpu_ns") or 0)
        if user == 0 and kernel == 0 and cpu > 0:
            # Older JSON only exposes the total; split it proportionally.
            user, kernel = 0.0, cpu
        rss = float(entry.get("rss_bytes") or 0)
        runs.append(
            Run(
                name=str(entry.get("name", "?")),
                wall_ns=_stat(stats, "median_wall_ns", wall),
                cpu_ns=_stat(stats, "median_cpu_ns", cpu),
                user_ns=user,
                kernel_ns=kernel,
                rss_bytes=rss,
                median_rss=_stat(stats, "median_rss", rss),
                min_rss=_stat(stats, "min_rss", rss),
                max_rss=_stat(stats, "max_rss", rss),
                min_wall=_stat(stats, "min_wall_ns", wall),
                max_wall=_stat(stats, "max_wall_ns", wall),
                stddev_wall=_stat(stats, "stddev_wall_ns", 0.0),
                faults=float(entry.get("page_faults") or 0),
                minor_faults=float(entry.get("minor_page_faults") or entry.get("page_faults") or 0),
                major_faults=float(entry.get("major_page_faults") or 0),
                ctx=float(entry.get("context_switches") or 0),
                vol_ctx=float(entry.get("vol_ctx_switches") or 0),
                invol_ctx=float(entry.get("invol_ctx_switches") or 0),
                runs=int(stats.get("runs") or 1),
                samples=entry.get("samples") or [],
                perf=entry.get("perf") or {},
            )
        )

    return Report(
        path=path,
        file=str(data.get("file", path.stem)),
        mode=str(data.get("mode", "quick")),
        winner=str(data.get("winner", "")),
        speedup=float(data.get("speedup_factor") or 0.0),
        runs=runs,
        mtime=dt.datetime.fromtimestamp(path.stat().st_mtime),
    )


class Colors:
    def __init__(self, reports: list):
        self.map = {}
        names = []
        for report in reports:
            for run in report.runs:
                if run.name not in names:
                    names.append(run.name)
        for index, name in enumerate(names):
            self.map[name] = KNOWN_COLORS.get(
                name.strip().lower(), FALLBACK_COLORS[index % len(FALLBACK_COLORS)]
            )

    def get(self, name: str) -> str:
        return self.map.get(name, MUTED)


# --- plotting primitives -------------------------------------------------

def new_fig(width: float, height: float):
    fig, ax = plt.subplots(figsize=(width, height))
    fig.patch.set_facecolor(BG)
    return fig, ax


def style_axes(ax, title: str | None = None, ylabel: str | None = None,
               xlabel: str | None = None, grid_axis: str = "y"):
    ax.set_facecolor(PANEL)
    if title:
        ax.set_title(title, color=FG, fontsize=12.5, fontweight="bold",
                     loc="left", pad=10)
    if ylabel:
        ax.set_ylabel(ylabel, color=MUTED, fontsize=10, labelpad=8)
    if xlabel:
        ax.set_xlabel(xlabel, color=MUTED, fontsize=10, labelpad=8)
    ax.grid(axis=grid_axis, color=GRID, linewidth=0.8, alpha=0.9)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=MUTED, labelsize=10, length=0)
    return ax


def annotate_bars(ax, xs, values, fmt, offset: int = 6, color: str = FG,
                  ceiling: float | None = None):
    span = max((abs(float(v)) for v in values if v), default=1.0)
    if ceiling is not None and ceiling > span:
        span = ceiling
    for x, value in zip(xs, values):
        label = fmt(value)
        ax.annotate(
            label, (x, value), xytext=(0, offset), textcoords="offset points",
            ha="center", va="bottom", color=color, fontsize=10,
            fontweight="bold",
        )
    ax.set_ylim(0, span * 1.24 if span > 0 else 1)


def bar_panel(ax, names, medians, lows, highs, colors, fmt,
              title=None, ylabel=None, log=False):
    xs = np.arange(len(names))
    bars = ax.bar(xs, medians, width=0.62, color=colors, edgecolor="none", zorder=3)
    if lows is not None and highs is not None:
        lower = np.clip(np.array(medians) - np.array(lows), 0, None)
        upper = np.clip(np.array(highs) - np.array(medians), 0, None)
        ax.errorbar(
            xs, medians, yerr=[lower, upper], fmt="none",
            ecolor=MUTED, elinewidth=1.2, capsize=5, capthick=1.2, zorder=4,
        )
    ax.set_xticks(xs)
    ax.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    for tick, name in zip(ax.get_xticklabels(), names):
        tick.set_color(colors[names.index(name)])
    if log:
        ax.set_yscale("log")
    top = None
    if highs is not None and len(highs):
        top = max(float(v) for v in highs)
    annotate_bars(ax, xs, medians, fmt, ceiling=top)
    style_axes(ax, title, ylabel)
    if not log:
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt(v)))
    else:
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt(v)))
        ax.grid(axis="y", which="both", color=GRID, linewidth=0.6, alpha=0.7)
    return bars


def save(fig, out_dir: Path, name: str, dpi: int) -> Path:
    path = out_dir / name
    fig.savefig(path, dpi=dpi, facecolor=BG, bbox_inches="tight", pad_inches=0.28)
    plt.close(fig)
    return path


def header(fig, title: str, subtitle: str | None = None, top: float = 0.85):
    """Title block above the axes with reserved space, so nothing collides."""
    fig.suptitle(title, color=FG, fontsize=14, fontweight="bold",
                 x=0.02, ha="left", y=0.985)
    if subtitle:
        fig.text(0.02, 0.935, subtitle, color=MUTED, fontsize=9.5,
                 ha="left", va="top")
    fig.subplots_adjust(top=top)


# --- charts --------------------------------------------------------------

def chart_wall(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    names = [r.name for r in runs]
    med = [r.wall_ns for r in runs]
    lows = [min(r.min_wall, r.wall_ns) for r in runs]
    highs = [max(r.max_wall, r.wall_ns) for r in runs]
    fig, ax = new_fig(8.6, 5.0)
    bar_panel(ax, names, med, lows, highs, [colors.get(n) for n in names],
              fmt_time, title="Execution time (wall clock)", ylabel="wall time")
    best = min(med) if med else 0
    if best > 0:
        ax.axhline(best, color=ACCENT, linewidth=1, linestyle=(0, (4, 4)), alpha=0.55, zorder=2)
    header(fig, f"Lou bench - {report.file}  [{report.mode}]",
           "bars are medians, whiskers are min/max across runs")
    return save(fig, out, "01-wall-time.png", dpi)


def chart_cpu(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    names = [r.name for r in runs]
    xs = np.arange(len(names))
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.4, 4.9))
    fig.patch.set_facecolor(BG)

    user = np.array([r.user_ns for r in runs])
    kernel = np.array([r.kernel_ns for r in runs])
    ax1.bar(xs, user, width=0.62, color=USER_CPU, label="user", zorder=3)
    ax1.bar(xs, kernel, width=0.62, bottom=user, color=KERNEL_CPU, label="kernel", zorder=3)
    total = user + kernel
    for x, value in zip(xs, total):
        ax1.annotate(fmt_time(value), (x, value), xytext=(0, 6),
                     textcoords="offset points", ha="center", color=FG,
                     fontsize=10, fontweight="bold")
    ax1.set_ylim(0, max(total.max() if len(total) else 1, 1) * 1.26)
    ax1.set_xticks(xs)
    ax1.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    ax1.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_time(v)))
    style_axes(ax1, "CPU time (median)", "cpu time")
    legend = ax1.legend(loc="upper right", frameon=False, fontsize=9.5)
    for text in legend.get_texts():
        text.set_color(FG)

    pct = [r.cpu_pct for r in runs]
    ax2.bar(xs, pct, width=0.62, color=[colors.get(n) for n in names], zorder=3)
    for x, value in zip(xs, pct):
        ax2.annotate(f"{value:.0f}%", (x, value), xytext=(0, 6),
                     textcoords="offset points", ha="center", color=FG,
                     fontsize=10, fontweight="bold")
    ax2.axhline(100, color=MUTED, linewidth=1, linestyle=(0, (4, 4)), alpha=0.7)
    ax2.set_ylim(0, max(max(pct) if pct else 100, 110) * 1.22)
    ax2.set_xticks(xs)
    ax2.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    ax2.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:.0f}%"))
    style_axes(ax2, "CPU utilisation (cpu / wall)", "share of one core")
    header(fig, f"Lou bench - {report.file}  [{report.mode}]",
           "above 100% means the runtime used more than one core", top=0.79)
    return save(fig, out, "02-cpu-usage.png", dpi)


def chart_memory(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    names = [r.name for r in runs]
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.4, 4.9))
    fig.patch.set_facecolor(BG)

    med = [r.median_rss for r in runs]
    lows = [min(r.min_rss, r.median_rss) for r in runs]
    highs = [max(r.max_rss, r.median_rss) for r in runs]
    bar_panel(ax1, names, med, lows, highs, [colors.get(n) for n in names],
              fmt_bytes, title="Peak memory (RSS)", ylabel="resident set size")
    ax1.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_bytes(v)))

    xs = np.arange(len(names))
    spread = [100.0 * (h - l) / m if m > 0 else 0.0 for h, l, m in zip(highs, lows, med)]
    ax2.bar(xs, spread, width=0.62, color=[colors.get(n) for n in names], zorder=3)
    for x, value in zip(xs, spread):
        ax2.annotate(f"{value:.1f}%", (x, value), xytext=(0, 6),
                     textcoords="offset points", ha="center", color=FG,
                     fontsize=10, fontweight="bold")
    ax2.set_ylim(0, max(max(spread) if spread else 1, 1) * 1.26)
    ax2.set_xticks(xs)
    ax2.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    ax2.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:.1f}%"))
    style_axes(ax2, "Memory spread (max - min) / median", "variation")
    header(fig, f"Lou bench - {report.file}  [{report.mode}]",
           "lower spread means a more predictable footprint", top=0.79)
    return save(fig, out, "03-memory.png", dpi)


def chart_distribution(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    names = [r.name for r in runs]
    with_samples = [r for r in runs if len(r.sample_wall_ms) > 1]
    fig, ax = new_fig(8.8, 5.2)

    if with_samples:
        data = [r.sample_wall_ms for r in with_samples]
        box = ax.boxplot(
            data, widths=0.5, patch_artist=True, showfliers=False,
            medianprops=dict(color=FG, linewidth=1.6),
            whiskerprops=dict(color=MUTED, linewidth=1.1),
            capprops=dict(color=MUTED, linewidth=1.1),
        )
        for patch, run in zip(box["boxes"], with_samples):
            color = colors.get(run.name)
            patch.set_facecolor(color)
            patch.set_alpha(0.30)
            patch.set_edgecolor(color)
            patch.set_linewidth(1.3)
        rng = np.random.default_rng(7)
        for index, run in enumerate(with_samples, start=1):
            values = np.array(run.sample_wall_ms)
            xs = rng.normal(index, 0.055, size=len(values))
            ax.scatter(xs, values, s=13, color=colors.get(run.name),
                       alpha=0.55, linewidths=0, zorder=5)
        ax.set_xticks(range(1, len(with_samples) + 1))
        ax.set_xticklabels([r.name for r in with_samples], color=FG,
                           fontsize=10.5, fontweight="bold")
        note = "box = quartiles, dots = individual runs"
    else:
        xs = np.arange(len(names))
        med = [r.wall_ns / 1e6 for r in runs]
        lower = [max(m - l / 1e6, 0) for m, l in zip(med, [r.min_wall for r in runs])]
        upper = [max(h / 1e6 - m, 0) for m, h in zip(med, [r.max_wall for r in runs])]
        ax.bar(xs, med, width=0.5, color=[colors.get(n) for n in names], zorder=3)
        ax.errorbar(xs, med, yerr=[lower, upper], fmt="none", ecolor=MUTED,
                    elinewidth=1.2, capsize=5, zorder=4)
        ax.set_xticks(xs)
        ax.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
        note = "re-run with --mode deep to get per-run samples"

    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:.2f} ms"))
    style_axes(ax, "Run-to-run distribution of wall time", "wall time")
    ax.text(0.995, 0.02, note, transform=ax.transAxes, color=MUTED,
            fontsize=9, ha="right", va="bottom")
    header(fig, f"Lou bench - {report.file}  [{report.mode}]",
           "spread matters: a fast median with huge variance is not stable")
    return save(fig, out, "04-distribution.png", dpi)


def chart_system(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    names = [r.name for r in runs]
    xs = np.arange(len(names))
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.4, 4.7))
    fig.patch.set_facecolor(BG)

    faults = [r.faults for r in runs]
    ax1.bar(xs, faults, width=0.62, color=[colors.get(n) for n in names], zorder=3)
    for x, value in zip(xs, faults):
        ax1.annotate(fmt_count(value), (x, value), xytext=(0, 6),
                     textcoords="offset points", ha="center", color=FG,
                     fontsize=10, fontweight="bold")
    ax1.set_ylim(0, max(max(faults) if faults else 1, 1) * 1.26)
    ax1.set_xticks(xs)
    ax1.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    ax1.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_count(v)))
    style_axes(ax1, "Page faults (median)", "faults")

    ctx = [r.ctx for r in runs]
    ax2.bar(xs, ctx, width=0.62, color=[colors.get(n) for n in names], zorder=3)
    for x, value in zip(xs, ctx):
        ax2.annotate(fmt_count(value), (x, value), xytext=(0, 6),
                     textcoords="offset points", ha="center", color=FG,
                     fontsize=10, fontweight="bold")
    ax2.set_ylim(0, max(max(ctx) if ctx else 1, 1) * 1.26)
    ax2.set_xticks(xs)
    ax2.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    ax2.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_count(v)))
    style_axes(ax2, "Context switches (median)", "switches")
    header(fig, f"Lou bench - {report.file}  [{report.mode}]",
           "kernel work the runtime causes per execution", top=0.79)
    return save(fig, out, "05-system.png", dpi)


def chart_ratios(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    if not runs:
        raise SystemExit("bench_plot: no results in JSON")
    base = min(runs, key=lambda r: r.wall_ns)
    names = [r.name for r in runs]
    wall_ratio = [r.wall_ns / base.wall_ns if base.wall_ns else 0 for r in runs]
    cpu_ratio = [r.cpu_ns / base.cpu_ns if base.cpu_ns else 0 for r in runs]
    mem_ratio = [r.median_rss / base.median_rss if base.median_rss else 0 for r in runs]

    fig, ax = new_fig(8.8, 5.0)
    xs = np.arange(len(names))
    width = 0.26
    series = [
        ("wall", wall_ratio, "#5eead4"),
        ("cpu", cpu_ratio, "#60a5fa"),
        ("memory", mem_ratio, "#f472b6"),
    ]
    for offset, (label, values, color) in zip((-width, 0.0, width), series):
        positions = xs + offset
        ax.bar(positions, values, width=width, color=color, label=label, zorder=3)
        for x, value in zip(positions, values):
            if value:
                ax.annotate(f"{value:.2f}x", (x, value), xytext=(0, 5),
                            textcoords="offset points", ha="center", color=FG,
                            fontsize=8.6, fontweight="bold")
    ax.axhline(1.0, color=ACCENT, linewidth=1, linestyle=(0, (4, 4)), alpha=0.6)
    ax.set_xticks(xs)
    ax.set_xticklabels(names, color=FG, fontsize=10.5, fontweight="bold")
    top = max(wall_ratio + cpu_ratio + mem_ratio + [1.0])
    ax.set_ylim(0, top * 1.22)
    style_axes(ax, f"Relative to {base.name} (1.00x = fastest)", "multiplier")
    legend = ax.legend(loc="upper left", frameon=False, fontsize=9.5, ncol=3)
    for text in legend.get_texts():
        text.set_color(FG)
    header(fig, f"Lou bench - {report.file}  [{report.mode}]",
           "same numbers as above, normalised to the fastest runtime", top=0.82)
    return save(fig, out, "06-ratios.png", dpi)


def chart_dashboard(report: Report, colors: Colors, out: Path, dpi: int) -> Path:
    runs = report.runs
    names = [r.name for r in runs]
    palette = [colors.get(n) for n in names]
    fig = plt.figure(figsize=(14.5, 8.6))
    fig.patch.set_facecolor(BG)
    grid = fig.add_gridspec(2, 3, hspace=0.42, wspace=0.24, top=0.86)

    ax = fig.add_subplot(grid[0, 0])
    bar_panel(ax, names, [r.wall_ns for r in runs],
              [r.min_wall for r in runs], [r.max_wall for r in runs],
              palette, fmt_time, "Wall time", "time")

    ax = fig.add_subplot(grid[0, 1])
    xs = np.arange(len(names))
    ax.bar(xs, [r.user_ns for r in runs], width=0.62, color=USER_CPU, label="user", zorder=3)
    ax.bar(xs, [r.kernel_ns for r in runs], width=0.62,
           bottom=[r.user_ns for r in runs], color=KERNEL_CPU, label="kernel", zorder=3)
    ax.set_xticks(xs)
    ax.set_xticklabels(names, color=FG, fontsize=10, fontweight="bold")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_time(v)))
    style_axes(ax, "CPU time", "cpu")
    legend = ax.legend(frameon=False, fontsize=8.5, loc="upper right")
    for text in legend.get_texts():
        text.set_color(FG)

    ax = fig.add_subplot(grid[0, 2])
    bar_panel(ax, names, [r.median_rss for r in runs],
              [r.min_rss for r in runs], [r.max_rss for r in runs],
              palette, fmt_bytes, "Peak memory", "rss")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_bytes(v)))

    ax = fig.add_subplot(grid[1, 0])
    if all(len(r.sample_wall_ms) > 1 for r in runs):
        data = [r.sample_wall_ms for r in runs]
        box = ax.boxplot(data, widths=0.5, patch_artist=True, showfliers=False,
                         medianprops=dict(color=FG, linewidth=1.4),
                         whiskerprops=dict(color=MUTED),
                         capprops=dict(color=MUTED))
        for patch, run in zip(box["boxes"], runs):
            patch.set_facecolor(colors.get(run.name))
            patch.set_alpha(0.30)
            patch.set_edgecolor(colors.get(run.name))
        ax.set_xticks(range(1, len(runs) + 1))
    else:
        ax.bar(xs, [r.wall_ns for r in runs], width=0.55, color=palette, zorder=3)
        ax.set_xticks(xs)
    ax.set_xticklabels(names, color=FG, fontsize=10, fontweight="bold")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:.0f} ms" if v > 1 else f"{v:.2f} ms"))
    style_axes(ax, "Run distribution", "wall")

    ax = fig.add_subplot(grid[1, 1])
    ax.bar(xs, [r.faults for r in runs], width=0.6, color=palette, zorder=3)
    ax.set_xticks(xs)
    ax.set_xticklabels(names, color=FG, fontsize=10, fontweight="bold")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: fmt_count(v)))
    style_axes(ax, "Page faults", "faults")

    ax = fig.add_subplot(grid[1, 2])
    ratios = []
    base = min(runs, key=lambda r: r.wall_ns) if runs else None
    labels = []
    for key, tag in ((lambda r: r.wall_ns, "wall"), (lambda r: r.cpu_ns, "cpu"),
                     (lambda r: r.median_rss, "mem")):
        for run in runs:
            b = key(base) if base else 0
            ratios.append(key(run) / b if b else 0)
            labels.append(f"{run.name}\n{tag}")
    ax.bar(range(len(ratios)), ratios, width=0.62, color=palette * 3, zorder=3)
    ax.axhline(1.0, color=ACCENT, linewidth=1, linestyle=(0, (4, 4)), alpha=0.6)
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, color=MUTED, fontsize=7.6)
    style_axes(ax, "Multipliers vs fastest", "x")
    ax.set_ylim(0, max(ratios + [1.0]) * 1.2)

    header(
        fig,
        f"Lou bench - {report.file}   winner: {report.winner or 'n/a'}",
        f"mode {report.mode} - {plural_runs(report)}"
        f" - {report.mtime:%Y-%m-%d %H:%M}",
        top=0.86,
    )
    return save(fig, out, "00-dashboard.png", dpi)


def chart_history(reports: list, colors: Colors, out: Path, dpi: int) -> Path | None:
    # Only compare runs of the same script: mixing workloads would make the
    # trend meaningless. Pick the script with the longest history.
    groups: dict = {}
    for report in reports:
        groups.setdefault(report.file, []).append(report)
    candidates = [
        (len(group), max(r.mtime for r in group), name, group)
        for name, group in groups.items()
        if len(group) >= 2
    ]
    if not candidates:
        return None
    candidates.sort()
    _count, _when, focus, group = candidates[-1]
    ordered = sorted(group, key=lambda r: r.mtime)

    names = []
    for report in ordered:
        for run in report.runs:
            if run.name not in names:
                names.append(run.name)

    fig, axes = plt.subplots(3, 1, figsize=(10.4, 8.0), sharex=True)
    fig.patch.set_facecolor(BG)
    metrics = [
        ("Wall time (median)", lambda r: r.wall_ns, fmt_time, "time"),
        ("CPU time (median)", lambda r: r.cpu_ns, fmt_time, "cpu"),
        ("Peak memory (median RSS)", lambda r: r.median_rss, fmt_bytes, "rss"),
    ]
    for ax, (title, getter, fmt, _tag) in zip(axes, metrics):
        for name in names:
            points = [
                (report.mtime, getter(run))
                for report in ordered
                for run in report.runs
                if run.name == name
            ]
            if not points:
                continue
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            ax.plot(xs, ys, marker="o", markersize=6, linewidth=1.8,
                    color=colors.get(name), label=name, zorder=3)
            for x, y in list(zip(xs, ys))[-1:]:
                ax.annotate(fmt(y), (x, y), xytext=(6, 4),
                            textcoords="offset points", color=FG,
                            fontsize=8.6, fontweight="bold")
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p, f=fmt: f(v)))
        style_axes(ax, title)
    legend = axes[0].legend(frameon=False, fontsize=9.5, loc="upper left", ncol=len(names))
    for text in legend.get_texts():
        text.set_color(FG)
    fig.autofmt_xdate()
    header(fig, f"Lou bench - history of {focus}",
           f"{len(ordered)} saved runs; each point is one result",
           top=0.90)
    return save(fig, out, "07-history.png", dpi)


# --- report table --------------------------------------------------------

def summary_rows(report: Report) -> list:
    if not report.runs:
        return []
    base = min(report.runs, key=lambda r: r.wall_ns)
    rows = []
    for run in sorted(report.runs, key=lambda r: r.wall_ns):
        rows.append({
            "name": run.name,
            "wall": fmt_time(run.wall_ns),
            "range": f"{fmt_time(run.min_wall)} - {fmt_time(run.max_wall)}",
            "wall_ratio": f"{run.wall_ns / base.wall_ns:.2f}x" if base.wall_ns else "-",
            "cpu": fmt_time(run.cpu_ns),
            "split": f"{fmt_time(run.user_ns)} / {fmt_time(run.kernel_ns)}",
            "util": f"{run.cpu_pct:.0f}%",
            "rss": fmt_bytes(run.median_rss),
            "rss_max": fmt_bytes(run.max_rss),
            "faults": fmt_count(run.faults),
            "ctx": fmt_count(run.ctx),
            "runs": str(run.runs),
            "fastest": run is base,
        })
    return rows


def plural_runs(report: Report) -> str:
    count = report.runs[0].runs if report.runs else 1
    return f"{count} run per runtime" if count == 1 else f"{count} runs per runtime"


def print_summary(report: Report) -> None:
    rows = summary_rows(report)
    if not rows:
        return
    print()
    print(f"  {report.file}  [{report.mode}]  winner: {report.winner or 'n/a'}")
    header = f"  {'runtime':<10} {'wall':>10} {'cpu':>10} {'util':>7} {'rss':>10} {'faults':>9} {'ctx':>8}"
    print(header)
    print("  " + "-" * (len(header) - 2))
    for row in rows:
        print(
            f"  {row['name']:<10} {row['wall']:>10} {row['cpu']:>10} "
            f"{row['util']:>7} {row['rss']:>10} {row['faults']:>9} {row['ctx']:>8}"
        )
    print()


# --- html ----------------------------------------------------------------

CSS = """
:root {
  --bg: #0e1116; --panel: #151a21; --panel-2: #1b212b; --fg: #e7ecf3;
  --muted: #8b95a7; --line: #242b36; --accent: #5eead4;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
.wrap { max-width: 1180px; margin: 0 auto; padding: 40px 24px 72px; }
h1 { font-size: 30px; letter-spacing: -0.02em; margin: 0 0 6px; }
h2 { font-size: 19px; letter-spacing: -0.01em; margin: 44px 0 14px; }
.sub { color: var(--muted); margin: 0 0 26px; font-size: 14px; }
.badge {
  display: inline-block; padding: 3px 10px; border-radius: 999px;
  background: rgba(94,234,212,.12); color: var(--accent);
  border: 1px solid rgba(94,234,212,.32); font-size: 12.5px; font-weight: 600;
}
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 16px 18px; }
.card .k { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
.card .v { font-size: 24px; font-weight: 700; margin-top: 6px; letter-spacing: -0.02em; }
.card .h { color: var(--muted); font-size: 12.5px; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 13.5px; }
th, td { text-align: right; padding: 9px 12px; border-bottom: 1px solid var(--line); }
th:first-child, td:first-child { text-align: left; }
th { color: var(--muted); font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .06em; }
tbody tr:hover { background: var(--panel); }
tr.win td { background: rgba(94,234,212,.06); }
.dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 8px; }
figure { margin: 0 0 26px; background: var(--panel); border: 1px solid var(--line); border-radius: 16px; padding: 14px; }
figure img { width: 100%; display: block; border-radius: 8px; }
figcaption { color: var(--muted); font-size: 13px; padding: 10px 4px 2px; }
.grid2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(460px, 1fr)); gap: 18px; }
code { background: var(--panel-2); padding: 2px 6px; border-radius: 6px; font-size: 13px; }
footer { color: var(--muted); font-size: 12.5px; margin-top: 46px; border-top: 1px solid var(--line); padding-top: 16px; }
@media (max-width: 640px) { .wrap { padding: 24px 14px 48px; } th, td { padding: 7px 6px; font-size: 12px; } }
"""


def b64(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def build_html(report: Report, charts: list, colors: Colors,
               history: Path | None, out: Path) -> Path:
    rows = summary_rows(report)
    fastest = next((r for r in rows if r["fastest"]), rows[0] if rows else None)
    multi = len(rows) > 1
    cells = []
    for row in rows:
        color = colors.get(row["name"])
        cells.append(
            f'<tr class="{"win" if row["fastest"] else ""}">'
            f'<td><span class="dot" style="background:{color}"></span>{row["name"]}</td>'
            f'<td>{row["wall"]}</td><td>{row["range"]}</td><td>{row["wall_ratio"]}</td>'
            f'<td>{row["cpu"]}</td><td>{row["split"]}</td><td>{row["util"]}</td>'
            f'<td>{row["rss"]}</td><td>{row["rss_max"]}</td>'
            f'<td>{row["faults"]}</td><td>{row["ctx"]}</td><td>{row["runs"]}</td></tr>'
        )

    cards = []
    if fastest and multi:
        cards.append(
            f'<div class="card"><div class="k">Fastest</div>'
            f'<div class="v" style="color:{colors.get(fastest["name"])}">{fastest["name"]}</div>'
            f'<div class="h">{fastest["wall"]} wall</div></div>'
        )
        cards.append(
            f'<div class="card"><div class="k">Speedup</div>'
            f'<div class="v">{report.speedup:.2f}x</div>'
            f'<div class="h">slowest vs fastest</div></div>'
        )
        heaviest = max(rows, key=lambda r: report.runs[[x.name for x in report.runs].index(r["name"])].median_rss)
        cards.append(
            f'<div class="card"><div class="k">Heaviest memory</div>'
            f'<div class="v" style="color:{colors.get(heaviest["name"])}">{heaviest["rss"]}</div>'
            f'<div class="h">{heaviest["name"]} peak RSS</div></div>'
        )
    cards.append(
        f'<div class="card"><div class="k">Mode</div>'
        f'<div class="v">{report.mode}</div>'
        f'<div class="h">{plural_runs(report)}</div></div>'
    )
    cards.append(
        f'<div class="card"><div class="k">Saved</div>'
        f'<div class="v" style="font-size:17px">{report.mtime:%Y-%m-%d %H:%M}</div>'
        f'<div class="h">{report.path.name}</div></div>'
    )

    figures = []
    captions = {
        "00-dashboard.png": "Everything at a glance.",
        "01-wall-time.png": "Median wall time; whiskers span the fastest and slowest run.",
        "02-cpu-usage.png": "User vs kernel CPU time, and how much of a core each runtime consumed.",
        "03-memory.png": "Resident set size at peak, plus how much it moves between runs.",
        "04-distribution.png": "Every individual run, not just the median.",
        "05-system.png": "Page faults and context switches: how much kernel work the runtime causes.",
        "06-ratios.png": "Wall, CPU and memory as a multiple of the fastest runtime.",
        "07-history.png": "Trend across every saved result when several JSON files are passed.",
    }
    for path in charts:
        caption = captions.get(path.name, "")
        figures.append(
            f'<figure><img alt="{path.stem}" src="{b64(path)}">'
            f'<figcaption>{caption}</figcaption></figure>'
        )

    css = CSS
    html = f"""<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lou bench - {report.file}</title>
<style>{css}</style>
</head>
<body>
<div class="wrap">
  <span class="badge">{f"{report.winner or 'bench'} wins - {report.speedup:.2f}x" if multi else f"single runtime: {report.winner or 'n/a'}"}</span>
  <h1>Lou bench</h1>
  <p class="sub">{report.file} - {report.mode} mode - generated {dt.datetime.now():%Y-%m-%d %H:%M:%S} on {socket.gethostname()}</p>

  <div class="cards">{"".join(cards)}</div>

  <h2>Charts</h2>
  <div class="grid2">{"".join(figures)}</div>

  <h2>All runtimes</h2>
  <table>
    <thead><tr>
      <th>Runtime</th><th>Wall</th><th>Min - max</th><th>vs best</th>
      <th>CPU</th><th>user / kernel</th><th>util</th>
      <th>RSS med</th><th>RSS max</th><th>Faults</th><th>ctx sw</th><th>Runs</th>
    </tr></thead>
    <tbody>{"".join(cells)}</tbody>
  </table>

  <h2>Reproduce</h2>
  <p class="sub">Regenerate this report with:</p>
  <p><code>./bench.sh benchmark --lou --node --bun --mode deep --save {report.path.name} {report.file}</code></p>

  <footer>
    Generated by <code>scripts/bench_plot.py</code> from <code>{report.path}</code>.
    Charts are also saved as PNG next to this file.
  </footer>
</div>
</body>
</html>
"""
    index = out / "index.html"
    index.write_text(html, encoding="utf-8")
    return index


# --- main ----------------------------------------------------------------

def main(argv: list) -> int:
    parser = argparse.ArgumentParser(
        prog="bench_plot",
        description="Render profiler JSON results as charts and an HTML report.",
    )
    parser.add_argument("results", nargs="+", help="profiler JSON file(s)")
    parser.add_argument("-o", "--out", help="output directory (default: <json>.charts)")
    parser.add_argument("--title", help="optional title override")
    parser.add_argument("--dpi", type=int, default=150, help="PNG resolution (default 150)")
    parser.add_argument("--open", action="store_true", help="open the HTML report")
    parser.add_argument("--no-html", action="store_true", help="only write PNGs")
    args = parser.parse_args(argv)

    paths = [Path(p) for p in args.results]
    missing = [str(p) for p in paths if not p.exists()]
    if missing:
        sys.stderr.write("bench_plot: missing input: " + ", ".join(missing) + "\n")
        return 2

    reports = [load_report(p) for p in paths]
    out = Path(args.out) if args.out else paths[0].with_suffix("").with_name(
        paths[0].stem + ".charts"
    )
    out.mkdir(parents=True, exist_ok=True)

    colors = Colors(reports)
    latest = max(reports, key=lambda r: r.mtime)
    if not latest.runs:
        sys.stderr.write("bench_plot: " + str(latest.path) + " has no results\n")
        return 2

    charts = []
    charts.append(chart_dashboard(latest, colors, out, args.dpi))
    charts.append(chart_wall(latest, colors, out, args.dpi))
    charts.append(chart_cpu(latest, colors, out, args.dpi))
    charts.append(chart_memory(latest, colors, out, args.dpi))
    charts.append(chart_distribution(latest, colors, out, args.dpi))
    charts.append(chart_system(latest, colors, out, args.dpi))
    charts.append(chart_ratios(latest, colors, out, args.dpi))
    history = chart_history(reports, colors, out, args.dpi)
    if history:
        charts.append(history)

    for report in reports:
        print_summary(report)

    index = None
    if not args.no_html:
        index = build_html(latest, charts, colors, history, out)

    print(f"  charts: {out}")
    if index:
        print(f"  report: {index}")
        if args.open:
            webbrowser.open(index.resolve().as_uri())
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
