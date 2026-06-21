# Function.prototype.call / apply / bind

## status
implementado

## Problema

Los métodos `call`, `apply` y `bind` de `Function.prototype` no
estaban implementados. Eran fundamentales para manipular `this` y
parámetros parciales en JS.

## Contexto

ECMAScript:
- `fn.call(thisArg, ...args)` — llama la función con `this` específico.
- `fn.apply(thisArg, argsArray)` — llama con `this` y array de argumentos.
- `fn.bind(thisArg, ...args)` — retorna nueva función con `this`
  fijado y argumentos parciales aplicados.

Lou tiene dos formas de representar funciones:
- `.function` (AST node) — funciones en el path del evaluador
  (también usado por el VM vía `eval_node`).
- `.closure` (bytecode) — funciones en el path del sub-VM.

El VM compila `Function.prototype.call/apply/bind` a `eval_node` para
que el evaluator haga el dispatch, ya que el VM no tiene un path
genérico para invocar closures arbitrarias.

## Implementación

### 1. `src/builtins/function/function.zig`

Módulo nuevo con dos piezas:

1. **`BoundFunctionInfo` + `makeBoundFunction` + `extractBoundFunction`
   + `isBoundFunction`** — representan un bound function como un
   `*ObjectValue` con `@@type = "Function"`, `@@target`, `@@bound_this`
   y `@@bound_args` (array). El wrapper soporta anidamiento
   (`bind().bind()`) gracias a `@@target` que puede ser otro wrapper.

2. **Unit tests** — round-trip de make + extract + rechazo de
   `@@type` distinto.

No se registra ningún `FUNCTION_OBJECT` en `BUILTIN_OBJECTS` porque
`call/apply/bind` se acceden vía cualquier función, no vía
`Function.call(...)`. El dispatch se hace desde el evaluator.

### 2. Dispatch en el evaluator (`src/evaluator.zig`)

`fn evaluateFunctionPrototypeMethod` se llama cuando el método es
`call`/`apply`/`bind` y el receiver es una función o un bound function
wrapper. Devuelve el resultado de invocar la función con el `thisArg`
y los argumentos correctos.

`fn invokeTargetWithThis` desenrolla wrappers anidados (bound dentro
de bound) recursivamente, y termina llamando a `invokeFunctionNode` (ya
public) con el target final, los args mergeados y el `this` del wrapper
más interno.

Modificaciones al `MethodCall` handler (`evaluate`):

- Para object `.Identifier`, dispatch al `js_object` case existente
  **pero con un check de bound function al inicio del mismo**. Si el
  valor es un bound wrapper, se llama a
  `evaluateFunctionPrototypeMethod` o `invokeBoundFunctionAsCall`.
  Este check se hace antes del dispatch por `@@type="Boolean"` para
  evitar colisiones.
- Para el path de `value == .function` (incluyendo el caso
  `function(){...}.bind(...)` donde object es una function
  expression), se añade el mismo check de call/apply/bind antes del
  default "call function".
- Para function declarations (que viven en `env.functions` no en
  `env.values`), se añade un check separado de
  `env.getFunction(obj_name)` después del bloque `env.get` para que
  `greet.call(obj, "x")` funcione cuando `greet` es una declaración
  top-level.
- Para `MemberAccess` (`this.foo` donde `this.foo` es null/undefined),
  se añaden los cases `null` y `void` que devuelven `void` (per
  ES2025 ToPropertyKey en non-strict mode).

Modificaciones al `FunctionCall` handler para soportar invocación
directa de bound functions (`bound(arg1, arg2)`):

- Si `env.get(f.name)` devuelve un bound function wrapper, extrae el
  info y lo invoca con el `this` ligado y los args mergeados.

### 3. VM compiler fallback (`src/vm.zig`)

El VM compiler detecta `MethodCall` con método `call`/`apply`/`bind` y
emite **solo `eval_node`** (sin pushes de bytecode para object y args).
Esto evita stack imbalance porque el evaluator re-evalúa el AST node
desde cero.

El VM `builtin` opcode para `bound(arg1, ...)` dispatcha a
`evalBoundFunctionCall` que llama a `invokeFunctionNode` con el target,
los args mergeados y el `bound_this`.

## Archivos creados / modificados

- `src/builtins/function/function.zig` (nuevo) — bound function helpers
  + unit tests
- `src/evaluator.zig` (modificado) — dispatch de call/apply/bind en
  MethodCall y FunctionCall, y MemberAccess null/void
- `src/vm.zig` (modificado) — compiler emite `eval_node` para
  call/apply/bind; `builtin` dispatcha bound functions

## Verificación

- `tests/compat/call-apply-bind.js` / `.lou` — output byte-idéntico
  a Node.js (verificado con `diff`)
- 932 unit tests pass (incluyendo los 3 nuevos en `function.zig`)
- `bash tests/compat/run.sh` — 20 PASS, 1 FAIL (pre-existing
  `isolate.lou`), 1 SKIP

Comandos:
```bash
zig build test
./zig-out/bin/lou run tests/compat/call-apply-bind.lou
bash tests/compat/run.sh
```

## pendiente

- [x] `fn.call(thisArg, ...args)` retorna el booleano correcto
- [x] `fn.apply(thisArg, argsArray)` con array y con `null`/`undefined`
- [x] `fn.bind(thisArg, ...args)` retorna wrapper invocable
- [x] Dispatch sobre primitivo (`true.toString()`-equivalente)
- [x] Dispatch sobre wrapper (`(new Boolean(true)).method()`)
- [x] `bound()` invocación directa (FunctionCall)
- [x] Re-bind: `bound.bind({...})` mantiene el this original (Node behavior)
- [x] Tests compat (Lou vs Node idénticos)
- [x] Unit tests

## Edge cases encontrados durante implementación

### Stack imbalance con `eval_node`
Inicialmente el VM compiler emitía `eval_node` para call/apply/bind
PERO también bytecode pushes para object y args. El `eval_node`
re-evalúa el AST y pushea el resultado, dejando los pushes previos
en el stack. Esto causaba que llamadas como
`function() { return this.name; }.bind({name: "X"})` dentro de una
función fallaran silenciosamente.

**Fix**: emitir SOLO `eval_node` (sin pushes), igual que
`NewExpression`.

### `MemberAccess` con `null`/`undefined`
`this.name` cuando `this` es `null` debería devolver `undefined` per
ES2025. Pero el `MemberAccess` handler solo tenía cases para
`array`/`string`/`iterator`/`regexp`/`js_object` y caía al
`return error.InvalidMemberAccess` para `null`/`void`. Esto causaba
que `greet.apply(null, ["Test"])` fallara con un error silencioso
(la propagación del error comía el output).

**Fix**: añadir cases `null` y `void` que devuelven `void` (per spec).

### Function declaration vs variable para `call`
`greet.call(obj, "x")` donde `greet` es una declaración top-level
fallaba porque `env.get("greet")` devuelve `void` (las funciones
viven en `env.functions`, no en `env.values`). El dispatch
original solo buscaba en `env.get`.

**Fix**: añadir un check separado `env.getFunction(obj_name)`
después del bloque `env.get` para function declarations.

### Duplicate `.js_object` branch
Inicialmente añadí un nuevo `} else if (value == .js_object) {` en el
path de dispatch por valor (fuera de `if (m.object.* == .Identifier)`).
Pero la lógica de bound function también necesita estar dentro del
`if (env.get(obj_name)) |value|` block (porque la mayoría de los
casos de `bound.bind(...)` son con `bound` siendo una variable). El
duplicate causaba que la rama nunca se ejecutara.

**Fix**: añadir el check al TOP del `} else if (value == .js_object)`
existente (dentro del `env.get` block), no crear un nuevo branch.

### `bind` sobre bound function mantiene el `this` original
Per spec ES, `bound.bind({name: "Frank"})` debería poner el nuevo
`thisArg`. Per Node.js (y el spec V8 / MDN docs), el `this` se
mantiene como el original de `bound`. Node retorna
`bound.bind({name: "Frank"})("Greetings") === "Hey Alice"` (no
`"Hey Frank"`).

**Fix**: en el re-bind, usar `info.bound_this` en lugar de `this_arg`
para preservar el `this` original.

### `toBoolean` no se llama sobre el primer argumento de `call`
Cuando `fn.call(null, ...)` o `fn.call(undefined, ...)` se invoca, el
`this` se mantiene como `null`/`undefined` (no se convierte a
`globalThis`). Esto es lo que hace Node, así que Lou coincide.

### Pruebas unitarias del helper
El primer intento de unit test usaba `.{ .VoidLiteral = {} }` para
inicializar un `Ast.Node` (un union). El compilador rechazaba porque
`VoidLiteral` es un struct vacío pero el field es un struct con
campos. Cambié a `.{ .FunctionDeclaration = .{...} }` con
`parameters` y `body` correctos.

## Limitaciones conocidas

- `bind.bind()` no permite cambiar el `this` (coincide con Node, no
  con la spec literal — la spec V8 es ambigua).
- `Function.prototype` no es directamente accesible como objeto
  built-in. Si alguien hace `Function.prototype.call(...)` con
  `Function` como variable global, no funcionará.
- `Symbol.toPrimitive` no está soportado.
- No hay soporte para `Reflect.apply` u otros mecanismos de
  invocación indirecta.
