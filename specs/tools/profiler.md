# Profiler — Benchmarking Harness Lou vs Node

## Propósito

Medir y comparar el rendimiento de Lou contra Node.js usando herramientas del SO. **Sin modificar Lou.** El profiler es un CLI independiente en Zig que ejecuta Lou y Node con profilers externos (time, perf, valgrind) y genera reportes comparativos.

## Comandos CLI

```
profiler bench [opts] <file.js>          # Lou + Node, todo
profiler run-lou [opts] <file.js>        # solo Lou
profiler run-node [opts] <file.js>       # solo Node
profiler compare <a.json> <b.json>       # dos resultados guardados
profiler list-tools                      # detecta herramientas disponibles
```

### Opciones globales

| Flag | Descripción |
|------|-------------|
| `--mode quick\|deep\|memory` | quick (default), deep (+ perf record), memory (+ valgrind) |
| `--json` | Output en JSON en vez de tabla |
| `--no-node` | Saltar Node |
| `--lou-bin <path>` | Ruta al binario de Lou (default: busca en PATH y ./zig-out/bin/lou) |
| `--save <file.json>` | Guardar resultados |
| `--no-color` | Output plano sin ANSI |
| `-v, --verbose` | Raw output de herramientas en stderr |

## Modos de profundidad

| Modo | Herramientas | Overhead | Métricas |
|------|-------------|----------|----------|
| `quick` | `time -v` + `perf stat -d` | ~0 | wall time, user/sys CPU, RSS, page faults, context switches, cycles, instructions, IPC, cache misses, branch misses |
| `deep` | quick + `perf record -g` | ~1-2x | + hottest functions con % CPU y source line |
| `memory` | deep + `valgrind --tool=massif` | ~10-20x | + pico heap, total allocs, leaks, heap timeline |

## Localización de binarios

Lou (orden de búsqueda):
1. `--lou-bin <path>` explícito
2. `./zig-out/bin/lou` relativo al cwd
3. `lou` en PATH

Node: siempre `node` en PATH.

## Herramientas detectadas

| Binario | Flag en reporte |
|---------|----------------|
| `/usr/bin/time` | time |
| `perf` | perf |
| `valgrind` | valgrind |
| `node` | node |

## Formato de salida

### Tabla (default)

```
═══ PROFILER ═══════════════════════════════════
Benchmark: js/main.js
Mode: quick

                Lou          Node          Ratio
Wall:        145.2ms       12.3ms        11.8x
CPU (user):  142.1ms       14.2ms        10.0x
RSS:           4.2 MB      32.1 MB        0.13x
Instr:         452 M         38 M         11.9x
Cycles:       1.2 B        110 M          10.9x
IPC:           0.37          0.34          1.1x
Cache miss:   12.3 M         2.1 M         5.9x
Branch miss:   4.2 M         0.8 M         5.3x

── Lou Hot Functions (perf) ──
 42.3%  evaluate         evaluator.zig:953
 18.1%  env.get          evaluator.zig:303
 12.5%  VM.interpret     vm.zig:350
  8.2%  valToStr         vm.zig:539
  5.1%  toF64            vm.zig:529

── Insights ──
  🔴 evaluate() = 42.3% hot — tree-walk switch dispatch
  🔴 env.get()  = 18.1% hot — string hashmap lookup loop
  🟡 valToStr() = 8.2%  alloc per concat
  🟢 RSS ratio  = 0.13x — Lou usa mucha menos memoria
```

### JSON

```json
{
  "benchmark": "js/main.js",
  "mode": "quick",
  "timestamp": "2026-05-16T12:00:00Z",
  "lou": {
    "wall_time_ns": 145200000,
    "user_cpu_ns": 142100000,
    "max_rss_bytes": 4404019,
    "instructions": 452000000,
    "cycles": 1200000000,
    "cache_misses": 12300000,
    "branch_misses": 4200000
  },
  "node": {
    "wall_time_ns": 12300000,
    ...
  },
  "ratios": {
    "wall_time": 11.8,
    "rss": 0.13,
    "instructions": 11.9
  },
  "hot_functions": [
    {"symbol": "evaluate", "source": "evaluator.zig", "line": 953, "overhead_pct": 42.3}
  ],
  "tools_available": ["time", "perf", "node"],
  "tools_missing": ["valgrind"]
}
```

## Insights automáticos

| Señal | Interpretación |
|-------|---------------|
| evaluate > 30% hot | Tree-walk overhead, Node JIT compila |
| RSS << Node | Esperado, Lou es minimalista sin JIT |
| Branch miss alta | Switch grande en evaluate (46 variantes) |
| Cache miss alta | StringHashMap lookups dispersan caché |
| IPC < 0.5 | Stall-heavy, probablemente memory-bound |
| valToStr caliente | String concat alloc en cada operación |

## Arquitectura

```
main.zig   ← CLI + orquestador
  │
  ├── metrics.zig   ← structs Metric* y MetricsCollection
  ├── parsers.zig   ← parseTimeOutput, parsePerfStat, parsePerfReport
  └── report.zig    ← formatTable, formatInsights, formatJSON

Subprocesos lanzados:
  /usr/bin/time -v <bin> <args...>
  perf stat -d <bin> <args...>
  perf record -g -o <tmpfile> <bin> <args...>
  perf report -i <tmpfile> --stdio -F overhead,sym,src_line
```

## Dependencias

- Zig std (spawn subprocesos, pipes)
- No external crates/packages
- Binarios externos: `/usr/bin/time`, `perf`, `node`, `valgrind` (opcionales)
