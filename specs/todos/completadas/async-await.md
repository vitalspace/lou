# Async/Await y Promise

## status
✅ COMPLETADO

## Problema
No existía soporte para `async`/`await`, funciones asíncronas ni un objeto `Promise` real. El token `Await` existía en el lexer pero el parser nunca lo usaba, y `Promise` era un stub síncrono que no ejecutaba callbacks.

## Contexto

Lou es un intérprete JavaScript escrito en Zig. `async`/`await` y `Promise` son fundamentales para programación asíncrona en JS moderno.

## Baseline (al iniciar el spec)
- `Await` YA existía en el lexer, pero sin parser ni evaluación.
- `Async` NO existía como keyword.
- `Promise` existía como `js_object` ya resuelto con `then`/`catch`/`finally`, pero no invocaba callbacks ni tenía constructor/estáticos.
- No hay event loop ni timers; `setTimeout` no está implementado.

## Arquitectura implementada

### Lexer / Parser
- Nuevo token/keyword `Async`; `Await` se conserva.
- `async` es contextual: funciona como identificador (`const async = 1`, `async(2)`) y como prefijo de función/arrow según el lookahead.
- `async function f() {}`, `const f = async function() {}`, `async (x) => ...` y `async x => ...`.
- `await expr` produce `AwaitExpression`.
- Métodos `async` en clases y objetos literales.

### AST
- `AwaitExpression { value }`.
- `FunctionDeclaration.is_async` y `ArrowFunction.is_async` (default `false`).
- `freeAst`, `printAst` y el walker de closures actualizados.

### Promise runtime (`src/builtins/promise/promise.zig`)
- Estados reales `pending` / `fulfilled` / `rejected` en propiedades internas `@@promise_*`.
- `.then`, `.catch`, `.finally` encolan reacciones y devuelven una promesa hija.
- Asimilación de promesas, propagación de rechazos, `finally` con pass-through y rechazo si el callback lanza.
- Estáticos `resolve`, `reject`, `all`, `allSettled`, `race`, `any`.
- Constructores `Promise` con executor y funciones `resolve`/`reject` invocables.

### Evaluator
- `new Promise(executor)` crea la promesa pendiente, ejecuta el executor y captura sus throws.
- Las funciones `async` se ejecutan y su retorno/throw se convierte en una promesa resuelta/rechazada.
- `await` desenvuelve una promesa resuelta; si está rechazada lanza el motivo para que `try/catch` lo capture; si está pendiente drena trabajos encolados antes de decidir.
- Los throws de funciones normales ahora se propagan correctamente al llamador, lo que también permite que callbacks de Promise rechacen la promesa hija.

### Cola de microtareas
- `Environment.promise_jobs` en la raíz.
- `drainPromiseJobs()` procesa reacciones al terminar el programa de nivel superior.
- `main.zig` usa el evaluator (no la VM) para programas que mencionan `async`, `await` o `Promise`, y drena la cola al final.

## Limitaciones conocidas
- No hay event loop ni timers; todo ocurre en el mismo tick.
- `await` sobre una promesa pendiente que no puede resolverse durante el drenado no suspende realmente la función; no hay continuaciones guardadas. Los casos con resolución síncrona, encadenada o por trabajos ya encolados funcionan.
- Los cuerpos `async` continúan de forma síncrona después de un `await` ya resuelto, por lo que programas con varios awaits intercalados pueden diferir del orden exacto de microtareas de Node. El fixture mantiene la salida dentro de una sola función `main` para que el orden sea determinista.
- No hay integración de Promise con la VM; el intérprete usa el evaluator para estos programas.

## Verificación

```bash
./zig-out/bin/lou run tests/compat/async-await.lou
node tests/compat/async-await.js
diff <(./zig-out/bin/lou run tests/compat/async-await.lou) <(node tests/compat/async-await.js)
bash tests/compat/run.sh
zig test src/main.zig
```

Resultados:
- `tests/compat/async-await.lou` idéntico a Node.
- `PASS=101 FAIL=0 SKIP=0`.
- `All 1112 tests passed.`

### Tests unitarios añadidos
- Parser: `async function` con `await`, arrow async, `async` como identificador.
- Evaluator: await + `.then`, rechazo async capturado con `.catch`, constructor `Promise` + `Promise.all`, y `Promise.all` con resolución diferida.

## Archivos tocados
- `src/lexer.zig`
- `src/ast.zig`
- `src/parser.zig`
- `src/evaluator.zig`
- `src/environment.zig`
- `src/main.zig`
- `src/types/runtime.zig`
- `src/builtins/promise/promise.zig`
- `tests/compat/async-await.lou`
- `tests/compat/async-await.js`
- `README.md`
