# BigInt Loose Equality (`==` Coercion)

## status
pendiente

## Problema
`tests/compat/bigint-loose-eq.lou` falla con:
```
--- Coercion Number -> BigInt ---
STACK UNDERFLOW: ip=22
thread ... panic: stack underflow
```

## Contexto
ES2020 define reglas específicas para `==` entre BigInt y otros tipos:
- `1n == 1` → `true` (Number se coerciona a BigInt si es entero exacto)
- `1n == "1"` → `true` (String se parsea como BigInt)
- `1n == 1.5` → `false` (Float no exacto)
- `1n == true` → `true` (true → 1n)

Lou implementa `looseValuesEqual` en `src/evaluator.zig` (líneas ~130-200) que maneja BigInt. Pero el VM bytecode compiler puede no estar usando esta función.

## Baseline (qué existe ya)
- `src/evaluator.zig:83` — `valuesEqual` (strict equality, sin coerción BigInt↔Number)
- `src/evaluator.zig:594-595` — dispatch de `Equal/NotEqual/StrictEqual/StrictNotEqual` usa `valuesEqual` (mismo path para loose y strict)
- `src/vm.zig:1093-1094` — opcodes `.eq`/`.ne` usan `valEq(self.pop(), self.pop())`
- `src/vm.zig:1641` — `valEq` helper (no documentado en spec, es la VM-side equivalent de `valuesEqual`)
- `src/builtins/boolean/boolean.zig:61` — `.big_int` truthy via `!big.value.eqlZero()`
- **NO existe `looseValuesEqual`** en el código actual — el spec referencia una función que no está (sólo `valuesEqual`)

## Quick verify (estado actual)
```bash
# Reproduce stack underflow
./zig-out/bin/lou run tests/compat/bigint-loose-eq.lou 2>&1 | head -10
# Verifica que strict equality sí funciona (referencia)
./zig-out/bin/lou run -e 'console.log(1n === 1); console.log(1n !== "1")' 2>&1
```

## Patrones a seguir
- `src/evaluator.zig:83` — `valuesEqual`: añadir ramas para `.big_int` vs `.integer`/`.float` (con check de integer-exact) y `.big_int` vs `.string` (con `parseInt`)
- `src/vm.zig:1641` — `valEq`: misma lógica, simétrica; debe aplicarse en opcodes `.eq` (1093) y `.ne` (1094)
- `src/builtins/bigint/bigint.zig:11-20` — cómo wrappear `.big_int` para comparación

## Gotchas
- `1n == 1` → `true` (Number se coerciona a BigInt si es integer-exact)
- `1n == 1.5` → `false` (float no entero-exacto)
- `1n == "1"` → `true` (string se parsea; falla silenciosa o false si no parsea)
- `1n == true` → `true` (true→1n)
- `1n == 1n` → `true` (mismo BigInt)
- `1n === 1` → `false` (strict NO coerciona)
- Stack underflow en `ip=22` sugiere path del VM no matchea la firma del opcode (probablemente `valuesEqual` no se llama desde `.eq` y se hace push incorrecto)
- `env.bigints` NO existe en `src/environment.zig` — referencia pendiente de añadir

## Código que falla
```js
console.log(1n == 1);     // expected: true
console.log(1n == "1");    // expected: true
```

## Implementacion sugerida
1. Verificar que el VM bytecode compiler usa `looseValuesEqual` para `==` y `!=`.
2. Si el compiler actual usa `valuesEqual` (strict), cambiar a `looseValuesEqual`.

## Tests
- Unit tests existentes para `looseValuesEqual` (verificados).
- `tests/compat/bigint-loose-eq.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/bigint-loose-eq.lou
diff <(./zig-out/bin/lou run tests/compat/bigint-loose-eq.lou) \
     <(node tests/compat/bigint-loose-eq.js)
```

## pendiente
- Verificar y arreglar VM bytecode compiler para usar `looseValuesEqual`.
