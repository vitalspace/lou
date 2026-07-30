# Empty statement (;)

## status

completado

## Problema

El parser no manejaba el empty statement (`;` solo en una línea). ECMAScript permite `;` como statement vacío. Esto es útil como body de loops vacíos o como separador.

## Resumen de implementación

### Archivos modificados (5 source + 2 test)

1. **`src/ast.zig`** — Añadido `EmptyStatement` a `NodeType` enum y `EmptyStatement: void` al union `Node`. Agregado `freeAst` (no-op) y `printAst` (`"EmptyStatement"`).

2. **`src/parser.zig`** — Agregado caso `.Semicolon` en `parseStatement` que consume el token `;` y retorna un nodo `EmptyStatement`.

3. **`src/evaluator.zig`** — Agregado `.EmptyStatement => return .{ .void = {} }` en el switch de `evaluate`.

4. **`src/vm.zig`** — Agregado `.EmptyStatement => {},` en el switch `stmt` del compilador (antes del `else` fallthrough).

5. **`tests/compat/empty-statement.js` + `tests/compat/empty-statement.lou`** — Compat tests cubriendo: `;` solo, `if (true);`, `while (false);`, `for (;;);`, `;;;`, `if/else` con empty bodies, y bloques con empty statements mezclados.

### Verificación

- Unit tests: todos pasan
- Compat test: empty-statement.lou → MATCH (diff vacío contra Node.js)
- Suite compat: sin regresiones

## Código que antes fallaba y ahora funciona

```js
;                    // parsea como empty statement ✓
if (true);           // if con body vacío ✓
while (false);       // while con body vacío ✓
for (;;);            // infinite loop con body vacío ✓
;;;                  // tres empty statements ✓
if (true) ; else console.log("else");  // if/else con empty consequence ✓
```

## Edge cases encontrados durante implementación

### `;;;` y trailing semicolons en parseProgram

`parseProgram` consume un `;` trailing después de cada statement. Esto significa que `;;;` (sin el fix) produciría solo 2 `EmptyStatement` en lugar de 3 (el primer `;` → EmptyStatement, segundo `;` → consumido por parseProgram como trailing, tercer `;` → EmptyStatement). 

Con el fix actual esto funciona correctamente porque `parseStatement` ya consume el `;` en el caso `.Semicolon`, y cuando parseProgram verifica `if (current_token == .Semicolon)` después, el siguiente token ya es el próximo `;` (o EOF).

**Resultado:** Compat test MATCH — `;;;` imprime "after empties" sin errores, igual que Node.
