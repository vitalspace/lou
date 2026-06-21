# Generators (`function*` y `yield`) — COMPLETADO ✅

## Estado (Auditoría 2026-05-28)

### Implementado ✅
- Parser: `function*`, `yield`, `yield*` — ✅
- Evaluador: `GeneratorDeclaration`, `YieldExpression`, `evaluateGeneratorNext` — ✅
- VM: fallback al evaluador para generators — ✅
- `console.log` output: match Node/Bun — ✅ (test-generators.js)
- `test-generators.js` corre completamente con Lou — ✅
- `for...of` con generators — ✅
- `yield*` delegación (generator, array, string, iterator) — ✅
- Spread `[...gen()]` y `fn(...gen())` — ✅
- `yield*` con strings — ✅
- Spread con `.iterator` (ArrayIterator) — ✅
- Validación completa de spec: 43 tests, 0 failures — ✅ (specs/todos/generators.md)
- Limpieza de memoria (generator + environment) — ✅ Environment.deinit() promueve objetos al outer. Generators trackeados en `env.generators`. Bugfix: orden de cleanup en Environment.deinit() (generators antes que arrays/objects).
- Sin memory leaks — ✅ Fix: `while (self.generators.pop())` en vez de `for (self.generators.items)` para evitar stale slice cuando gen_env.deinit() promueve generadores internos durante la limpieza raíz (`src/environment.zig:252`).

### Implementado ✅ (Nuevo en esta sesión)
- `.return()` / `.throw()` en generators — ✅ `evaluateGeneratorReturn` / `evaluateGeneratorThrow` en `src/evaluator.zig`, dispatch en MethodCall handler (ambas ramas), VM.
- `gen[Symbol.iterator]` devuelve el generator — ✅ ArrayIndex handler devuelve `array_val` para `@@iterator`. `callFunctionValue` + `DirectCall` devuelven el generator.
- `valuesEqual` para `.generator` — ✅ comparación por puntero (antes siempre `false`).
- `yield*` con objetos que implementan `@@iterator` — ✅ switch en `YieldExpression` añade caso `.js_object`; estado persistente en `env.yield_star_js_iterator`; handler delega iteración vía `.next()` del objeto.

### No implementado ❌
- (ninguno — todo lo listado está implementado)

## Referencia

- `src/parser.zig` — parsing de `function*` y `yield`
- `src/ast.zig` — nodo `GeneratorDeclaration`, `YieldExpression`
- `src/evaluator.zig` — evaluación de generators con suspensión (`evaluateGeneratorNext`)
- `src/evaluator.zig` — Spread con generators: `evaluateArgs` y `ArrayLiteral`
- `src/environment.zig` — `yield_star_*` fields, orden de deinit
- `src/vm.zig` — fallback al evaluador para generators
- `src/types/runtime.zig` — `GeneratorObject` struct
- `js/test-generators.js` — tests básicos de generators
- `js/test-generators-memory.js` — tests de limpieza de memoria

## Verificación

```js
function* counter() {
  yield 1;
  yield 2;
  yield 3;
}

var gen = counter();
console.log(gen.next()); // { value: 1, done: false }  ✅
console.log(gen.next()); // { value: 2, done: false }  ✅
console.log(gen.next()); // { value: 3, done: false }  ✅
console.log(gen.next()); // { value: undefined, done: true }  ✅
```

### Tests nuevos

```js
// for...of con generators
function* range(start, end) {
  while (start < end) { yield start; start = start + 1; }
}
var result = [];
for (const x of range(0, 5)) result.push(x);
// result = [0, 1, 2, 3, 4]  ✅

// Spread con generators
var arr = [...range(0, 3)];
// arr = [0, 1, 2]  ✅

// yield* con generator
function* inner() { yield 1; yield 2; }
function* outer() { yield* inner(); yield 3; }
// outer() yields 1, 2, 3  ✅

// yield* con array
function* fromArr() { yield* [10, 20]; }
// fromArr() yields 10, 20  ✅

// yield* con string
function* fromStr() { yield* "AB"; }
// fromStr() yields "A", "B"  ✅
```

## Tests

- `js/test-generators.js` — tests funcionales básicos
- `js/test-generators-memory.js` — tests de memoria (creación masiva, abandoned, nested)
