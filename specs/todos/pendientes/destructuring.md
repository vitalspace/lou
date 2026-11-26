# Destructuring

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

`tests/compat/destructuring.lou` sigue FAIL. Primera divergencia (línea 11), Lou vs Node:

```text
Lou : 0
Node: NaN
```

El default de patrón completo (`f4()` con `{x, y} = {}`) da `0` en vez de `NaN`: `undefined + undefined` se evalúa como `0`.

Estado de los 8 fixtures del área:

| Test file | Status |
|---|---|
| `tests/compat/destructuring.lou` | **FAIL** (línea 11: `0` vs `NaN`) |
| `tests/compat/destructuring-decl.lou` | PASS |
| `tests/compat/destructuring-assign.lou` | PASS |
| `tests/compat/destructuring-nested.lou` | PASS |
| `tests/compat/destructuring-nested-rest.lou` | **FAIL** (línea 1: `1` vs `NaN`) |
| `tests/compat/destructuring-array.lou` | PASS |
| `tests/compat/destructuring-for-of.lou` | PASS |
| `tests/compat/destructuring-for-in.lou` | PASS |

```bash
diff <(./zig-out/bin/lou run tests/compat/destructuring.lou) <(node tests/compat/destructuring.js)
```

## Resumen de implementación

**Strategy: Desugaring in the parser.** Instead of adding new AST nodes (`ArrayDestructuring`, `ObjectDestructuring`, `RestElement`) + new VM opcodes, the parser desugars destructuring into `BlockStatement` nodes containing `VariableDeclaration` + `Assignment` nodes with temp variables. This reuses the existing evaluator/VM paths with zero runtime changes.

### `src/parser.zig`

Key functions added:

- **`parseDestructuredDecl()`** — Entry point for `const/let/var [a, b] = expr` / `const/let/var {x, y} = expr`. Returns a `BlockStatement` containing `[temp_decl, binding1, binding2, ...]`.

- **`parseDestructuredPattern()`** — Recursive pattern parser. Handles:
  - **Array patterns**: positional access via `source[idx]`, elision (`,,`), rest (`...rest` via `source.slice(idx)`), nested patterns (`[[a, b], c]`), defaults (`a = default` via `??` operator)
  - **Object patterns**: property access via `source.prop_name`, shorthand (`{ x }`), rename (`{ name: n }`), rest (`{ ...rest }`), nested patterns (`{ a: { b, c } }`), defaults (`x = default`)
  - Accepts `decl_mode` boolean: when true emits `VariableDeclaration` nodes; when false emits `Assignment` nodes for assignment expressions.

- **`parseDestructuredAssign()`** — For bare `[a, b] = expr` in statement context. Also called from `parsePrimary()` for `[a, b] = expr` in expression context (with backtracking when `=` is absent → parse as array literal).

- **`parseParenthesizedDestructuredAssign()`** — For `({x, y} = expr)` in expression context. Tried in `parsePrimary()` after arrow-function and grouped-expression attempts fail.

- **Helper functions**:
  - `genDestTempName()` — Generates unique temp names like `_dest0`, `_dest1`
  - `makeIdentNode()` — Creates `Identifier` nodes
  - `makeBindNode()` — Creates either `VariableDeclaration` or `Assignment` based on `decl_mode`

### `src/ast.zig`

No changes needed. The desugaring approach reuses existing node types:
- `VariableDeclaration` / `LetDeclaration` / `ConstantDeclaration`
- `Assignment`
- `BlockStatement`
- `ArrayIndex` / `MemberAccess` for element/property access
- `BinaryExpression` with `.Nullish` for default values
- `MethodCall` with `.slice` for rest arrays

### `src/evaluator.zig`

No changes needed. The desugared `BlockStatement` containing simple `VariableDeclaration` / `Assignment` + `ArrayIndex` / `MemberAccess` access paths is handled by the existing evaluator.

### `src/vm.zig`

No changes needed. Same reason.

## Archivos modificados

- `src/parser.zig` — All destructuring parsing logic

## Edge cases NOT supported (future work)

1. **Object rest exclusion**: `const { a, ...rest } = obj` — Currently the rest binding captures the entire `source`, not `source minus extracted keys`. This works for the common case but differs from JS semantics when combined with rename/defaults.

2. **VM string-indexing limitation**: For-in destructuring with array patterns (`for (const [k] in obj)`) fails at runtime because the VM's `ArrayIndex` opcode doesn't support string indexing (`"x"[0]` → `NotAnArray`). Use object patterns (`{ length }`, `{ 0: first }`) instead. The evaluator (`zig build test`) handles this correctly.

## Covered features

- ✅ Array destructuring in `const`, `let`, `var`
- ✅ Object destructuring in `const`, `let`, `var`
- ✅ Array destructuring in assignments (`[a, b] = expr`)
- ✅ Parenthesized object destructuring in assignments (`({x, y} = expr)`)
- ✅ Nested patterns (arbitrary depth, mixed array/object)
- ✅ Rest in arrays (`[head, ...tail]`)
- ✅ Rest in objects (`{a, ...rest}`)
- ✅ Default values (`[a = 10]`, `{x = 5}`)
- ✅ Rename (`{name: n}`)
- ✅ Elision (`[,, third]`)
- ✅ Whole-pattern defaults (`{x} = defaultVal`) — nested only
- ✅ Comma-separated declarations (`const [a] = [1], b = 2`)
- ✅ Function parameter destructuring: `function({a, b}) {}`
- ✅ Arrow function parameter destructuring: `const f = ({x, y}) => x + y`
- ✅ Array parameter destructuring: `const f = ([a, b]) => a + b`
- ✅ Whole-pattern defaults in function params: `function f({x} = {}) {}`
- ✅ Rename in function params: `function f({name: n}) {}`
- ✅ Nested in function params: `function f({x: {y}}) {}`
- ✅ For-of array destructuring: `for (const [a, b] of pairs) {}`
- ✅ For-of object destructuring: `for (const { x, y } of items) {}`
- ✅ For-of nested destructuring: `for (const { x: { y } } of items) {}`
- ✅ For-of destructuring with rename and defaults: `for (const { oldName: n = d } of items) {}`
- ✅ For-in object destructuring: `for (var { length } in obj) {}`
- ✅ For-in destructuring with rename: `for (var { length: len } in obj) {}`

## Edge cases encontrados durante implementación

### 1. Backtracking for `[` ambiguous with array literals

When the parser sees `[` in statement or expression context, it doesn't know whether it's an array literal (`[1, 2, 3]`) or an array destructuring assignment (`[a, b] = arr`). The parser saves the lexer state, tries `parseDestructuredAssign()`, and if it fails (no `=` after the pattern), it restores the state and parses as an array literal.

### 2. `{` ambiguous with object literals

In expression context, `{x, y}` is an object literal, but `({x, y} = expr)` is a parenthesized destructuring assignment. The parser handles this via a three-way backtrack in `parsePrimary(.LParen)`: tries arrow function first, then parenthesized destructured assign, then grouped expression (which may be an object literal).

### 3. Nested whole-pattern defaults require temp vars

For cases like `const [[a, b] = defaultArr] = actual`, the parser creates a temp variable for the nested sub-pattern so that the default can be applied with `??` after the sub-access but before the inner destructuring.

## Quick verify

```bash
echo 'const [a, b] = [1, 2]; console.log(a, b);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Output: 1 2

diff <(./zig-out/bin/lou run tests/compat/destructuring-decl.lou 2>&1) <(node tests/compat/destructuring-decl.js 2>&1)
# Should be empty (MATCH)
```

