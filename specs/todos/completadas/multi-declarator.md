# Multiple declarators (`const a = 1, b = 2;`)

## status

**completada** — implementada (compat: 88 PASS / 0 FAIL / 0 SKIP)

`tests/compat/multi-declarator.lou` produce salida byte-idéntica a Node.

## Problema

El parser ya construía una lista de declaraciones para `const/let/var` con
varias variables, pero la envolvía en un `BlockStatement`. Para `var` no se
notaba (hoisting), pero `const`/`let` quedaban atrapados en el nuevo ámbito
del bloque:

```js
const a = 10, b = 2;
console.log(a, b); // undefined undefined
```

## Implementación

### `src/ast.zig`

- `BlockStatement` gana `is_scope: bool = true` (default: un bloque real).

### `src/parser.zig`

- Los tres wrappers de lista de declaradores (`const`, `let`, `var`) se
  marcan con `is_scope = false`: son transparentes.

### `src/evaluator.zig`

- `BlockStatement` sólo crea un `Environment` de bloque si `is_scope` es
  true; un wrapper transparente evalúa sus sentencias en el ámbito actual.

### `src/vm.zig`

- El compilador emite las sentencias del wrapper directamente en el ámbito
  actual, sin el baile `try_get_global`/`set_global` de los bloques.

## Verificación

- Fixture nuevo con top-level, función, bloque anidado y `for (let i = 0, j = 10; ...)`.
- `zig test src/main.zig` — 1,075 tests.
