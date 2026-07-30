# Compound Assignment on MemberAccess

## status

pendiente (drift corrected 2026-06-29; previously falsely marked implementado)

`tests/compat/compound-assignment-member.lou` currently FAILs per the compat baseline (30 PASS / 50 FAIL / 1 SKIP). The spec body claims the stack-underflow bug was fixed via VM + evaluator refactor, but the compat test still produces a diff against Node. Reverted status.

## Problema
`tests/compat/compound-assignment-member.lou` falla con `STACK UNDERFLOW` panic:

```
STACK UNDERFLOW: ip=13
thread ... panic: stack underflow
/src/vm.zig:1048:13 in pop
/src/vm.zig:1215:18 in interpret
```

## Contexto
Lou implementa compound assignment (`+=`, `-=`, etc.) para `Identifier` LHS (los unit tests pasan). Pero para `MemberAccess` LHS (`obj.x += 5`) y `ArrayIndex` LHS (`arr[i] += 5`), el VM bytecode compiler no emite los opcodes correctos, causando stack underflow.

El test cubre casos como:
```js
var obj = { x: 10 };
obj.x += 5;      // expected: 15
arr[i++] += 5;   // expected: arr[0]+5, i=1
obj["x"] *= 2;   // expected: 20
```

Los unit tests en `src/evaluator.zig` (líneas ~4600-4800) pasan porque van por el AST evaluator path. Pero el VM bytecode path no maneja `MemberAccess` o `ArrayIndex` como LHS de compound assignment.

## Código que falla
```js
var obj = { x: 10 };
obj.x += 5;
```

## Implementacion sugerida
1. En VM bytecode compiler (vm.zig), cuando se compila una BinaryExpression compound (`+=`, `-=`, etc.) con LHS `MemberAccess` o `ArrayIndex`:
   - Evaluar el LHS base (obj, arr).
   - Evaluar el LHS index/key.
   - Evaluar el RHS.
   - Hacer la operación (add, sub, etc.).
   - Almacenar el resultado de vuelta en el LHS.
2. Alternativamente, delegar al AST evaluator via `eval_node` (más simple, menos performante).
3. Verificar el flujo del stack: no debe haber pops de más.

## Tests
- Unit tests existentes pasan (verificados).
- `tests/compat/compound-assignment-member.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/compound-assignment-member.lou
diff <(./zig-out/bin/lou run tests/compat/compound-assignment-member.lou) \
     <(node tests/compat/compound-assignment-member.js)
```

## pendiente
- ~~Implementar compound assignment sobre MemberAccess/ArrayIndex en VM bytecode compiler.~~

- **Estimated fix effort**: 2h: add vm.zig opcode path for MemberAccess LHS with compound assignment (+=, -=, *=, /=, %=). Currently stack underflow in .pop means no value is pushed for the LHS member after evaluation.

## Solución
Dos bugs relacionados, uno en VM y otro en evaluator.

### VM (`src/vm.zig`)
- El `expr` para `BinaryExpression` con operador compound (PlusAssign, etc.)
  sólo manejaba LHS `Identifier`; el resto caía al vacío → `pop` sin valor
  → stack underflow. Se añade un branch `else` que emite `eval_node` para
  deferir al AST evaluator en runtime.
- Mismo patrón para `Assign` con LHS `ArrayIndex` (pre-existente, no
  rompía el spec pero impedía `obj["k"] = 7` y derivados).

### Evaluator (`src/evaluator.zig`)
- El handler de BinaryExpression para compound assignment sólo aceptaba
  LHS `Identifier`; ahora también `MemberAccess` (lectura/escritura via
  `js_object.properties`) y `ArrayIndex` (lectura/escritura via
  `js_object.properties` o `array.set/get`).
- Se extrae la operación a un helper `compoundOp(allocator, op, lhs, rhs)`
  reutilizable por los 3 LHS. Añade soporte para `string += rhs` (concat).
- Mismo refactor para `Assign` con `ArrayIndex` (soporta ahora `.array`
  además de `.js_object`).
- Helpers nuevos: `indexToKey(allocator, idx)` y `indexToUsize(idx)`
  (encapsulan la conversión de índices para keys de properties y para
  índices de array).

### Limitaciones
- `compoundOp` retorna `.void = {}` cuando los tipos son incompatibles
  (en vez de error) para no romper tests con `obj.x = "hello"; obj.x += 5`.
  V8 haría coerción silenciosa en algunos casos y error en otros.

### Resultados
- `tests/compat/compound-assignment-member.lou` → PASS.
- 10/27 compat tests PASS (sin regresiones).
