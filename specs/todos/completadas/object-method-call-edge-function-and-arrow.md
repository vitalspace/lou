# Object literal: function expression with non-trivial body as a property value

## status
✅ COMPLETADO — duplicado histórico del spec consolidado

## Resolución
Había dos causas independientes, ambas cerradas por el bundle
[object-method-call-edge-parser-fixes.md](./object-method-call-edge-parser-fixes.md):

1. **Key reservada:** `fn` es una keyword. El key-switch de
   `parseObjectLiteral` solo aceptaba `String/Identifier/Integer/Float`;
   se amplió vía `isPropertyName()`. Eso cerraba el repro
   `{ fn: function(a, b) { ... } }` y el caso mixto `fn` + `arrow`.
2. **Cuerpo no-bloque:** `parseFunctionDeclaration` también usaba
   `parseStatement` para cuerpos no-bloque. Se consolidó en
   `parseFunctionBody()` → `parseExpression`. Este subcase (`function() 1`)
   es inválido en ES y queda cubierto solo por parser unit tests.

## Verificación actual
- Repro `{ fn: function(a, b) { return a + b; } }` idéntico a Node (`3`).
- Caso mixto `{ fn: function(a, b) { ... }, arrow: (a, b) => a + b }`
  idéntico a Node (`3 7`).
- Ambos están ahora en `object-method-call-edge-cases.{js,lou}`.
- Parser unit test nuevo:
  `parse object literal - function expression block followed by arrow property`.
- `PASS=104 FAIL=0 SKIP=0` y `All 1130 tests passed.` al momento del cierre.

## Archivos relacionados
- `tests/compat/object-method-call-edge-cases.js`
- `tests/compat/object-method-call-edge-cases.lou`
- `tests/compat/object-method-call.js`
- `tests/compat/object-method-call.lou`
- `src/parser.zig`
- [object-method-call-edge-parser-fixes.md](./object-method-call-edge-parser-fixes.md)
