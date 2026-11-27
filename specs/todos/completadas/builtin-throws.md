# Builtins: propagación de throws

## status

**completada** — implementada (compat: 90 PASS / 0 FAIL / 0 SKIP,
2026-11-27). `tests/compat/builtin-throws.lou` PASS.

## Problema

Los callbacks de iteración se ejecutaban en un `Environment` hijo y, si
lanzaban `throw`, el builtin se lo tragaba: el `catch` exterior nunca se
ejecutaba.

```js
try { [1].forEach(function () { throw new Error("x"); }); }
catch (e) { console.log("caught", e.message); }
// Node: caught x     Lou: no imprime nada
```

## Implementación

### `src/builtins/callbacks.zig` (nuevo)

- `propagateThrow(func_env, env)`: si el entorno del callback tiene
  `throw_hit`, copia `throw_value` al entorno llamador y devuelve true.
  El call site retorna inmediatamente y el `throw` sigue por la VM
  (`deliverBuiltinThrow`) o por el evaluador (`error.Thrown`).

### Builtins con callbacks

- `array/{forEach,map,filter,reduce,reduceRight,some,every,find,findIndex,
  findLast,findLastIndex,flatMap,from}.zig`: chequeo tras cada `evaluate`.
- `array/{sort,toSorted}.zig`: chequeo tras el comparador.
- `map/{map,forEach}.zig`, `set/{set,forEach}.zig`: mismo chequeo.
- `map/forEach.zig` y `set/forEach.zig` aceptan `.closure`, `.function` y
  nombre de función, e inicializan con `initCallable` para conservar el
  ámbito capturado.

### `src/evaluator.zig`

- Las llamadas a métodos builtin (`MethodCall`) comprueban `env.throw_hit`
  antes de devolver el valor, igual que `FunctionCall`/`NewExpression`.

## Verificación

- Fixture `builtin-throws` con forEach/map/filter/reduce/some/every/find,
  `Map.forEach`, `Set.forEach` y comparador de `sort`.
- `zig test src/main.zig` — 1,078 tests; `src/evaluator.zig` — 1,064.
