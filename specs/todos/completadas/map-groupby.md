# Map.groupBy y Object.groupBy

## status

**COMPLETADO** — verificado 2026-11-26 (compat: 63 PASS / 22 FAIL / 1 SKIP)

`tests/compat/map-groupby.lou` pasa byte-identical. El fallo no estaba en
`groupBy` (que ya copiaba el throw del callback), sino en el puente entre el
protocolo de throws de los builtins y el intérprete VM.

```bash
diff <(./zig-out/bin/lou run tests/compat/map-groupby.lou) \
     <(node tests/compat/map-groupby.js) && echo OK
```

## Problema

Los builtins señalizan un throw de JS poniendo `env.throw_hit`/`throw_value`
(protocolo del evaluador), pero la VM ejecuta `try/catch` con su propia pila
`exception_handlers` y solo reacciona a `error.Thrown`. Los opcodes `.builtin`
y `.method_call` ignoraban `env.throw_hit`, así que el throw del callback se
descartaba y la ejecución seguía como si nada.

## Solución

- `VM.deliverBuiltinThrow()` (`src/vm.zig`): si `env.throw_hit`, toma
  `throw_value`, limpia el flag y salta al handler más cercano (restaura `sp`,
  empuja el error y fija `ip`); sin handler devuelve `error.Thrown`.
- `.builtin` y los 20 sitios `const r = md(...)` de `.method_call`: se pone
  `env.throw_hit = false` antes de invocar (descarta flags obsoletos de un
  `throwTypeError` ya capturado) y `if (try self.deliverBuiltinThrow()) continue;`
  después, descartando el resultado del builtin.

## Gotchas

- `Map.groupBy` y `Object.groupBy` ya propagaban desde el builtin
  (`func_env.throw_hit` → `env.throw_hit`); lo que faltaba era el puente VM.
- Los callbacks de `Array.prototype.forEach/map` y `Map.forEach` siguen sin
  propagar: esos builtins no copian el throw del entorno del callback. Ver
  `../pendientes/builtin-throws.md`.
- `BigInt("abc")` devuelve `undefined` en vez de lanzar `SyntaxError` (mismo
  spec pendiente).
- Los mensajes de error propios (`JSON.parse`, `TypeError`) aún no coinciden
  con Node; eso es el gap `json-parse`/`error-objects`.

## Tests

- `tests/compat/map-groupby.{js,lou}` (6 casos: Map/Object groupBy, claves
  null, callback con índice, throw propagado).
- `try { JSON.parse("{") } catch` a nivel top-level ya entra al catch.
