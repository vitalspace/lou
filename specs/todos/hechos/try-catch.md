# try/catch

## status
IMPLEMENTADO (2026-06-28)

## Problema (resuelto)

El evaluador de `TryCatchFinally` tenía dos bugs semánticos:
1. **Errores en catch se tragaban**: `else |_| {}` silenciosamente ignoraba errores Zig que ocurrían dentro del bloque catch.
2. **Finally no ejecutaba antes de propagar errores del catch**: Si el bloque catch lanzaba un error, el finally se ejecutaba después pero el error del catch se perdía.

## Resumen de implementación

**Infraestructura ya existente** (no se modificó):
- Lexer: tokens `.Try`, `.Catch`, `.Finally`, `.Throw`
- AST: nodos `TryCatchFinally` y `ThrowStatement`
- Parser: `parseTryStatement` y `parseThrowStatement`
- VM: opcodes `throw_stmt`, `set_handler`, `clear_handler`, `save_error`, `throw_rethrow` con stack de exception handlers
- Environment: campos `throw_hit` y `throw_value`

### Cambios

1. **`src/evaluator.zig`** — Fix en el handler `.TryCatchFinally`:
   - **Bug 1 (catch errors swallowed)**: Cambiado `else |_| {}` → `else |catch_err| { ... }` para capturar errores del bloque catch.
   - **Bug 2 (finally before error propagation)**: El finally ahora se evalúa DENTRO del `else |catch_err|` antes de propagar el error, garantizando que finally siempre ejecuta incluso si catch lanza.
   - **Verificación de throw_hit después de finally**: En todos los paths (catch-success, catch-throw, no-catch), se verifica `env.throw_hit` después del finally para que throws en finally tengan precedencia.

### Limitación conocida

**Return en try + finally**: Si un `return` ocurre dentro del try body (vía BlockStatement), el finally no se ejecuta antes del return. Esto requiere cambios en cómo `BlockStatement` maneja `ReturnStatement` (actualmente hace shortcut sin setear `return_hit`). El camino directo por `ReturnStatement` (fuera de BlockStatement) sí setea `return_hit`.

## Tests

- **`tests/compat/try-catch.{lou,js}`** — 6 casos de prueba: basic try-catch, try-finally, try-catch-finally, catch re-throw con finally, nested try-catch, finally con throw propagation. PASS (diff vacío contra Node.js).

## Verificación

```bash
./zig-out/bin/lou run tests/compat/try-catch.lou
diff <(./zig-out/bin/lou run tests/compat/try-catch.lou 2>&1) \
     <(node tests/compat/try-catch.js 2>&1)
```

Diff vacío → PASS.
