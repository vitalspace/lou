# Object literal: parenthesized single-arg arrow, then another property

## status
✅ COMPLETADO — duplicado histórico del spec consolidado

## Resolución
Misma causa raíz y mismo fix que el caso zero-arg: el cuerpo no-bloque
de `parseArrowFunction` pasaba por `parseStatement` →
`parseCommaExpression`, que se comía la coma entre propiedades. El helper
consolidado `parseFunctionBody()` usa `parseExpression` y preserva el
delimitador del object literal.

## Verificación actual
- Repro `{ singleArrow: (x) => x * 3, other: 2 }` idéntico a Node (`12 2`).
- Cubierto por subcase B en `object-method-call-edge-cases.{js,lou}`.
- `PASS=104 FAIL=0 SKIP=0` y `All 1130 tests passed.` al momento del cierre.

## Archivos relacionados
- `tests/compat/object-method-call-edge-cases.js`
- `tests/compat/object-method-call-edge-cases.lou`
- `tests/compat/object-method-call.js`
- `tests/compat/object-method-call.lou`
- `src/parser.zig`
- [object-method-call-edge-parser-fixes.md](./object-method-call-edge-parser-fixes.md)
