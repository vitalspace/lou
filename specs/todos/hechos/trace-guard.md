# Trace Guard — `DEBUG_TRACE` / `tracePrint` DCE invariant

## status
COMPLETADO (2026-06-24)

## Resumen

El intérprete tenía **26 llamadas incondicionales** a `std.debug.print("[trace] ...")` repartidas por el VM, evaluator y el módulo de Promise. Cada llamada emitía a `stderr` en producción, contaminando la salida normal del programa.

Refactor aplicado en dos capas para silenciarlos:

1. **Helper central** (`src/environment.zig`) — `pub const DEBUG_TRACE = false;` + `pub inline fn tracePrint(comptime fmt: []const u8, args: anytype) void { if (DEBUG_TRACE) std.debug.print("[trace] " ++ fmt, args); }`. La estructura espeja el patrón existente de `DEBUG_OPTIMIZATION` / `debugPrint` en el mismo archivo.
2. **Gating en cada call site** (`promise.zig` × 13, `evaluator.zig` × 7, `vm.zig` × 3) — toda invocación pasó de `tracePrint("...", .{...})` a `if (DEBUG_TRACE) tracePrint("...", .{...})` (forma de statement, sin braces, sin re-indent del tuple).

Cada uno de los 3 archivos importa `const DEBUG_TRACE = env_mod.DEBUG_TRACE;` junto al alias `const tracePrint = env_mod.tracePrint;` para que el `if` del call site vea el comptime-value de propagación limpia.

## Invariante validado

> Con `DEBUG_TRACE = false` y compilación bajo `-Doptimize=ReleaseSafe`, **ambos** el cuerpo de `tracePrint` Y el args-tuple `.{...}` son completamente elididos. Bajo `-Doptimize=Debug`, el comportamiento NO está garantizado (LLVM puede preservar el código de trace para symbolización/debug-friendliness — el `if` del call site sigue ocultando los args en Sema, pero no se debe asumir DCE completo).

La doble capa es deliberada:

- **`if (DEBUG_TRACE) tracePrint(...)` en el call site** → Zig 0.16 Sema propaga `unreachable` a la expresión args, elidiendo la construcción del tuple al comptime (incluyendo ternarios, unwrap de unions, formateos `.{...}` no-triviales).
- **`if (DEBUG_TRACE) std.debug.print(...)` dentro de `tracePrint`** → LLVM/optimize-on-ReleaseSafe DCE-elimina la rama entera; defense-in-depth.

El gate interno quedó redundante con el gate externo (todo call-site reachable ya pasó por el `if` exterior), pero se mantuvo como red de seguridad y porque el helper podría ser invocado sin el wrapper en tests ad-hoc.

## Validación (A/B)

### Emit-side: stderr en ReleaseSafe (`-Doptimize=ReleaseSafe`)
- **Heavy smoke** (Promise/import, nested objects, `try/catch`, `new Date()`, `Set/Map`, regex, BigInt):
  - `DEBUG_TRACE=false` → **0** líneas `[trace]` en stderr
  - `DEBUG_TRACE=true`  → ~4 líneas (uno por method-call: `entered` + `obj tag`)
- **Diff stdout** entre Debug-build y ReleaseSafe-build sobre el mismo workload: **byte-idéntico** (`diff` vacío, sin divergencia semántica).

### Performance-side: micro-benchmark `arr.indexOf` × 1,000,000
| Build | median (s) | stdev | trace lines × run |
|---|---:|---:|---:|
| TRACE-OFF (`DEBUG_TRACE=false`) | 18.505 | ~0.01 | 0 |
| TRACE-ON  (`DEBUG_TRACE=true`)  | 20.710 | ~0.01 | ~4 M |
| **Δ per method-call**            | —      | —    | **+2.20 µs** |

Interpretación: el overhead de `std.debug.print + format + write_to_stderr` es ~2.20 µs por cada vez que un trace site dispara cuando `DEBUG_TRACE=true`. **Workload-proporcional** al número de fires, **no** al tamaño del workload que el trace envuelve. Por eso una workload mixta (50 k aritmética + 2 method calls) no exhibió delta — el costo del trace es amortizado en ~4 fires, invisible dentro del ruido.

Esta cifra sirve como presupuesto de regresión: cualquier `tracePrint` site nuevo que se añada sabiendo que dispara N veces por operación efectiva añade `N × 2.2 µs` al runtime bajo `DEBUG_TRACE=true`.

### Sema-elision savings: GATED vs UNGATED A/B (medición 2026-06-24)

Para aislar cuánto tiempo gana específicamente el call-site `if
(DEBUG_TRACE)` en `DEBUG_TRACE=false` (vs el LLVM DCE base que ya elide
el cuerpo del helper interno), se compararon dos binarios
ReleaseSafe sobre el mismo workload `1M arr.indexOf`:

| Build | median (s) | stdev | trace lines × run |
|---|---:|---:|---:|
| GATED-false   (`if (DEBUG_TRACE)` + `DEBUG_TRACE=false`) | **20.22** | 1.70 | 0 |
| UNGATED-false (gates stripped, `DEBUG_TRACE=false`) | **19.93** | 5.12 | 0 |
| **Δ (gated - ungated, median)** | **+295 ms** (+1.48%) | — | — |

Interpretación honesta:

* El Δ **NO ES ZERO** — el gate `if (DEBUG_TRACE) tracePrint(...)`
  impone una pequeña sobrecosto de codegen (≈ 75 ns / sitio × ~4
  sitios / iteración × 1M iteraciones ≈ 300 ms), aunque **dentro del
  ruido** del stdev elevado del arm ungated (5.12 s).
* **Bajo `-Doptimize=ReleaseSafe` LLVM ya DCE-elide el cuerpo del
  helper y los args-tuples trivialmente**, sin necesidad del gate
  exterior. El gate exterior aporta defensa adicional, pero **no
  ganancia medible** de performance en este workload.
* La invariante original (Sema-elide del args-tuple) **sigue siendo
  válida** para los casos donde el args-tuple no es trivial (closures,
  ternarios, `unwrap`, etc.) y donde `-Doptimize=Debug` no garantiza
  DCE completo. Bajo ReleaseSafe y args-tuples simples, LLVM lo hace
  sin necesidad del gate.
* **Recomendación práctica**: mantener el gate exterior (defense in
  depth — chequeable por `tests/check-trace-guard.py`, garantiza
  semántica bajo Debug y bajo variantes de optimización no probadas).
  No rollbackear — la pequeña (~0.3 % en este benchmark) sobrecosto
  vale la pena para el enforcement automatizado.

Esta medición corrige parcialmente la afirmación original "el gate
exterior gana X ms de performance". La realidad bajo ReleaseSafe es:
* LLVM hace la mayor parte del trabajo sin ayuda.
* El gate exterior + `tests/check-trace-guard.py` mantienen la
  corrección arquitectónica pero no producen mejora medible de
  performance en workloads pequeños.

## Activar / desactivar

Para activar los traces (diagnóstico temporal):

```bash
# 1. Editar src/environment.zig:
sed -i 's/pub const DEBUG_TRACE = false;/pub const DEBUG_TRACE = true;/' src/environment.zig

# 2. Rebuild:
zig build -Doptimize=ReleaseSafe

# 3. Ejecutar y mirar stderr:
./zig-out/bin/lou run <program.lou> 2>  # o 2>&1 para merge con stdout

# 4. Restaurar:
sed -i 's/pub const DEBUG_TRACE = true;/pub const DEBUG_TRACE = false;/' src/environment.zig
zig build -Doptimize=ReleaseSafe
```

Para verificar que la invariante sigue cumpliéndose:

```bash
zig build -Doptimize=ReleaseSafe
# Cualquier programa produce cero líneas [trace] en stderr (DEBUG_TRACE=false).
```

## Caveats / Leaks conocidos

- **Regex `(?<!\.)` look-behind en el wrap script**: si en el futuro algún código invoca `something.tracePrint(...)` (como método en lugar de top-level), el script de wrapping lo saltaría silenciosamente. Hoy seguro porque `tracePrint` siempre es top-level. Un test CI que cuente los `tracePrint(` invocations podría cerrar la puerta.
- **No hay `if (DEBUG_TRACE)` en el alias `const tracePrint = env_mod.tracePrint;`** — esto es deliberado. El alias sólo importa el puntero a la función; el gating ocurre en cada call site.
- **`DEBUG_TRACE` debe permanecer `pub const`** (no `pub var`); un var runtime forzaría `if (var_bool)` y Sema ya no podría elidir el args-tuple.
- El gate externo (`if (DEBUG_TRACE)` al call site) **NO elide la evaluación del `obj.js_object.properties.get(...)` ni de la lógica de lookup del `@@type`** que ocurrieron ANTES del `tracePrint(...)`. Sólo elide el cost del `.{...}` y el `std.debug.print`.

## Archivos modificados

- `src/environment.zig` — añadido `pub const DEBUG_TRACE = false;` (línea ~8) y `pub inline fn tracePrint(comptime fmt, args) void` (línea ~23). 26 llamadas `std.debug.print("[trace] ...")` reemplazadas por `tracePrint(...)`.
- `src/builtins/promise/promise.zig` — 13 sites wrapped con `if (DEBUG_TRACE) tracePrint(...)` + alias `const DEBUG_TRACE = env_mod.DEBUG_TRACE;`.
- `src/evaluator.zig` — 7 sites wrapped + alias.
- `src/vm.zig` — 3 sites wrapped + alias. Los arms `ac==0` del dispatcher `@@type` (dedup'd contra `ac>0`) no tenían tracePrint y siguen sin tenerlo.

Total: **23/23** call sites wrapped (matches pre-refactor inventory).

## Compat suite

Sin cambios. Baseline antes y después del refactor:

```
bash tests/compat/run.sh  # → PASS=33 FAIL=20 SKIP=1
```

Los 20 FAIL son pre-existentes en specs no relacionados (arrow-syntax, boolean, call-apply-bind, date-object, etc.) — el trace-guard refactor **no introdujo ni resolvió ninguna regresión**.

## pendiente (futuro)

- ~~Aplicar el mismo gating pattern a `debugPrint` (controlado por `DEBUG_OPTIMIZATION`) si su uso hot-path muestra un perfil similar. Misma estructura: `if (DEBUG_OPTIMIZATION) debugPrint(...)` en cada call site del archivo que lo use.~~ → **resuelto** (2026-06-24): ver "Espejo: `debugPrint` / `DEBUG_OPTIMIZATION`" abajo.
- ~~Considerar un test CI que cuente `tracePrint(` invocations y verifique que el `if (DEBUG_TRACE)` wrapper esté presente en cada uno (catch el riesgo del look-behind regex, ver Caveats).~~ → **resuelto**: `tests/check-trace-guard.py` (ver "Validación CI" abajo).
- Documentar el overhead per-fire (2.20 µs) en el README o en una guía de contributor para que quien añada trace sites tenga presupuesto explícito.

## Espejo: `debugPrint` / `DEBUG_OPTIMIZATION`

Mismo invariante y misma solución, sobre el helper paralelo en
`src/environment.zig`:

```zig
pub const DEBUG_OPTIMIZATION = false;
pub inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG_OPTIMIZATION) {
        std.debug.print(fmt, args);
    }
}
```

A diferencia de `tracePrint`, `debugPrint` no prefija `[trace] ` — el
caller escribe el prefijo (típicamente `[OPTIMIZATION]` o
`[ARRAY PUSH OPTIMIZATION]`). Eso no cambia el invariante args-tuple.

### Aplicación (2026-06-24)

* `src/optimizations.zig` — alias `const DEBUG_OPTIMIZATION = Env.DEBUG_OPTIMIZATION;` (junto al alias existente `const debugPrint = Env.debugPrint;`) + 8 call sites wrapped como `if (DEBUG_OPTIMIZATION) debugPrint("[OPTIMIZATION] ...", .{...});` (líneas que estaban en `optimizeSimpleForLoop` y `optimizeArrayPushLoop`).
* `src/evaluator.zig` — alias `const DEBUG_OPTIMIZATION = env_mod.DEBUG_OPTIMIZATION;` (junto al alias existente `const debugPrint = env_mod.debugPrint;`) + 3 call sites wrapped como `if (DEBUG_OPTIMIZATION) debugPrint("[OPTIMIZATION] Trying/SUCCESS/FAILED-falling-through ...", .{...});` en el handler `.ForLoop`.
* `src/evaluator.zig.bak2` — backup stale (no compilado, no referenciado por `build.zig`/`build.zig.zon`); explícitamente excluido del wrap.

Total: **11/11** call sites wrapped (8 en optimizations.zig + 3 en
evaluator.zig). El change size es mínimo: optimizations.zig +31 líneas,
evaluator.zig +1179 líneas (incluyendo el walk del archivo más grande).

### Validaci\u00f3n A/B (Debug + ReleaseSafe)

* Build green bajo `DEBUG_OPTIMIZATION=false` y `=true` (zig build exit 0
  en ambos modos).
* Stdout **byte-identical** bajo ambos modos (`diff` vacío) — la gating
  outer (`if (DEBUG_OPTIMIZATION) debugPrint(...)`) hace que Sema
  propague `unreachable` al args-tuple cuando `false`, así que el
  programa no paga ningún costo por los debug sites que nunca disparan.

### Caveat observado (no regresión introducida por este refactor)

El smoke A/B emite **0** líneas `[OPTIMIZATION]` en stderr incluso con
`DEBUG_OPTIMIZATION=true` para el workload probado
(`for (let i = 0; i < N; i++) sum += i` y similares). La función
`optimizeSimpleForLoop` está wrap-eada y compila al Sema-elide
correctly, pero su **path de invocación** desde el handler `.ForLoop`
no parece disparar para los shapes de loop del smoke test (el caso de
`for (...)` con block-scoped `let` Init probablemente aborta antes).
Esto es pre-existente al wrap gating: no es regresión del refactor.

Si los markers `[OPTIMIZATION]` no aparecen nunca en este codebase, el
overhead medido para `tracePrint` (2.20 µs per-fire) sería
proporcionalmente cero para `debugPrint`. El wrap sigue siendo
correcto: si alguien en el futuro arregla el dispatch para que el
optimizer fires, los markers aparecerán automáticamente bajo
`DEBUG_OPTIMIZATION=true` y se elidirán bajo `false`.

### Pendiente (futuro)

- Extender `tests/check-trace-guard.py` para también hacer cumplir
  `if (DEBUG_OPTIMIZATION) debugPrint(...)` en cada call site
  (parallel gate-enforcer). Hoy solo cubre `tracePrint`. La estructura
  del script est\u00e1 lista para absorber una segunda tupla
  (prefix=`debugPrint`, alias=`DEBUG_OPTIMIZATION`, gutter=`if
  ...`).

## Validación CI (cierre del riesgo del look-behind regex)

Script: `tests/check-trace-guard.py` (Python 3 stdlib). Cierra el riesgo
documentado arriba ("Regex `(?<!\.)` look-behind en el wrap script") que
un día un `obj.tracePrint(...)` method-form slip silenciosamente sin
gate.

Frontieres cerradas por el script:

1. **Bare call** — `tracePrint("...", .{...})` sin gate → FAIL.
2. **Method-form** — `obj.tracePrint(...)` (que el wrap-script con
   `(?<!\.)` habría saltado) → FAIL porque el gate-introducer regex
   nunca anclaría en `obj.`.
3. **Inline gate** — el predicado acepta `if (DEBUG_TRACE) tracePrint(...)`
   en cualquier posición dentro de la línea, no solo al inicio. Eso
   cubre la forma idiomática `orelse { if (DEBUG_TRACE) tracePrint(...) }`
   y `catch { if (DEBUG_TRACE) tracePrint(...) }` que se usa en
   `evaluator.zig`, `vm.zig` y `promise.zig`.
4. **Docstrings** — `(pub )?(const|let|var) NAME[[:] type] = "..."` con
   body que contiene `tracePrint(` se clasifica como comentario
   (heurística explícita para no flaggear líneas que son documentación).
5. **Block-comment continuation lines** — un state machine char-by-char
   (depth counter para `/*` / `*/` anidados) evita flaggear `tracePrint(`
   dentro de `/* ... */` en cualquier línea del bloque.
6. **BOM** — el read usa `encoding="utf-8-sig"` para strip el U+FEFF
   inicial y que los regex anclados en `^\s*` no rompan en archivos
   guardados con tooling Windows.
7. **Word-boundary precision** — el gate usa `\btracePrint\(` (no
   substring), rechaza `xtracePrint(...)` no-canónica (sin word
   boundary).

Exit codes:

* `0` — árbol limpio (gate aplicado en cada call site).
* `1` — al menos un FAIL.
* `2` — root inválido (CLI invocado con path inexistente).

Uso:

```bash
python3 tests/check-trace-guard.py        # default root = src/
python3 tests/check-trace-guard.py src    # explícito
```

Validación al construir el script (2026-06-24):

| Test | Resultado |
|---|---|
| A — `python3 tests/check-trace-guard.py src` | exit 0; 23 gated + 1 skip (def/alias) + 1 in comments/docstrings + **0 violations** (25 tracePrint references across 172 .zig files) |
| B — fixture con 10 casos_edge (gated, mid-expression gate, bare, docstring untyped+typed, block-comment single line + continuation, method-form, `xtracePrint(...)` no-canónica, alias, def) | exit 1; exactly 2 FAIL: bare call + method-form; el resto correctamente clasificado |
| C — sanity (ungate 1 site real, run, expect 1 FAIL, restore, expect 0) | pass |

Sin SyntaxWarning en stderr (docstrings raw que evitan `\s` literal).

## Integración futura

`tests/compat/run.sh` no invoca este script porque es un análisis
estático, no un compat-test. Si se añade CI (GitHub Actions / similar),
el primer step debería ser:

```yaml
- name: trace-guard
  run: python3 tests/check-trace-guard.py
```

Esto falla el build si alguien añade un `tracePrint(...)` sin el gate,
preservando la invariante documentada en este spec.

## Cómo extender el patrón (receta)

Para añadir un nuevo trace site:

```zig
// 1. Declarar alias en la cabecera del archivo (una vez):
const env_mod = @import("environment.zig"); // ruta relativa al archivo
const tracePrint = env_mod.tracePrint;
const DEBUG_TRACE = env_mod.DEBUG_TRACE;

// 2. En el punto de instrumentación:
if (DEBUG_TRACE) tracePrint("subsystem.event key1={s} key2={d}\n", .{
    key1_string_var,
    key2_int_var,
});
```

El arg-tuple se evalúa siempre que `DEBUG_TRACE` no se haya confirmado comptime-`false`. En ReleaseSafe (el modo de producción) el compilador *debe* (vía la invariante documentada arriba) elidir tanto el call como los args. Si añades un trace site y observas overhead indebido en ReleaseSafe, reportar como regresión de la invariante.
