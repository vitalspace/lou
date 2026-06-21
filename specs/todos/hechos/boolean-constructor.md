# Boolean() Constructor as Function

## status
implementado

## Problema
`tests/compat/boolean.lou` falla. Después de imprimir los primeros casos, el programa termina sin completar el resto del output:

Output actual (Lou):
```
--- Boolean() constructor as function ---
true
false
```
(programa termina)

Output esperado (JS):
```
--- Boolean() constructor as function ---
true
false
--- Boolean() with various inputs ---
...
```

## Contexto
El spec test cubre:
- `Boolean()` y `Boolean(value)` como constructor y como función.
- `Boolean()` retorna `false` para `0`, `null`, `undefined`, `NaN`, `""`.
- `Boolean()` retorna `true` para cualquier otro valor.
- `new Boolean(...)` retorna un wrapper object.
- `Boolean.prototype` y métodos heredados.

Lou ya tiene `src/builtins/boolean/boolean.zig` con la mayoría del spec implementado (tests unitarios pasan). Pero el compat test usa sintaxis específica de Lou (¿`fn` vs `function`?) que puede no estar reconocida.

## Código que falla
Ver `tests/compat/boolean.lou`. Después de los primeros casos, alguna expresión causa terminación prematura del programa.

## Implementacion sugerida
1. Verificar que `Boolean` está registrado correctamente como builtin object.
2. Verificar que `Boolean(x)` como llamada a función (no constructora) funciona en VM bytecode.
3. Verificar dispatch de métodos en Boolean prototype.

## Tests
- Unit tests existentes en `src/builtins/boolean/boolean.zig` (ya pasan).
- `tests/compat/boolean.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/boolean.lou
diff <(./zig-out/bin/lou run tests/compat/boolean.lou) \
     <(node tests/compat/boolean.js)
```

## pendiente
- Investigar terminación prematura del compat test.

## Solución
Tres bugs contribuían:

1. **VM sin BigIntLiteral** (`src/vm.zig`): el `expr` no tenía case para
   `BigIntLiteral`, así que `0n` no emitía bytecode. El method_call
   posterior (de `console.log(Boolean(0n))`) intentaba pop un arg que
   nunca se pusheó → stack underflow. **Fix**: añadir case que delega
   via `eval_node` al AST evaluator.

2. **`new Boolean()` no wrappea** (`src/evaluator.zig`): la builtin
   `BooleanConstructor` siempre retorna un primitivo. ES2015 requiere
   un wrapper object para `new Boolean(x)`. El helper
   `makeBooleanWrapper` (en `src/builtins/boolean/boolean.zig`) ya
   existía pero nadie lo llamaba. **Fix**: el branch de `NewExpression`
   que detecta builtin ahora wrappea el resultado si el nombre es
   `"Boolean"` y el valor es primitivo booleano.

3. **Primitive autoboxing en method calls** (`src/vm.zig` + `src/evaluator.zig`):
   `true.toString()` no funcionaba porque el VM `method_call` no
   busca métodos en prototipos para primitivos. **Fix**: el compilador
   del VM detecta cuando el `object` de un `MethodCall` es un literal
   primitivo (Boolean/Integer/Float/String/BigInt) y delega via
   `eval_node` al evaluator. El evaluator ahora despacha via
   `getBuiltinObject("Boolean")` (y equivalentes) para los métodos
   del prototipo, y via la tag `@@type` del wrapper para los
   instances de `new Boolean()`.

4. **`&&` / `||` retornaban boolean** (`src/evaluator.zig` +
   `src/vm.zig`): la semántica ES2015 es retornar el operando (no
   coerced a boolean). `Boolean(1) && "yes"` debe retornar `"yes"`,
   no `true`. **Fix**: el opcode `and_` y `or_` del VM, y la rama
   `And`/`Or` del evaluator, ahora retornan el operando apropiado
   según ES2015.

### Limitaciones
- Otros method calls sobre primitivos (`(123).toString()`,
  `"abc".slice()`) se beneficiarán del mismo path, pero la
  implementación completa del dispatch de `String.prototype.*` /
  `Number.prototype.*` en el evaluator queda fuera de scope.

### Resultados
- `tests/compat/boolean.lou` → PASS.
- 13/27 compat tests PASS (sin regresiones).
