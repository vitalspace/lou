# Object Literal — Reserved Keywords as Property Keys

## status
completado (2026-06-29, parser fix landed; commit pending)

## Problema

`parseObjectLiteral`'s property-name switch only accepts `.String / .Identifier / .Integer / .Float`. Using any reserved keyword (`fn`, `return`, `if`, `else`, `null`, `true`, `false`, `while`, `for`, …) as the key in an object literal is rejected with `error.ExpectedPropertyName` at `parser.zig:792`.

This frustrates running the original object-method-call repro against modern JS idioms:

```js
const o = { fn: 1 };          // error: ExpectedPropertyName
const o = { return: 1 };      // error: ExpectedPropertyName
const o = { if: 2, else: 3 }; // error: ExpectedPropertyName
const o = { true: 1, false: 0, null: 3, undefined: 4 }; // error: ExpectedPropertyName
```

ES2015 §13.2.5.4 (`LiteralPropertyName`) explicitly allows `IdentifierName | StringLiteral | NumericLiteral`, and §11.6.1 `IdentifierName` includes reserved words. So Lou's existing pre-fix behavior was non-conformant.

## Contexto

This spec is subcase **C-2** of the original object-method-call bug surfaced by the bisect of `tests/compat/object-method-call.lou`. The other two subcases — zero-arg-arrow (`ExpectedCommaOrRBrace` at `parser.zig:806`) and parens-single-arg-arrow (same line, same error) — were both rooted in `parseStatement` → `parseCommaExpression`'s greedy comma consumption and were fixed by switching the body parser to `parseExpression` in `parseArrowFunction` and `parseFunctionDeclaration`.

C-2 is fundamentally different: it lives in **`parseObjectLiteral`** (the key-selection switch), not in arrow or function body parsing. The original bug-3 repro from the consolidated spec — `const o = { fn: function(...) { ... } }` — actually trips the key switch first (the `fn` is the property name), not the function body parser. The body-parser fix in C-1 covered the *non-block + comma* path; the key-switch fix in C-2 covers the *reserved-keyword-as-key* path. Both are needed.

The same fix elsewhere in the codebase: `parseMemberAccessOrCall` already gates property-name recognition behind `isPropertyName(tok_type)` at `parser.zig:32`. The helper lists `.Identifier + .Const + .Var + .Let + .Null + .Undefined + .True + .False + .Fn + .Return + .If + .Else + .For + .While + .In + .Break + .Continue + .Switch + .Case + .Default + .Match + .Import + .From + .As + .Export + .TypeOf` and is the single source of truth for "this token can be a property name in member-access / object-literal / destructuring contexts."

The cleanest fix is therefore to delegate the key switch to `isPropertyName()` for the Identifier-or-keyword branch, keeping `.String / .Integer / .Float` explicit because their semantics are "use the literal as the key" (e.g. `{ "fn": 1 }` vs `{ fn: 1 }` forcii to give the same key string `"fn"`).

## Baseline (qué existe ya)

- `isPropertyName(tok_type)` defined at `src/parser.zig:32` (used by `parseMemberAccessOrCall` at `parser.zig:1343`).
- Lexer populates `Token.literal` for keyword tokens with the source word (`"fn"`, `"return"`, `"true"`, `"null"`, …). Verified indirectly by:
  - `parseConstantDeclaration` (`src/parser.zig:224`) reads `.literal` after `.Const`.
  - `parseVariableDeclaration`, `parseLetDeclaration`, `parseForLoop`'s `for...of/from/in` paths read `.literal` after `.Var / .Let / .Const / .Identifier`.
  - `parseImportStatement` (`src/parser.zig`) reads `.literal` for default-binding after `.Identifier`.
- ES2015 §13.2.5 (`PropertyDefinition`) and §13.2.5.4 (`LiteralPropertyName`) — grammar allows IdentifierName (which includes reserved words per §11.6.1).
- Downstream: `ast.Property.key` flows into `getMember` / `setMember` / `getPropertyByPath` paths in `evaluator.zig` and `vm.zig`. The key string is consumed as-is — no special handling for keywords vs. plain identifiers.

## Quick verify (estado actual)

```bash
# All three intended repro cases (post-fix output matches node):
printf 'const o = { fn: 1 }; console.log(o.fn);\n' > /tmp/r1.lou
/home/lou/zig-out/bin/lou run /tmp/r1.lou
# → 1

printf 'const o = { return: 1 }; console.log(o.return);\n' > /tmp/r2.lou
/home/lou/zig-out/bin/lou run /tmp/r2.lou
# → 1

printf 'const o = { if: 2, else: 3 }; console.log(o.if, o.else);\n' > /tmp/r3.lou
/home/lou/zig-out/bin/lou run /tmp/r3.lou
# → 2 3

# Sanity: the literal-key form still works (`{ "fn": 1 }` ≡ `{ fn: 1 }`):
printf 'const a = { fn: 1 }; const b = { "fn": 1 }; console.log(a.fn === b["fn"]);\n' > /tmp/eq.lou
/home/lou/zig-out/bin/lou run /tmp/eq.lou
# → true
```

All four should produce the expected output.

## Patrones a seguir

- `src/parser.zig:32` — `isPropertyName` helper (single source of truth).
- `src/parser.zig:1343` — `parseMemberAccessOrCall` already uses `isPropertyName` after `consume '.'`.
- `src/parser.zig:32-49` — list of IdentifierName tokens. If a future keyword is added to the lexer, add it here too.
- ES2015 §13.2.5 / §13.2.5.4 (PropertyDefinition / LiteralPropertyName).
- ES2015 §11.6.1 IdentifierName (specifies that reserved words are allowed as IdentifierName, unlike Identifier).

## Gotchas

- The fix is **strictly widening**: only tokens added to the accepted set are reserved keywords listed in `isPropertyName`. No previously-accepted tokens are removed.
- The `else => blk:` switch arm reads `this.current_token.literal` after `isPropertyName` returns true. This relies on the lexer's contract that `.literal` is the source word for keyword tokens. The convention is established site-wide (see Baseline) but a future lexer refactor that drops `literal` for keywords would silently break this — locked in by unit test "parse object literal - true/false/null/undefined as keys".
- The numeric path (`.Integer / .Float` as keys, e.g. `{ 1: "x" }`) is unchanged. `isPropertyName` doesn't include them; they stay in the explicit switch cases.
- ES2015 also allows **computed property names** (`{ [expr]: value }`) which the current parser does NOT support. That's a pre-existing limitation, not in scope for this spec. The key switch's `else` branch rejects `.LBracket` → falls through to `error.ExpectedPropertyName`.
- ES6 method shorthand (`{ foo() {} }`) and `get/set` accessors (`{ get foo() {} }`) — also not supported by this parser; pre-existing limitation (would need additional handling outside the key switch).
- Quoted-string and bare-keyword forms produce semantically identical keys (`{ "fn": 1 }` ≡ `{ fn: 1 }`) — locked in by the existing implicit coverage.

## Código que falla (pre-fix)

```js
const o1 = { fn: 1 };                                   // ExpectedPropertyName at parser.zig:792
const o2 = { return: 1 };                               // ExpectedPropertyName
const o3 = { if: 2, else: 3 };                          // ExpectedPropertyName
const o4 = { true: 1, false: 0, null: 3, undefined: 4 };// ExpectedPropertyName
const o5 = { while: "loop" };                           // ExpectedPropertyName
const o6 = { class: 0 };                                // ExpectedPropertyName (would error on IdentifierName canonicalization; future spec)
const o7 = { [computed]: 1 };                           // ExpectedPropertyName (computed keys not supported; pre-existing)
```

## Implementación aplicada (2026-06-29)

### Diff

`src/parser.zig`, in `parseObjectLiteral` (around line 79x, just after the spread-property block):

```zig
// ES2015 §13.2.5.4: a property name in an object literal may be
// an IdentifierName (which includes reserved words like `fn`,
// `return`, `if`, ...), a string literal, or a numeric literal.
// `isPropertyName(tok_type)` already covers IdentifierName (we
// use it for member-access keys too), so we delegate to it for
// the Identifier-or-keyword branch. The String / Integer / Float
// cases stay explicit because their semantics are "use the
// literal as the key".
const key = switch (this.current_token.type) {
    .String, .Integer, .Float => this.current_token.literal,
    else => blk: {
        if (!isPropertyName(this.current_token.type)) return error.ExpectedPropertyName;
        break :blk this.current_token.literal;
    },
};
```

Before the fix (rejected everything else):

```zig
const key = switch (this.current_token.type) {
    .String => this.current_token.literal,
    .Identifier => this.current_token.literal,
    .Integer => this.current_token.literal,
    .Float => this.current_token.literal,
    else => return error.ExpectedPropertyName,
};
```

After the fix, `.Identifier` is folded into the `else` arm via `isPropertyName` (it returns `true` for `.Identifier`), so behavior on plain identifiers is unchanged.

### Why `blk`-switch with else arm (not a flat if/else)

The two branches do the same thing (return `tok.literal`) but conceptually represent two production rules from the ES grammar:

- `.String / .Integer / .Float` ⇒ value-as-literal: `LiteralPropertyName → StringLiteral | NumericLiteral`.
- `Identifier / reserved keyword` ⇒ IdentifierName: `LiteralPropertyName → IdentifierName`.

A flat `if (tok is one of {String, Integer, Float} or isPropertyName(tok)) tok.literal else error` would conflate these categories. The `switch` makes the production-rule separation visible without adding verbosity.

### Unit tests added in `src/parser.zig`

```zig
test "parse object literal with reserved-keyword key - fn"
test "parse object literal with reserved-keyword key - return"
test "parse object literal with multiple reserved-keyword keys"
test "parse object literal regression - plain identifier keys still work"
test "parse object literal - true/false/null/undefined as keys"
test "parse object literal - non-keyword token still errors"
```

Six new tests cover:

1. Single `fn` key (the original repro).
2. Single `return` keyword as key.
3. Multi-keyword with comma-delimited list (`if, else`).
4. Regression guard for pre-existing identifier / string / integer keys — proves we didn't accidentally widen past reserved words.
5. Lexer-literal-population contract — `true / false / null / undefined` all emit sensible string literals via `Token.literal`.
6. Negative test — `({ ;: 1 })` still errors with `ExpectedPropertyName` (bounds guard).

## Tests

### Compat

The previously-named `tests/compat/object-method-call.{js,lou}` is unaffected by this edge case (arrow-form, no reserved-keyword keys). A new compat test isn't strictly required; the latency surface is parser-only and unit tests suffice.

### Unit

Six tests listed above, all in `src/parser.zig` "Tests" section at the end of file.

## Verificación

```bash
cd /home/lou && zig build 2>&1 | tail -5
zig build test 2>&1 | grep -E '(reserved-keyword|regression|ExpectedPropertyName|FAIL|ok)' | head -20

# Three intended repro cases — post-fix:
for prog in 'const o = { fn: 1 }; console.log(o.fn);' \
            'const o = { return: 1 }; console.log(o.return);' \
            'const o = { if: 2, else: 3 }; console.log(o.if, o.else);'; do
  printf '%s' "$prog" > /tmp/r.lou
  /home/lou/zig-out/bin/lou run /tmp/r.lou
done

# Negative bound — pre-fix and post-fix behavior unchanged:
printf '({ ;: 1 })' > /tmp/n.lou
/home/lou/zig-out/bin/lou run /tmp/n.lou 2>&1 | head -3  # ExpectedPropertyName
```

## pendiente

- (none — fix landed in working tree; commit pending. Tests added and verified to pass.)
- Cross-link to consolidated spec: `object-method-call-edge-parser-fixes.md`.
- Sibling specs:
  - `object-method-call-edge-zero-arg-arrow.md` (closed: parseStatement → parseExpression in parseArrowFunction)
  - `object-method-call-edge-parens-single-arrow.md` (closed: same path)
  - `object-method-call-edge-function-and-arrow.md` (closed: same path on parseFunctionDeclaration)
  - `object-method-call-edge-reserved-keyword-key.md` (this spec, fixed in parseObjectLiteral key switch)

## Out of scope (deferred)

- **Computed property names**: `{ [expr]: value }` is ES2015 PropertyDefinition. Currently rejected by the key switch (`else` falls through to `ExpectedPropertyName`). Would require a separate `.LBracket` arm before the key switch, building a `Property.key_expr` AST node. Existing AST already has the `key_expr` field on `Property`, but the parser doesn't emit it.
- **ES6 method shorthand**: `{ foo() {} }`. Distinct from key:value because no colon. Would require a separate `.LParen` arm after the key.
- **`get` / `set` accessors**: `{ get foo() {} }`. Same as method shorthand plus a getter/setter keyword detection.
- **String/numeric key canonicalization**: e.g. `{ 1: "x" }` should be equivalent to `{ "1": "x" }`. Behavior unchanged between pre-fix and post-fix; the explicit `.Integer / .Float` cases preserve the literal as-is.

## Cross-references

- `specs/todos/pendientes/object-method-call.md` — parent spec
- `specs/todos/pendientes/object-method-call-edge-parser-fixes.md` — consolidated follow-up
- ES2015 §13.2.5 / §13.2.5.4 (PropertyDefinition / LiteralPropertyName)
- ES2015 §11.6.1 (IdentifierName — reserved words allowed)
- `src/parser.zig:32` — `isPropertyName` helper
- `src/parser.zig:1343` — `parseMemberAccessOrCall` existing usage of `isPropertyName` for member-access keys
