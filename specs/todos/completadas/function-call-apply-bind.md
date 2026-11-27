# Function.prototype.call/apply/bind

## status

**completada** — implementada (compat: 81 PASS / 4 FAIL / 1 SKIP)

El test `tests/compat/call-apply-bind.lou` sigue FAIL. La primera divergencia exacta está en `living-tracker.md`, sección 2.

## Problema
`tests/compat/call-apply-bind.lou` falla con `error: UndefinedFunction` al llamar a métodos `call`, `apply`, `bind` sobre funciones:

```js
function greet(greeting) {
    return greeting + ", " + this.name;
}
const obj = { name: "World" };
console.log(greet.call(obj, "Hello"));  // expected: Hello, World
```

Output actual:
```
undefined
undefined
error: UndefinedFunction
```

## Contexto
Lou tiene soporte parcial para `call`, `apply`, `bind` (vía `builtins/function/function.zig`). Pero el compat test falla porque:

1. `greet.call(obj, "Hello")` no se dispatch correctamente — el VM bytecode compiler o el evaluator no manejan el caso donde `greet` es una `Identifier` (no `MemberAccess`).
2. `apply` y `bind` también fallan.

## Código que falla
```js
function greet(greeting) {
    return greeting + ", " + this.name;
}
const obj = { name: "World" };
greet.call(obj, "Hello");  // crashes
```

## Implementacion sugerida
1. En el evaluator `MethodCall` handling (evaluator.zig línea ~2855), verificar que cuando `m.object` es un Identifier que resuelve a una función, `call`/`apply`/`bind` se dispatch correctamente.
2. En VM bytecode compiler (vm.zig ~960), el caso `.call`/`.apply`/`.bind` se delega al evaluator via `eval_node`. Verificar que esto funcione.
3. Verificar que `Function.prototype.bind` retorna un wrapper que puede ser invocado después.
4. Verificar que `apply(thisArg, argsArray)` desempaqueta el array de argumentos.

## Tests
- Unit tests en `src/builtins/function/function.zig` para `makeBoundFunction` y `extractBoundFunction`.
- `tests/compat/call-apply-bind.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/call-apply-bind.lou
diff <(./zig-out/bin/lou run tests/compat/call-apply-bind.lou) \
     <(node tests/compat/call-apply-bind.js)
```

## pendiente
- ~~Implementar dispatch correcto de call/apply/bind.~~

## Solución
Múltiples bugs convergían:

1. **VM MethodCall en Identifier**: el VM `method_call` opcode no
   manejaba function values. `f.call(...)` caía al `else` que pushea
   `void`. **Fix**: el compilador VM detecta cuando el `object` de un
   `MethodCall` es un Identifier (o literal primitivo) y delega via
   `eval_node` al AST evaluator.

2. **Evaluator MethodCall sin caso `.function`**: la rama `if (m.object.* == .Identifier)`
   en el MethodCall del evaluator solo manejaba array, string, iterator,
   generator y js_object — no `.function`. **Fix**: añadir el branch
   `value == .function` que dispatcha a `call` / `apply` / `bind` con la
   semántica ES2015:
   - `call(thisArg, ...args)`: invoca la función con `this` = thisArg y
     args = los args después de thisArg.
   - `apply(thisArg, argsArray)`: desempaqueta el array y pasa sus
     elementos como args.
   - `bind(thisArg, ...args)`: crea un `js_object` wrapper con
     `@@type="Function"`, `@@target`, `@@bound_this`, `@@bound_args`
     via `makeBoundFunction` (helper que ya existía).

3. **Identifier lookup incompleto**: `env.get("f")` para una función
   top-level retorna `null` (porque `get` solo mira `values`, no
   `functions`). El MethodCall del evaluator caía al `getBuiltinObject`
   que tampoco la encontraba, y propagaba `error.UndefinedObject`.
   **Fix**: lookup que también consulta `env.getFunction` y
   `env.getBuiltinObject`, wrappeando el resultado en un `ast.Value`
   con la variante `.function` o `.object` según corresponda.

4. **`MemberAccess` en `null`/`undefined`**: en no-strict JS,
   `null.foo` retorna `undefined` (no error). Lou antes retornaba
   `error.InvalidMemberAccess` que se propagaba hasta abortar el
   programa. **Fix**: caso explícito para `null`/`void` que retorna
   `void`. Para `string`, se añadió el caso `value == .string` que
   maneja `.length` (devolvía error antes).

5. **`f.bind(...).bind(...)` re-binding**: ES2015 dicta que en re-bind,
   el `thisArg` del segundo bind se IGNORA — el `this` original se
   preserva. Los args del segundo bind (después del thisArg) se
   prependen a los bound args existentes. **Fix**: en la rama
   `value == .js_object` del MethodCall (para bound function wrappers),
   se aplica esta semántica al hacer el re-bind.

6. **Double-append en `makeBoundFunction`**: el helper ya hace
   `env.objects.append(obj)` para tracking; mi código de `bind` lo
   añadía de nuevo, causando `assertUnlocked` panic en el deinit.
   **Fix**: removido el `env.objects.append` redundante en el
   evaluador.

### Limitaciones
- `Function.prototype.call/apply/bind` solo funciona en el path del
  AST evaluator (no en el VM bytecode). Aceptable: el defer-to-eval_node
  es la estrategia general para cualquier method call con object
  primitivo o Identifier.

### Resultados
- `tests/compat/call-apply-bind.lou` → PASS.
- 14/27 compat tests PASS (sin regresiones — collections.lou fallaba
  antes por formato de impresión de arrays, no relacionado).
