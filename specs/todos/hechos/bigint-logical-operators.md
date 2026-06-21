# BigInt Logical Operators (`&&`, `||`)

## status
implementado

## Resumen
`tests/compat/bigint-logical-operators.lou` ahora produce salida identica a `node tests/compat/bigint-logical-operators.js`.

## Cambios

### `src/vm.zig`
- **Nuevo opcode `jump_if_not_nullish`** (`src/vm.zig:20`, `src/vm.zig:1200`): peek top, salta si el valor NO es `null`/`void`. Necesario para cortocircuito de `??`.
- **`.and_`/`.or_` ahora retornan operando, no boolean** (`src/vm.zig:1171-1172`):
  ```zig
  .and_ => { const b = self.pop(); const a = self.pop(); self.push(if (truthy(a)) b else a); },
  .or_  => { const b = self.pop(); const a = self.pop(); self.push(if (truthy(a)) a else b); },
  ```
  Mismo shape que `.nullish` (`src/vm.zig:1173`).
- **Compiler emite bytecode con cortocircuito** para `&&`, `||`, `??` (`src/vm.zig:796-845`):
  - `&&`: `expr(left); jump_if_false END; pop; expr(right); END:`
  - `||`: `expr(left); jump_if_true  END; pop; expr(right); END:`
  - `??`: `expr(left); jump_if_not_nullish END; pop; expr(right); END:`

### `src/evaluator.zig`
- **And/Or branch retorna `left` o `right` directamente** (`src/evaluator.zig:641-660`). Cortocircuito preservado, tipo del operando preservado.
- **`left_truthy` extendido** con `.big_int` y `.null` (`src/evaluator.zig:643-651`):
  ```zig
  .big_int => |big| !big.value.eqlZero(),
  .void, .null => false,
  ```

## Verificación
```bash
$ diff <(./zig-out/bin/lou run tests/compat/bigint-logical-operators.lou) \
       <(node tests/compat/bigint-logical-operators.js)
# (sin output — coinciden exactamente)
```

Ademas, las siguientes compat tests que antes fallaban ahora pasan (tambien usan `&&`/`||`):
- `bigint-array-index.lou`
- `bigint-array-methods.lou`
- `bigint-increment-decrement.lou`
- `bigint-logical-edge.lou`

## Problema
`tests/compat/bigint-logical-operators.lou` falla con:
```
--- BigInt && ---
STACK UNDERFLOW: ip=15
thread ... panic: stack underflow
```

## Contexto
ES2020 define que `&&` y `||` aplicados a BigInt siguen las mismas reglas que para cualquier valor:
- `BigInt(x) && BigInt(y)` retorna `BigInt(y)` si ambos truthy, sino `BigInt(x)` o el falsy.
- Pero en JS real, `&&` y `||` no cambian el tipo — retornan el último operando evaluado.

Lou implementa BigInt como un valor distinto. El VM bytecode compiler puede no manejar correctamente el caso donde operandos de `&&`/`||` son BigInts.

## Baseline (qué existe ya)
- `src/vm.zig:1098-1099` — opcodes `.and_`/`.or_` empujan `.boolean` (no el operando) — **bug raíz**
- `src/evaluator.zig:601-636` — branch And/Or en evaluator también empuja `.boolean` — mismo bug en fallback path
- `src/vm.zig:1100` — opcode `.nullish` correctamente retorna el operando (`a` si no null/void, sino `b`) — **patrón a seguir**
- `src/evaluator.zig:603-610` — función local `left_truthy` (evalúa truthy para cada tipo)
- `src/builtins/boolean/boolean.zig:61` — `truthy` para `.big_int` (`!big.value.eqlZero()`)

## Quick verify (estado actual)
```bash
# Reproduce stack underflow
./zig-out/bin/lou run tests/compat/bigint-logical-operators.lou 2>&1 | head -10
# Verifica que `??` sí funciona (referencia de patrón)
./zig-out/bin/lou run -e 'console.log(0n ?? 42n); console.log(null ?? 1n)' 2>&1
```

## Patrones a seguir
- `src/vm.zig:1100` — `nullish`: `self.push(if (a == .null or a == .void) b else a);` — mismo shape debe aplicar a `and_`/`or_` con `truthy(a)` como predicado
- `src/evaluator.zig:601-636` — And/Or branch: actualmente evalúa `left`, decide truthy, evalúa `right`, retorna `.boolean`. Debe retornar `left` o `right` directamente
- `src/evaluator.zig:603-610` — `truthy` ya implementado para integer/float/string/void; añadir `.big_int => |big| !big.value.eqlZero()`

## Gotchas
- Short-circuit: `&&` no evalúa `b` si `a` es falsy; `||` no evalúa `b` si `a` es truthy — preservar este comportamiento
- `??` ya funciona correctamente en `src/vm.zig:1100` — NO romper al cambiar `.and_`/`.or_`
- Stack underflow en `ip=15` sugiere que `b` se pop'eó antes de chequear `a`, o que el path VM emite código que no matchea la firma del opcode
- Retorno debe preservar el tipo del operando (BigInt, string, number, etc.) — no coerce a boolean
- VM push debe aceptar cualquier `Value` (no boxing especial)

## Código que falla
```js
console.log(1n && 2n);  // expected: 2n
console.log(0n && 2n);  // expected: 0n
```

## Implementacion sugerida
1. Verificar dispatch de `&&` y `||` en el VM bytecode compiler para operandos BigInt.
2. Verificar que el AST evaluator maneja correctamente BigInt en logical operations.

## Tests
- Unit tests existentes (verificados).
- `tests/compat/bigint-logical-operators.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/bigint-logical-operators.lou
diff <(./zig-out/bin/lou run tests/compat/bigint-logical-operators.lou) \
     <(node tests/compat/bigint-logical-operators.js)
```

## pendiente
- (nada — implementado)
