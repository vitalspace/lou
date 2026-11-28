# Lou

<div align="center">
  <img title="Lou" width="320" height="320" alt="Lou" src="https://github.com/user-attachments/assets/14eb6160-7670-4325-80cb-c83b1f75c266" />

  <p><strong>A JavaScript/TypeScript-compatible scripting language written in Zig.</strong></p>

  <p>
    <img alt="Zig 0.17.1" src="https://img.shields.io/badge/Zig-0.17.1-F7A41D?logo=zig&logoColor=white&style=flat-square" />
    <img alt="1044 tests passing" src="https://img.shields.io/badge/tests-1044%20passing-2ea44f?style=flat-square" />
    <img alt="Node console parity" src="https://img.shields.io/badge/console-Node%20parity-339933?logo=node.js&logoColor=white&style=flat-square" />
  </p>
</div>

Lou is a scripting language with partial JavaScript/TypeScript support,
implemented in **Zig 0.17.1**. It combines a bytecode VM with a tree-walking
evaluator, a type checker for `.lou`/`.ts` files, and a console implementation
that follows Node's `util.inspect` output.

## Highlights

- **JavaScript/TypeScript syntax** — classes (inheritance, `super`, static members, private fields, getters/setters), closures, arrow functions, default and rest parameters, destructuring, spread, computed properties, and generators (`function*`, `yield`).
- **Promises** — a built-in `Promise` object and promise chaining.
- **Modern data types** — `BigInt`, `Symbol`, `Map`, `Set`, `WeakRef`, `FinalizationRegistry`, and `DisposableStack`.
- **Node-compatible console** — `dir`, `table`, `trace`, groups, counters, timers, assertion messages, and ANSI colors on real terminals.
- **RegExp engine** — parser, compiler, and VM with capture groups and callbacks.
- **Type checker** — optional static checking for `.lou` and `.ts` sources.
- **Bytecode VM** — optimized execution with an AST evaluator fallback.
- **Compatibility suite** — every fixture is executed by both Lou and Node and diffed byte-for-byte.

## Requirements

- **Zig 0.17.1**
- Node.js (only for `zig build compat`)

## Installation

```bash
git clone https://github.com/vitalspace/lou.git
cd lou
zig build release
```

The binary is written to `zig-out/bin/lou`.

## Usage

```bash
./zig-out/bin/lou run script.js
./zig-out/bin/lou run script.lou
```

`.lou` and `.ts` files go through the type checker; `.js` files skip it.

## Build

```bash
zig build             # Debug build (leak checking enabled)
zig build release     # ReleaseFast build (use this for benchmarks)
zig build test        # Unit tests + compatibility suite
zig build compat      # Compatibility suite only (requires Node)
zig build run -- run script.js
```

> Debug builds use Zig's safety allocator with leak detection. They are
> intentionally slower; benchmark with `zig build release`.

## Benchmarks

`bench.sh` runs the profiler in `profiler/` and turns the results into charts.

```bash
./bench.sh main                  # Lou vs Node on js/main.js (50 runs, deep)
./bench.sh arrays                # Lou vs Bun on js/arrays/arrays.js
./bench.sh benchmark --lou --node --bun --mode deep js/main.js
./bench.sh compat                # every tests/compat fixture: Lou vs Node vs Bun
./bench.sh compat --runs 30      # more samples per fixture (default: 20)
./bench.sh plot                  # charts for every saved result
./bench.sh plot --open           # ... and open the HTML report
```

`compat` is the regression sweep: it runs every fixture in `tests/compat/`
through the profiler, compares Lou's median against the fastest rival and writes
`bench-results/compat-<stamp>/report.md` with the summary, each fixture where
Lou is slower, near-ties, and fixtures that crash or exit non-zero. The raw
medians live in `report.json` and `ratios.png` plots the comparison.

Every run is saved to `bench-results/<timestamp>-<script>.json` and charted into
`bench-results/latest/`:

| File | Metric |
| --- | --- |
| `00-dashboard.png` | all charts in one image |
| `01-wall-time.png` | execution time, median with min/max whiskers |
| `02-cpu-usage.png` | user vs kernel CPU time, and CPU utilisation |
| `03-memory.png` | peak RSS and how much it varies between runs |
| `04-distribution.png` | every individual run (box plot + scatter) |
| `05-system.png` | page faults and context switches |
| `06-ratios.png` | wall, CPU and memory as a multiple of the fastest runtime |
| `07-history.png` | trends across all saved results |
| `index.html` | all of the above plus a summary table |

Charts need Python 3 with matplotlib:

```bash
sudo pacman -S python-matplotlib      # Arch
sudo apt install python3-matplotlib   # Debian/Ubuntu
```

The renderer is `scripts/bench_plot.py`; it also works on any profiler JSON:

```bash
python3 scripts/bench_plot.py results.json -o out/ --open
```

## Console parity

`console` is not a thin wrapper around `log`. It follows Node's behavior for
streams, formatting, and terminal colors:

- `log`, `info`, and `debug` write to **stdout**; `error`, `warn`, and `trace` write to **stderr**.
- `dir(value, options)` supports `depth`, `colors`, `maxArrayLength`, and `sorted`.
- `table(data, properties)` builds the same grid as Node, including `(index)`, headers, borders, and column alignment.
- On a TTY, table cells and inspected values use Node's ANSI palette. Widths ignore escape bytes, so colored and plain output align identically.
- `NO_COLOR` and `TERM=dumb` disable colors, matching Node and Bun.
- `assert`, `count`, `countReset`, `group`, `groupEnd`, `trace`, `time`, `timeEnd`, and `clear` are implemented.

```js
const users = [
  { name: "Ada", age: 36, active: true },
  { name: "Linus", age: 56, active: false },
];

console.table(users);
console.dir(users[0], { depth: 1, colors: true });
console.trace("done");
```

`table` and `dir` are built for allocation-sensitive paths: each cell is
formatted once and the whole table is flushed in one pass. A 1,000-row,
three-column table renders in roughly **1.3–1.7 ms** in ReleaseFast on the
development machine.

## Builtins

| Area | Provided |
| --- | --- |
| Console | `console.*` — the full set listed above |
| Collections | `Array`, `Object`, `Map`, `Set`, iterators |
| Text | `String`, `RegExp`, `JSON` |
| Numbers | `Number`, `Boolean`, `BigInt`, `Math`, `parseInt`, `parseFloat`, `isFinite`, `isNaN` |
| Time | `Date`, `Intl` |
| Promises | `Promise` |
| Runtime | `Symbol`, `WeakRef`, `FinalizationRegistry`, `DisposableStack`, URI helpers |

Method coverage varies; the compatibility fixtures under `tests/compat/` document
what is currently exercised.

## Architecture

```text
src/
├── main.zig            # CLI entry point
├── lexer.zig           # Tokenizer
├── parser.zig          # AST construction
├── ast.zig             # AST definitions
├── evaluator.zig       # Tree-walking evaluator
├── vm.zig              # Bytecode VM
├── optimizations.zig   # Optimizer
├── type_checker.zig    # Static checks for .lou/.ts
├── environment.zig     # Scopes, frames, runtime state
├── builtins/           # console, array, string, json, regex, ...
├── types/              # Runtime values and objects
└── utils/              # Shared helpers

tests/
├── compat/             # .lou fixtures + Node .js counterparts
└── ...                 # Zig unit tests
```

## Testing

```bash
zig build test
```

Current status:

- **1,125** Zig tests pass.
- **103** JavaScript compatibility fixtures.
- **103** produce byte-identical output to Node.
- `console-output` and `console-inspection` match Node exactly, including ANSI output on a TTY.

The compatibility runner strips ANSI before diffing, so color behavior is also
covered by dedicated unit tests and a PTY diff against Node.

## Philosophy

Lou will never abandon Zig development. If Zig lacks something Lou needs to be
fast and efficient, we will use interoperability with C/C++.
