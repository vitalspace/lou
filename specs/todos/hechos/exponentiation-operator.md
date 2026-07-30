# Operador de exponenciación (`**`)

## status

pendiente (drift corrected 2026-06-29; previously falsely marked COMPLETADO)

`tests/compat/exponentiation-operator.lou` currently FAILs per the compat baseline (30 PASS / 50 FAIL / 1 SKIP). The spec body's `Estado del test` claim was based on an earlier run; the current compat baseline shows the test FAILing. Reverted status to reflect open follow-up work.

## Problema (resuelto)
El operador `**` (exponenciación) y `**=` (asignación de exponenciación) ahora están implementados. Compat test pasa byte-idéntico contra Node.

## Resumen de implementación

1. **`src/lexer.zig`** — Añadido el token `PowerAssign` al enum `TokenType` (después de `ModuloAssign`). El handler de `*` ahora reconoce `**=` antes que `**` antes que `*=` antes que `*` (longest-match-first). Unit test añadido.

2. **`src/ast.zig`** — Añadido `.PowerAssign` al mapping de precedencia `.Assign`, junto a `PlusAssign`. Esto hace que `x **= 5` parsee como `BinaryExpression(Identifier(x), .PowerAssign, IntegerLiteral(5))` dentro del flujo existente de `parseStatement` para Identifier (peek_token != `.Assign`/`.Colon`/`.Dot`/`.LBracket` → cae a `parseCommaExpression`).

3. **`src/parser.zig`** — En el loop de `parsePrecedece`, special-case `.Exponent` para recursionar con `.Product` (un nivel bajo `.Highest`). Esto convierte el Pratt parsing left-associative estándar a right-associative para `**` per ES2016 (`a ** b ** c → a ** (b ** c)`).
   - Trace `2 ** 3 ** 2`: outer→parse 2, consume `**`, recurse con `.Product` → inner parse 3, consume `**`, recurse con `.Product` → parse 2, returns 2. Inner build `BE(3,**2)`, returns. Outer build `BE(2,**, BE(3,**2))`. RIGHT-ASSOC ✓.
   - Trace `2 * 3 ** 4`: precedence se mantiene intacto para otros operadores. ✓
   
   **ES2016 Annex C** — `(-x)` y otros unary prefixes directamente antes de `**` son SyntaxError (por ej. `-2 ** 2`). Añadido:
   - Campo `last_was_unary_prefix: bool = false` en Parser struct.
   - En `parsePrecedece`: reset a `false`, captura en local `direct_unary = this.last_was_unary_prefix` **inmediatamente** después de que `parsePrimary` retorne, reset de nuevo a `false`, y chequea `direct_unary && .Exponent → error.UnexpectedToken`.
   - En cada rama unary de `parsePrimary` (`.Minus`, `.Increment`, `.Decrement`, `.Not`, `.BitNot`, `.TypeOf`, `.Delete`): set `last_was_unary_prefix = true` **al final de cada path, justo antes de `return`**. Esto es crítico porque operandos recursivos (e.g. `-(...)`) pueden ser procesados por parsePrecedece internamente que resetean el flag; settearlo al final wins.
   - Unit tests añadidos en `src/parser.zig` cubriendo: right-associativity, `**=`, rejection of `-2 ** 2`/`--x ** 2`, acceptance of `(-2) ** 2`/`2 ** -2`.

4. **`src/evaluator.zig`** — El handler `.Exponent` (que ya existía para BigInt^BigInt) fue reescrito completamente:
   - `integer^integer` con resultado que cabe en `i64` → retorna `Value{ .integer = ... }` (preserva formato de print Node-style "8" en lugar de "8.0").
   - Exponente negativo integer (e.g. `2 ** -1`) → retorna `Value{ .float = ... }` via `std.math.pow` (antes fallaba con `OutOfMemory`).
   - Exponente fraccional o mixed (e.g. `2 ** 0.5`, `4 ** -0.5`) → retorna float.
   - IEEE 754: `0 ** 0 = 1`, `1 ** NaN = NaN`, `NaN ** 0 = 1` directamente via `std.math.pow`.
   - `.PowerAssign` adicionado al grupo compound-assign con simetría, incluyendo integer^integer fitting-in-i64 + float fallback.

5. **`src/vm.zig`** — `.Exponent` y `.PowerAssign` BinarioExpresiones se delegan via `eval_node` al AST evaluator (donde reside la lógica BigInt-aware). Comentario añad documentando el rationale.

6. **`tests/compat/exponentiation-operator.{js,lou}`** — Nuevo compat test. Output byte-idéntico a Node. Diff vacío.

## Estado del test (auto 2026-06-23)

- Compat test match: `exponentiation-operator.lou` (EXACT)
- Test status: **PASS**
- Diff: empty (Lou output == Node output). Sections:
  - Basic integer powers (8 cases)
  - Right-associative chains `2 ** 3 ** 2` y `2 ** 2 ** 3`
  - Exponentes negativos y fraccionales (`2 ** -1`, `4 ** -0.5`, `2.5 ** 2`)
  - Float inputs (`2.5 ** 2.0`, `0.5 ** 2`)
  - Variables (`base ** exp`)
  - Precedencia mixta con `*` (`2 * 3 ** 2 = 18`, `3 ** 2 * 2 = 18` per ES)
  - Right-side unary minus (`2 ** -2 = 0.25`)
  - Compound assign (`a **= 2`, `b **= 0`, `c **= 3`, cadena `d **= 0.5; d **= 3`)

## Edge cases verificados manualmente

| Caso | Lou | Node |
|------|-----|------|
| `-2 ** 2` | error.UnexpectedToken | SyntaxError |
| `(-2) ** 2` | 4 | 4 |
| `-((2)) ** 2` | error.UnexpectedToken | SyntaxError |
| `!x ** 2` (parser) | error.UnexpectedToken | SyntaxError |
| `2 ** -2` | 0.25 | 0.25 |
| `2 ** 3 ** 2` | 512 (right-assoc) | 512 (right-assoc) |
| `--x ** 2` | error.UnexpectedToken | SyntaxError |

## pendiente (out of scope, no relacionado)

- `NaN` y `Infinity` no están definidos como globals en el Environment (`env.values`). Tests que los usen fallan con `UndefinedVariable`. Cubrir en spec separado `globals-nan-infinity.md`.
- `obj.x **= y` (compound assign con MemberAccess LHS) — el parser actual solo procesa `.Assign` con member access en `parseStatement`. Fuera de scope; el spec solo lista Identifier LHS.
- `void` keyword como unary operator — el lexer no emite `.Void` token. Fuera de scope.

## pendiente (testing)

- (ninguno — compat pasa, edge cases verificados, unit tests añadidos en lexer y parser)
