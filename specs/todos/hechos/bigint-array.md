# BigInt Array Indexing and Iteration

## status
hecho

## Problema
`tests/compat/bigint-array-index.lou` y `tests/compat/bigint-array-methods.lou` fallan:

**bigint-array-index.lou**:
```
error: NotAnArray
/src/vm.zig:1154:25 in interpret
```
El programa intenta indexar un BigInt como si fuera array: `1n[0]` o similar.

**bigint-array-methods.lou**:
```
thread ... panic: integer overflow
/src/vm.zig:1116:122 in interpret
```
Integer overflow en alguna operación con BigInt.

## Contexto
ES2020 permite:
- `BigInt` como índice de array: `arr[1n]` — debe coercionar a Number (con check de precisión).
- BigInts en array methods: `[1n, 2n, 3n].map(x => x * 2n)`.
- BigInt.prototype methods: `1n.toString()`, `1n.toString(16)`, etc.

Lou implementa la mayoría de BigInt features (los unit tests pasan), pero el compat test usa sintaxis específica o edge cases que no están manejados.

## Baseline (qué existe ya)
- `src/vm.zig:1136` — `index_get` opcode maneja `.array` (integer/float) y `.js_object`, pero NO `.big_int` para `arr == .array`
- `src/vm.zig:1218` — `set_prop` opcode (no `set_index` dedicado; asignación a índice cae a `set_prop`)
- `src/builtins/bigint/bigint.zig:5` — `BigIntConstructor` registra `.big_int` values
- `src/builtins/bigint/bigint.zig:191` — `BIGINT_OBJECT` con métodos (`toString`, `toLocaleString`, `asIntN`, `asUintN`)
- `src/evaluator.zig:642` — Plus dispatch cubre string concat pero NO mixed BigInt+Number
- `specs/todos/hechos/bigint-array-index.md` — spec hermano de índice (no es array literal con BigInts)

## Quick verify (estado actual)
```bash
# Reproduce NotAnArray para índice BigInt
./zig-out/bin/lou run tests/compat/bigint-array-index.lou 2>&1 | head -20
# Reproduce integer overflow en array methods
./zig-out/bin/lou run tests/compat/bigint-array-methods.lou 2>&1 | head -20
```

## Patrones a seguir
- `src/vm.zig:1136-1170` — `index_get` actual: rama `arr == .array` con `switch(idx)` integer/float — añadir `.big_int => |b|` con `bigIntIndex(b)` helper
- `src/builtins/bigint/bigint.zig:5-20` — patrón constructor: recibe primitivo, crea `BigIntValue`, append a `env.bigints` para cleanup
- `src/vm.zig:1085` — patrón de cleanup: `env.owned_strings.append(self.env.allocator, s) catch {};` antes de push

## Gotchas
- VM: añadir rama `.big_int` en `interpret` para `index_get` Y dispatch de `set_prop` para asignación a índice
- BigInt → `BigIntValue.fromString`, append a `env.bigints` (campo NO existe aún en `src/environment.zig` — los builtins ya lo referencian pero el struct debe ser actualizado)
- `env.bigints` debe añadirse en `initWithIo` (~91), `initBlock` (~125), `deinit` (~253) — mismo patrón que `env.arrays`
- `Integer overflow` viene del parser: `parser.zig:458,498,562` desugars `x++` a `x + 1.0` (FloatLiteral) — para BigInt, la coerción debe ser explícita o el AST debe generar BigIntLiteral
- `index_get` actual retorna `error.IndexOutOfBounds` para integer/float inválido; para BigInt (out-of-range, negative) debe push `void` (undefined), no panic

## Código que falla
```js
const arr = [1n, 2n, 3n];
console.log(arr[0]);   // expected: 1n
console.log(arr.length); // expected: 3
```

## Implementacion sugerida
1. Verificar que `[1n, 2n, 3n]` parse correctamente (ArrayLiteral con BigIntLiteral elements).
2. Verificar que `arr[0]` retorna el BigInt value.
3. Verificar que array methods (`.map`, `.filter`, etc.) funcionan con BigInts.
4. Para el integer overflow: identificar qué operación causa overflow.

## Tests
- Unit tests existentes en `src/builtins/bigint/bigint.zig` (la mayoría pasan).
- `tests/compat/bigint-array-index.lou` y `bigint-array-methods.lou` deben pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/bigint-array-index.lou
./zig-out/bin/lou run tests/compat/bigint-array-methods.lou
```

## pendiente
- Diagnosticar y arreglar BigInt array indexing y methods.
