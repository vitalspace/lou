#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PROFILER="$ROOT/profiler/zig-out/bin/profiler"
PLOTTER="$ROOT/scripts/bench_plot.py"
JS_DIR="$ROOT/js"
RESULTS_DIR="$ROOT/bench-results"

stamp() { date +%Y%m%d-%H%M%S; }

ensure_profiler() {
  if [ ! -x "$PROFILER" ]; then
    echo "=== Building profiler ==="
    ( cd "$ROOT/profiler" && zig build -Doptimize=ReleaseFast )
    echo ""
  fi
}

# plot_results <out_dir> <open|""> <json...>
plot_results() {
  local out_dir="$1"; shift
  local open_flag="$1"; shift
  local args=()
  if [ -n "$open_flag" ]; then args+=(--open); fi
  args+=("$@")
  python3 "$PLOTTER" "${args[@]}" --out "$out_dir" || {
    echo "warning: charts skipped (python3 + matplotlib required)" >&2
    return 0
  }
}

cmd_build() {
  echo "=== Building ReleaseFast ==="
  zig build release
  echo ""
}

cmd_arrays() {
  echo "=== Lou vs Bun: arrays/arrays.js (deep) ==="
  ensure_profiler
  local out="$RESULTS_DIR/$(stamp)-arrays.json"
  mkdir -p "$RESULTS_DIR"
  "$PROFILER" \
    --run Lou:"lou run" \
    --run Bun:bun \
    "$JS_DIR/arrays/arrays.js" \
    --mode deep \
    --save "$out"
  echo ""
  plot_results "$RESULTS_DIR/latest" "" "$out"
}

cmd_main() {
  echo "=== Lou vs Node: main.js (deep) ==="
  ensure_profiler
  local out="$RESULTS_DIR/$(stamp)-main.json"
  mkdir -p "$RESULTS_DIR"
  "$PROFILER" \
    --run Lou:"lou run" \
    --run Node:node \
    "$JS_DIR/main.js" \
    --mode deep \
    --save "$out"
  echo ""
  plot_results "$RESULTS_DIR/latest" "" "$out"
}

cmd_test() {
  echo "=== Running tests ==="
  zig test src/main.zig
  echo ""
}

cmd_benchmark() {
  shift
  local run_args=()
  local file=""
  local mode=""
  local save=""
  local perf_flag=""
  local has_runtime=false
  local want_plot=true
  local open_flag=""
  local out_dir="$RESULTS_DIR/latest"

  while [ $# -gt 0 ]; do
    case "$1" in
      --lou)    run_args+=(--run "Lou:lou run"); has_runtime=true; shift ;;
      --bun)    run_args+=(--run "Bun:bun");     has_runtime=true; shift ;;
      --node)   run_args+=(--run "Node:node");   has_runtime=true; shift ;;
      --mode)   mode="--mode $2"; shift 2 ;;
      --perf)   perf_flag="--perf"; shift ;;
      --save)   save="$2"; shift 2 ;;
      --out)    out_dir="$2"; shift 2 ;;
      --plot)   want_plot=true; shift ;;
      --no-plot) want_plot=false; shift ;;
      --open)   open_flag="--open"; shift ;;
      --no-color) run_args+=(--no-color); shift ;;
      -*)
        echo "Unknown flag: $1"
        exit 1
        ;;
      *)
        if [ -z "$file" ]; then
          file="$1"
        else
          echo "Unexpected argument: $1"
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [ -z "$file" ]; then
    echo "Missing file argument"
    echo "Usage: $0 benchmark [--lou] [--bun] [--node] [--mode quick|deep] [--perf] [--save file.json] [--out dir] [--open] [--no-plot] <file>"
    exit 1
  fi

  if ! $has_runtime; then
    run_args+=(--run "Lou:lou run")
  fi

  # Always keep a JSON copy: charts and history are built from it.
  if [ -z "$save" ]; then
    mkdir -p "$RESULTS_DIR"
    save="$RESULTS_DIR/$(stamp)-$(basename "$file" .js).json"
  else
    mkdir -p "$(dirname "$save")"
  fi

  echo "=== Benchmark: $(basename "$file") ==="
  cmd_build
  ensure_profiler
  "$PROFILER" "${run_args[@]}" $mode $perf_flag --save "$save" "$file"

  echo "  json:   $save"
  if $want_plot; then
    plot_results "$out_dir" "$open_flag" "$save"
  fi
}

cmd_plot() {
  local out_dir="$RESULTS_DIR/latest"
  local open_flag=""
  local files=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --open) open_flag="--open"; shift ;;
      --out)  out_dir="$2"; shift 2 ;;
      *)      files+=("$1"); shift ;;
    esac
  done

  if [ "${#files[@]}" -eq 0 ]; then
    shopt -s nullglob
    files=("$RESULTS_DIR"/*.json)
    shopt -u nullglob
  fi

  if [ "${#files[@]}" -eq 0 ]; then
    echo "No result JSONs found."
    echo "Run: $0 benchmark --lou --node --bun --save $RESULTS_DIR/run.json js/main.js"
    exit 1
  fi

  plot_results "$out_dir" "$open_flag" "${files[@]}"
}

cmd_all() {
  cmd_test
  cmd_build
  cmd_arrays
  echo ""
  cmd_main
}

usage() {
  echo "Usage: $0 <command> [args]"
  echo ""
  echo "Commands:"
  echo "  test                           zig test src/main.zig"
  echo "  build                          zig build release"
  echo "  arrays                         build + benchmark arrays.js (Lou vs Bun, deep) + charts"
  echo "  main                           build + benchmark main.js (Lou vs Node, deep) + charts"
  echo "  benchmark [flags] <file>       build + benchmark with custom runtimes + charts"
  echo "    --lou                          include Lou runtime"
  echo "    --bun                          include Bun runtime"
  echo "    --node                         include Node runtime"
  echo "    --mode quick|deep              profiling depth"
  echo "    --perf                         run perf stat for hardware counters"
  echo "    --save <file.json>             save results (default: bench-results/<stamp>-<file>.json)"
  echo "    --out <dir>                    where charts go (default: bench-results/latest)"
  echo "    --plot / --no-plot             force or skip chart generation"
  echo "    --open                         open the HTML report when done"
  echo "    --no-color                     disable ANSI colors"
  echo "  plot [flags] [file.json ...]   charts + HTML for saved results"
  echo "    (no files)                     plot every JSON in bench-results/"
  echo "    --out <dir>                    output directory (default: bench-results/latest)"
  echo "    --open                         open the HTML report when done"
  echo "  all                            test + build + both benchmarks + charts"
  echo "  help                           show this message"
  echo ""
  echo "Charts land in bench-results/latest/index.html (PNG files alongside it)."
}

sel="${1-}"
[ -z "$sel" ] && sel="all"

case "$sel" in
  help|--help|-h) usage ;;
  benchmark|bm) cmd_benchmark "$@" ;;
  plot|charts|report) shift; cmd_plot "$@" ;;
  test)     cmd_test ;;
  build)    cmd_build ;;
  arrays)   cmd_build && cmd_arrays ;;
  main)     cmd_build && cmd_main ;;
  all)      cmd_all ;;
  *)
    echo "Unknown command: $sel"
    echo "Use: $0 help"
    exit 1
    ;;
esac
