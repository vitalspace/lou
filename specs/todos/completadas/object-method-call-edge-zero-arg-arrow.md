# Object literal: zero-arg arrow with literal body, then another property

## status
✅ COMPLETADO — duplicado histórico del spec consolidado

## Resolución
El bug ya estaba corregido por el bundle consolidado
[object-method-call-edge-parser-fixes.md](./object-method-call-edge-parser-fixes.md).

`parseArrowFunction` usaba `parseStatement` para cuerpos no-bloque. Ese
camino terminaba en `parseCommaExpression`, que consumía la coma del
object literal y dejaba `current_token` en el `:` de la propiedad
siguiente. La consolidación en `parseFunctionBody()` hace que el cuerpo
no-bloque use `parseExpression`, que respeta la coma del caller.

## Verificación actual
- Repro `{ f: () => 99, g: 1 }` idéntico a Node (`99 1`).
- Cubierto por subcase A en `object-method-call-edge-cases.{js,lou}`.
- `PASS=104 FAIL=0 SKIP=0` y `All 1130 tests passed.` al momento del cierre.

## Archivos relacionados
- `tests/compat/object-method-call-edge-cases.js`
- `tests/compat/object-method-call-edge-cases.lou`
- `tests/compat/object-method-call.js`
- `tests/compat/object-method-call.lou`
- `src/parser.zig`
- [object-method-call-edge-parser-fixes.md](./object-method-call-edge-parser-fixes.md)
