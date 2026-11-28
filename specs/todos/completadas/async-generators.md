# Async Generators y for-await-of

## status
✅ COMPLETADO

## Problema
Los generadores asíncronos (`async function*`) y `for await...of` no estaban implementados. El parser rechazaba `async function*` y `for await`, y el runtime solo conocía generadores síncronos y `Promise` sin integración con iteración.

## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los generadores asíncronos permiten producir valores de forma lazy desde código que espera Promises, y `for await...of` consume iterables síncronos o asíncronos.

## Baseline (al iniciar el spec)
- `GeneratorDeclaration` y `YieldExpression` ya existían.
- `GeneratorObject` y `evaluateGeneratorNext` ya existían, pero solo para generadores síncronos.
- `async`/`await` y `Promise` ya estaban implementados (spec `async-await.md`).
- Faltaban: `async function*`, `for await...of`, `Symbol.asyncIterator` y el envoltorio Promise de `.next()`/`.return()`.
- Los generadores síncronos con `for (let ...)` no reanudaban correctamente: el scope de iteración se perdía y el `yield` se trataba como terminación del loop.

## Arquitectura implementada

### Parser
- `async function* name() {}` y expresiones `const g = async function* () {}` producen un `GeneratorDeclaration` con `is_async = true`.
- `for await (const x of iterable) {}` produce un `ForOfLoop` con `is_await = true`.
- `for await (... in ...)` se rechaza con `error.UnexpectedToken`; la forma válida es `of`.
- `async` sigue siendo contextual: `const async = 1` y `function async() {}` continúan funcionando.

### AST
- `ForOfLoop.is_await: bool = false`.
- `GeneratorDeclaration.is_async: bool = false`.
- `printAst` muestra `Async: true` en generadores y `Await: true` en `for-of`.

### Runtime
- `GeneratorObject.is_async` marca el generador asíncrono.
- `WellKnownSymbol.asyncIterator` y `Symbol.asyncIterator` (`@@asyncIterator` en objetos).
- El entorno persistente del generador guarda `is_generator` e `is_async_generator`.

### Evaluator
- `invokeFunctionNode` copia `is_async` al `GeneratorObject`.
- `.next()` y `.return()` de un generador asíncrono devuelven una `Promise` resuelta con `{ value, done }`; `.throw()` devuelve una `Promise` rechazada con el motivo.
- `yield` dentro de un generador asíncrono espera el valor producido (`yield Promise.resolve(x)` entrega `x`).
- `return` dentro de un generador asíncrono también espera el valor de retorno.
- `yield*` delega en generadores síncronos/asíncronos, arrays, strings y objetos con `@@iterator` o `@@asyncIterator`, esperando cada valor cuando el generador es asíncrono.
- Los errores de un `yield` rechazado se convierten en el rechazo de la Promise de `.next()` con el motivo original.

### `for await...of`
- Se materializan los valores del iterable en un `ArrayObject` antes de ejecutar el cuerpo.
- Se soportan arrays, strings, generadores síncronos/asíncronos, iteradores internos y objetos con `@@asyncIterator` o `@@iterator`.
- Cada valor se pasa por `awaitValue`, por lo que un array de Promises se resuelve elemento a elemento.
- La materialización reutiliza el camino cacheado de `for-of`, lo que conserva la reentrada de `yield`, `break` y `continue` dentro de generadores.

### Fix de loops en generadores síncronos
- Un `for (let i = ...)` dentro de un generador usa un scope de iteración heap (`initIterHeap`) en vez de un scope de stack.
- Al producirse un `yield`, se guarda el scope ya incrementado para que el siguiente `.next()` continúe con el valor correcto.
- El nodo del loop no se limpia si hubo `yield`, y las banderas de yield se propagan desde el scope hijo al entorno del generador.
- Al completarse naturalmente, un generador devuelve `{ value: undefined, done: true }`; solo un `return` explícito aporta un valor.

## Limitaciones conocidas
- No hay event loop real ni timers; los `await` se resuelven en el mismo tick cuando la Promise ya está resuelta o sus trabajos están encolados.
- `for await...of` es eager: consume todo el iterable antes de ejecutar el cuerpo. Un `break` no cierra el iterador y los efectos laterales del generador ocurren antes de la primera salida del cuerpo.
- `.throw()` en un generador asíncrono devuelve una Promise rechazada, pero no inyecta la excepción en el punto de suspensión para que un `try/catch` interno la capture.
- No se soportan métodos generadores asíncronos en objetos o clases (`{ async *gen() {} }`); sí se soportan declaraciones y expresiones `async function*`.
- Los programas con `async`, `await` o `Promise` siguen ejecutándose en el evaluator, no en la VM.

## Verificación

```bash
./zig-out/bin/lou run tests/compat/async-generators.lou
node tests/compat/async-generators.js
diff <(./zig-out/bin/lou run tests/compat/async-generators.lou) \
     <(node tests/compat/async-generators.js)
bash tests/compat/run.sh
zig test src/main.zig
```

Resultados:
- `tests/compat/async-generators.lou` idéntico a Node (`diff` vacío).
- `PASS=102 FAIL=0 SKIP=0`.
- `All 1123 tests passed.`

### Cobertura del fixture
- `.next()` devuelve una Promise y entrega valores de un generador con `await` y `for (let ...)`; el `return` final entrega `"finished"`.
- `for await` sobre un generador asíncrono, un array con Promises, un generador síncrono, un string y un objeto con `Symbol.asyncIterator`.
- Composición con `yield Promise.resolve(...)`, `yield*` sobre otro generador asíncrono y `.return()` anticipado.
- Rechazo de `.next()` por un `yield` rechazado y rechazo de `.throw()` con el motivo original.
- `typeof Symbol.asyncIterator === "symbol"`.

### Tests unitarios añadidos
- Parser: `async function*` marca `GeneratorDeclaration.is_async`; `for await` marca `ForOfLoop.is_await`; `for-of` normal no se marca; `for await (... in ...)` y `for await (;;)` se rechazan.
- Evaluator: `.next()` de generador asíncrono devuelve Promise y entrega valores; `for await` consume un generador asíncrono; `return` con Promise se espera; `yield Promise.reject(...)` rechaza `.next()` con el motivo; un generador síncrono con `for (let ...)` reanuda con el binding incrementado y completa en `undefined`.

## Archivos tocados
- `src/ast.zig`
- `src/parser.zig`
- `src/environment.zig`
- `src/evaluator.zig`
- `src/types/runtime.zig`
- `src/builtins/symbol.zig`
- `src/builtins/symbol/symbol.zig`
- `src/builtins/console/format.zig`
- `tests/compat/async-generators.js`
- `tests/compat/async-generators.lou`
- `README.md`

## Edge cases y seguimiento
- Promover a spec propio el soporte de métodos generadores asíncronos en objetos/clases (`async *method`).
- Promover a spec propio un `for await` lazy con cierre temprano del iterador en `break`/`return`/`throw`.
- Promover a spec propio la inyección real de `.throw()` en el punto de suspensión y el `finally` de generadores asíncronos.
- El fix de loops con `yield` también mejora generadores síncronos; conviene añadir un fixture dedicado de generators con loops si se amplía esa cobertura.