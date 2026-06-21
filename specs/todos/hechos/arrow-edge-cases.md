# Arrow Function Edge Cases

## status
implementado

## Problema
`tests/compat/arrow-edge-cases.lou` falla con output incorrecto. La salida se detiene después de los primeros casos sin error explícito, indicando que algún statement no produce el output esperado.

## Contexto
Lou ya parsea y compila arrow functions (`x => x * x`, `(a, b) => a + b`, `() => ...`), pero ciertos edge cases del spec fallan:
- Arrow functions en ramas de ternario: `const sign = x > 0 ? n => "positive" : n => "negative"`
- Ternarios anidados con arrows como ramas
- Array literals con arrow bodies en bloque y expression: `[x => { return x+1 }, x => x+1]`
- Arrow en `for (...)` init/condition
- Arrow retornada de function: `function getAdder() { return x => x + 1 }`
- Arrow con body complejo (binary, call, member)

## Código que falla
```js
const classify = n =>
    n === 0   ? z => "zero"
    : n > 0   ? p => "positive"
    :          m => "negative";
console.log(classify(5)(1));  // expected: positive
```

Output actual (Lou):
```
positive
positive
positive
```

JS espera:
```
positive
positive
positive
zero
negative
0
1
6
12
6
0
3
6
...
```

El programa termina prematuramente. Probable stack underflow o similar.

## Implementacion sugerida
1. Verificar que el bytecode para `a ? b : c` (ternario con arrows) compile correctamente sin perder operandos del stack.
2. Verificar `for (let i = 0, pred = (n) => n < 10; pred(i); i++)` — el AST permite comma-separated init en `for`.
3. Verificar arrow como retorno: `return x => x + 1`.
4. Investigar si `classify(5)(1)` está bien evaluado (call sobre el resultado de llamar classify).

## Tests
- `tests/compat/arrow-edge-cases.lou` debe producir mismo output que `tests/compat/arrow-edge-cases.js`.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/arrow-edge-cases.lou
node tests/compat/arrow-edge-cases.js
diff <(./zig-out/bin/lou run tests/compat/arrow-edge-cases.lou 2>&1) \
     <(node tests/compat/arrow-edge-cases.js 2>&1)
```

## pendiente
- ~~Implementar y verificar.~~

## Solución
La causa raíz no estaba en el parser de arrows, sino en `UpdateExpression`
(`src/evaluator.zig:2871`). El evaluator leía el valor, computaba `±1`, y lo
retornaba — pero nunca persistía el nuevo valor en la variable/miembro/índice.
Resultado: `i++`/`--k`/`o.x++`/`a[0]++` eran no-ops, lo que provocaba el
bucle infinito en `for (let i = 0, pred = (n) => n < 10; pred(i); i++) { ... }`.

Fix: después de computar `new_value`, escribirlo de vuelta al operando,
soportando:
- `Identifier`  → `env.setInScope`
- `MemberAccess` → `obj_val.js_object.properties.put`
- `ArrayIndex`   → `arr_val.js_object.properties.put` o `arr_val.array.set`

Con esto:
- `tests/compat/arrow-edge-cases.lou` → PASS (diff limpio vs `node`).
- `tests/compat/update-expression-lhs.lou` → PASS (era FAIL pre-fix).
- `tests/compat/control.lou` (for/while) sigue PASS.

Resultados del test runner: 8 PASS / 18 FAIL / 1 SKIP (los FAILs restantes
son de features no relacionadas: BigInt, Date, RegExp, etc., que ya estaban
roto antes de este spec).
