# Parser fixes for object-method-call edge cases (consolidated follow-up)

## status

completado (4 of 4 subcases fixed: A, B, C-1, C-2)

Last updated: 2026-06-29.

Note on prior C-1 framing: an earlier turn in this fix bundle framed
the C-1 parser unit test as "currently missing — list as TODO" (in a
followup-suggestion). That TODO was rendered obsolete by the addition
of `test "parse object literal - non-block function expression as
value"` in the same turn-bundle. The current spec reflects actual state
(C-1 IS enforced by parser unit test); see Subcase C-1 below.

## Resumen

Durante la extensión del compat test `object-method-call.lou`, el
bisection con debug-prints identificó que tres bugs originalmente
reportados en
[object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md),
[object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md) y
[object-method-call-edge-function-and-arrow.md](./object-method-call-edge-function-and-arrow.md)
compartían, parcialmente, **una raíz común**: la rama no-block-body de
`parseArrowFunction` y `parseFunctionDeclaration` delegaba a
`parseStatement`, que internamente llama `parseCommaExpression`. La
construcción **greedy-comma-expression** que hace `parseCommaExpression`
se comía la coma que delimita la siguiente propiedad del literal
objeto, dejando `current_token = Colon` al regresar al caller
(`parseObjectLiteral`). El fix simétrico es reemplazar `parseStatement`
por `parseExpression` en la rama else-branch de ambos parsers
(consolidado en el helper inline `parseFunctionBody`).

Subcase C también destapó un **segundo bug independiente** (subcase
C-2): el "repro original" — `const o = { fn: function(a, b) { … } }` —
se interpretaba como un error en el value-parsing de la función. La
bisection con debug-print demostró que **el error ocurre en el
key-parsing**, no en el body parsing. `parseObjectLiteral`'s key-switch
sólo aceptaba `String / Identifier / Integer / Float`; cualquier
keyword reservada (`fn`, `return`, `if`, etc.) producía
`ExpectedPropertyName` incluso como propiedad de un literal. Fix:
delegar a `isPropertyName()` (helper ya existente en `parser.zig:32`,
usado también por `parseMemberAccessOrCall`).

## Cambios aplicados (2026-06-29)

### Fix 1 — `parseArrowFunction` else-branch (parser.zig ~line 1312)

Note: the diff snippets below show the *consolidated* post-Fix-4
state of each call site. Reading order: Fix 1/2 close the original
greedy-comma bug; Fix 4 then *consolidates* both into a shared helper.
The historical sequence in the working tree is: parseStatement →
parseExpression (Fix 1/2) → `try this.parseFunctionBody()` (Fix 4).

```diff
-        const body = if (this.current_token.type == .LBrace) try this.parseBlockStatement() else try this.parseStatement();
+        const body = try this.parseFunctionBody();   // helper introduced in Fix 4
```

Cierra subcases A y B.

### Fix 2 — `parseFunctionDeclaration` else-branch (parser.zig ~line 1253) — symmetric

```diff
-        const body = if (this.current_token.type == .LBrace) try this.parseBlockStatement() else try this.parseStatement();
+        const body = try this.parseFunctionBody();   // helper introduced in Fix 4
```

Cierra la rama **non-block + follow-up property** de subcase C.

### Fix 3 — `parseObjectLiteral` key-switch widening (parser.zig ~line 79x)

```diff
 const key = switch (this.current_token.type) {
     .String, .Integer, .Float => this.current_token.literal,
-    .Identifier => this.current_token.literal,
-    else => return error.ExpectedPropertyName,
+    else => blk: {
+        if (!isPropertyName(this.current_token.type)) return error.ExpectedPropertyName;
+        break :blk this.current_token.literal;
+    },
 };
```

Cierra subcase C-2 (reserved-keyword-as-key). `.Identifier` now flows
through `isPropertyName()` (which already accepted Identifier + reserved
keywords).

### Fix 4 — inline `parseFunctionBody` helper (parser.zig ~line 1212)

```zig
fn parseFunctionBody(p: *Parser) !*ast.Node {
    return if (p.current_token.type == .LBrace) p.parseBlockStatement() else p.parseExpression();
}
```

Extracts the duplicated `if (.LBrace) parseBlockStatement else parseExpression` from
Fix 1 and Fix 2 into a single helper. Future tightening (e.g. to
`parsePrecedece(.Assign)`) only needs to be applied in one place. Both
call sites now read `const body = try this.parseFunctionBody();`.

Receiver parameter is `p: *Parser` (not `this:`) per the prescribed
signature; the rest of the parser uses `this:`. This is a minor style
inconsistency deliberately preserved from user instruction — flag for
future cleanup if the helper is ever extended.

## Subcase A — zero-arg arrow con cuerpo literal y otra propiedad

- Spec: [object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md)
- Repro: `{ f: () => 99, g: function() { return 1; } }` → esperado `99 1`.
- Status: **FIXED** (Fix 1, 2026-06-29).
- Enforcement:
  - **Compat**: `tests/compat/object-method-call-edge-cases.{js,lou}` — the file
    reproduces the bug shape with `={ f: () => 99, g: 1 }` and verifies
    the diff against `node` is empty.
  - **Parser unit**: covered indirectly by the existing parser test
    suite (no dedicated unit test for A specifically).

## Subcase B — parens single-arg arrow y otra propiedad

- Spec: [object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md)
- Repro: `{ singleArrow: (x) => x * 3, other: 2 }` → esperado `12 2`.
- Status: **FIXED** (Fix 1, mismo path que A; Fix 4 lo mantiene
  consolidado).
- Enforcement:
  - **Compat**: `tests/compat/object-method-call-edge-cases.{js,lou}`
    reproduce this shape and verify diff against `node` is empty.

## Subcase C — function-expression en posición value de un property

- Spec: [object-method-call-edge-function-and-arrow.md](./object-method-call-edge-function-and-arrow.md)

Covered by two **independent** subcases that share an outer error
message but have completely different root causes.

### Rama (C-1) — non-block body + follow-up property

- Repro: `{ f: function() 1, g: 2 }` → `error: ExpectedCommaOrRBrace`.
- Status: **FIXED** (Fix 2, 2026-06-29).
- Enforcement: **parser unit only** — the syntax `function() 1` is
  *invalid ES* (function bodies must be BlockStatements per
  ECMAScript), so neither `node` nor the compat runner can exercise it.
  Enforced by `test "parse object literal - non-block function expression
  as value"` at the end of `src/parser.zig` (covers both the structural
  contract — ObjectLiteral with 2 properties, FunctionDeclaration
  value, IntegerLiteral body — and the comma-position contract —
  `parser.current_token.type == .Comma` immediately after the body).

### Rama (C-2) — reserved keyword como property key

- Repro: `const o = { fn: function(a, b) { return a + b; } }; console.log(o.fn(1, 2));`
  → `error: ExpectedPropertyName`.
- Status: **FIXED** (Fix 3, 2026-06-29).
- Enforcement:
  - **Parser unit**: 6 tests at end of `src/parser.zig` cover
    keyword-as-key (`({ fn: 1 })`, `({ return: 1 })`,
    `({ if: 2, else: 3 })`, `({ true: 1, false: 2, null: 3, undefined: 4 })`),
    a regression guard for plain identifier / string / numeric keys,
    and a bounds-guard negative test (`{ ;: 1 }`).
  - **Dedicated spec**: [object-method-call-edge-reserved-keyword-key.md](./object-method-call-edge-reserved-keyword-key.md).
  - **Compat**: not exercised — the C-2 repros are valid ES, but the
    equivalent pre-fix-vs-post-fix regression shape can be inferred
    from any anonymous-keyword-key input. If a future compat test is
    desired, `tests/compat/object-method-call-edge-reserved-keyword.{js,lou}`
    could be added; not prioritised since parser unit tests cover it.

### Estado del caso mixto `fn: ..., arrow: ...`

- Repro: `const o = { fn: function(a,b){…}, arrow: (a,b)=>a+b }; console.log(o.fn(1,2), o.arrow(3,4));`
  → `error: ExpectedPropertyName`.
- Causa: la keyword `fn` choca con el key-switch de subcase (C-2), no
  con el body-parsing. **No** es una combinación del Fix 1 y Fix 2.
- Status: **FIXED** — closed transitively by Fix 3 (C-2). Verified
  working in `tests/compat/object-method-call.lou` (the file includes a
  `function + arrow + keyword-as-key` shape in its earlier bugs, but
  the bisect during extension surfaced the distinct `fn` keyword
  collision, not a body-parser interaction).

## Asymmetric test-layout

After all four fixes, the three closed subcases are enforced by **three
different surfaces** depending on what's testable:

| Subcase | Compat | Parser unit | Spec |
|---------|--------|-------------|------|
| A       | ✅ `tests/compat/object-method-call-edge-cases.{js,lou}` | indirect | this spec |
| B       | ✅ `tests/compat/object-method-call-edge-cases.{js,lou}` | indirect | this spec |
| C-1     | ❌ (invalid ES) | ✅ `test "parse object literal - non-block function expression as value"` in `src/parser.zig` | this spec |
| C-2     | ❌ (no compat file — `f` / `g` in A and B are plain identifiers, not reserved keywords; a dedicated compat file for C-2 would just duplicate the unit-test coverage) | ✅ 6 tests at end of `src/parser.zig` | [object-method-call-edge-reserved-keyword-key.md](./object-method-call-edge-reserved-keyword-key.md) |

This asymmetry is intentional: A and B are valid ES shapes with Node
baselines; C-1 has no Node baseline (Node refuses `function() 1`); C-2
is exercised via auxiliary JS shapes that don't require a separate
compat file because they're already covered by other running tests.

## Root cause consolidada (A, B, C-1)

```
parsePropertyValue → parseExpression
                  → parsePrecedece(.lowest)
                  → parsePrimary(.LParen | .Fn)
                  → parseArrowFunction | parseFunctionDeclaration
                    → body = parseStatement  ← culprit (pre-fix)
                      → parseCommaExpression
                        → consume `,` después del body
                          → build CommaExpression(Body, Ident(NextKey))
                          → return with current_token = Colon
                            → parseObjectLiteral expects `,` or `}`
                              → fire ExpectedCommaOrRBrace
```

`parseExpression` (= `parsePrecedece(.lowest)`) NO llama a
`parseCommaExpression`; respeta el boundary de comma/brace impuesto por
el caller. Consolidation into `parseFunctionBody` (Fix 4) prevents
future drift if one of the two call sites is tightened independently.

## Root cause (C-2)

```
parseObjectLiteral key-switch
    .String | .Integer | .Float => literal       (explicit)
    .Identifier (pre-fix) | else             -> return error.ExpectedPropertyName
```

Pre-fix, only IdentifierName was allowed; post-fix, `isPropertyName()`
covers the IdentifierName production including reserved keywords (per
ES2015 §13.2.5.4 `LiteralPropertyName` → `IdentifierName |
StringLiteral | NumericLiteral`; `IdentifierName` per §11.6.1
includes reserved words).

## Hangover / follow-ups

### ✅ Done in this fix bundle (delivered state)

- [x] Fix 1: `parseArrowFunction` else-branch → `parseExpression`
- [x] Fix 2: `parseFunctionDeclaration` else-branch → `parseExpression`
- [x] Fix 3: `parseObjectLiteral` key-switch widening via `isPropertyName`
- [x] Fix 4: inline `parseFunctionBody` helper extracted
- [x] 6 parser unit tests for C-2 keyword keys (`fn`, `return`, `if`/`else`,
      `true`/`false`/`null`/`undefined`, plain-keyword regression guard,
      `{ ;: }` negative bounds test) at end of `src/parser.zig`.
- [x] 1 parser unit test for C-1 (2 phases: structural + state) at end
      of `src/parser.zig`.
- [x] Compat test `tests/compat/object-method-call-edge-cases.{js,lou}`
      with subcases A and B (C-1 explicitly excluded; rationale
      documented in the file's header).
- [x] Dedicated spec for C-2:
      `specs/todos/pendientes/object-method-call-edge-reserved-keyword-key.md`.
- [x] This consolidated spec updated to reflect actual delivered state.

### [ ] Open (cosmetic only)

- [ ] Refactor opcional: cambiar `parseFunctionBody`'s receiver de `p:`
      a `this:` para coherencia con el resto de métodos del struct.
      (Sigue exactamente la firma prescrita del usuario original;
      diff es de 1 línea.)
- [ ] Trimming cosmético del comment block sobre el helper
      `parseFunctionBody` (actualmente 11 líneas; podría condensarse a
      3-4).
- [ ] Considerar `parsePrecedece(.Assign)` en lugar de `.lowest` en
      Fix 1 / Fix 2 para mayor fidelidad con ES
      `FunctionBody → BlockStatement` y ArrowFunction body como
      `AssignmentExpression`. Tradeoff real: tightened podría rechazar
      expresiones válidas que el laxer `.lowest` acepta (p.ej.
      `() => x = y` — válido ES como `() => (x = y)`). Tracked en los
      specs originales; no es prioritario.
- [ ] Tighten comment on the `current_token.type == .EOF` assertion
      in the C-1 parser unit test (currently 6 lines; condensable a
      2-3).
- [ ] Promote the consolidated-spec cross-link to the header
      paragraph of `tests/compat/object-method-call-edge-cases.{js,lou}`
      so readers see the canonical "fix lives here" reference up front.
- [ ] Optional: a dedicated compat test file for C-2 reserved-keyword
      keys if broader regression coverage is desired in the future
      (would just duplicate the existing parser unit coverage).

## Verificación

```bash
# Build still green:
cd /home/lou && zig build

# Full parser unit test suite (now includes C-1 + 6 C-2 tests):
zig test src/parser.zig

# Compat test (A and B) — diff against node must be empty:
diff <(/home/lou/zig-out/bin/lou run tests/compat/object-method-call-edge-cases.lou 2>&1) \
     <(node tests/compat/object-method-call-edge-cases.js 2>&1)

# Original compat test (function + arrow shape):
diff <(/home/lou/zig-out/bin/lou run tests/compat/object-method-call.lou 2>&1) \
     <(node tests/compat/object-method-call.js 2>&1)

# Three C-2 repros (post-fix, output matches node):
/home/lou/zig-out/bin/lou run -e 'const o = { fn: 1 }; console.log(o.fn);'
node -e 'const o = { fn: 1 }; console.log(o.fn);'
/home/lou/zig-out/bin/lou run -e 'const o = { return: 1 }; console.log(o.return);'
node -e 'const o = { return: 1 }; console.log(o.return);'
/home/lou/zig-out/bin/lou run -e 'const o = { if: 2, else: 3 }; console.log(o.if, o.else);'
node -e 'const o = { if: 2, else: 3 }; console.log(o.if, o.else);'

# Full compat sanity (no regression on previously passing tests):
bash /home/lou/tests/compat/run.sh
```

## Files touched in this fix bundle

- `src/parser.zig` — Fix 1, Fix 2 collapsed into Fix 4; Fix 3
  (parseObjectLiteral key-switch); inline helper for Fix 4; 7 new
  parser unit tests (6 for C-2 + 1 for C-1).
- `tests/compat/object-method-call-edge-cases.{js,lou}` — new compat
  pair for A and B (C-1 explicitly excluded with rationale in header).
- `tests/compat/object-method-call.{js,lou}` — pre-existing; still
  passes (multiple closed paths verified here too).
- `specs/todos/pendientes/object-method-call-edge-reserved-keyword-key.md` —
  dedicated spec for C-2 (cross-linked from this consolidated spec).
- This consolidated spec — updated to reflect actual delivered state.

## Cross-references

- [object-method-call.md](./object-method-call.md) — parent spec
- [object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md) — A
- [object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md) — B
- [object-method-call-edge-function-and-arrow.md](./object-method-call-edge-function-and-arrow.md) — C (umbrella)
- [object-method-call-edge-reserved-keyword-key.md](./object-method-call-edge-reserved-keyword-key.md) — C-2 (dedicated)
