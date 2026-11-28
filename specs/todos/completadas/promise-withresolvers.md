# Promise.withResolvers

## status
✅ COMPLETADO

## Problema
`Promise.withResolvers()` (ES2024) no estaba implementado. Era la única pieza pendiente de la API estática de `Promise`.

## Contexto

Lou es un intérprete JavaScript escrito en Zig. `PromiseWithResolvers` devuelve una Promise pendiente junto con las funciones `resolve` y `reject` que la controlan, sin necesidad de escribir el executor de `new Promise(...)`.

## Baseline (al iniciar el spec)
- `Promise` ya existía con `then`, `catch`, `finally`, `resolve`, `reject`, `all`, `allSettled`, `race` y `any`.
- El runtime ya tenía `createPending`, `createResolved`, `createRejected`, `makeResolver` y `callResolver`.
- `Promise.withResolvers` no estaba en `PROMISE_METHODS`.
- `typeof` reportaba los resolvers como `"object"` aunque fueran invocables.

## Implementación

### Builtin
- Nuevo `PromiseWithResolvers` en `src/builtins/promise/promise.zig`.
- Crea una Promise pendiente con `createPending`.
- Crea `resolve` y `reject` con `makeResolver`, ambos cerrando sobre la misma Promise.
- Devuelve un objeto plano con las propiedades en orden `promise`, `resolve`, `reject`.
- Registrado como método estático `withResolvers` en `PROMISE_METHODS`.

### Semántica de settlement
- Primera llamada gana: una resolución posterior ignora `reject`, y viceversa.
- `resolve(value)` con una Promise nativa adopta su estado, incluso si sigue pendiente.
- `resolve()` y `reject()` sin argumentos usan `undefined`.
- Los resolvers funcionan aunque se extraigan del objeto o se renombren por destructuring.
- Cada llamada a `Promise.withResolvers()` crea una Promise y resolvers independientes.

### `typeof`
- `typeof` ahora reporta `"function"` para cualquier objeto interno marcado con `@@callable`, incluido `PromiseResolver`.
- Esto aplica también a los resolvers que recibe el executor de `new Promise(...)`.

## Limitaciones conocidas
- No hay event loop ni timers reales; los `await` se resuelven con la cola determinista de microtareas existente.
- Solo se asimilan Promises nativas: un thenable genérico se guarda como valor, no se invoca.
- Los resolvers son objetos callables internos; no exponen metadatos de `Function` como `.name` o `.length`.

## Verificación

```bash
./zig-out/bin/lou run tests/compat/promise-withresolvers.lou
node tests/compat/promise-withresolvers.js
diff <(./zig-out/bin/lou run tests/compat/promise-withresolvers.lou) \
     <(node tests/compat/promise-withresolvers.js)
bash tests/compat/run.sh
zig test src/main.zig
```

Resultados:
- Fixture `promise-withresolvers.lou` idéntico a Node (`diff` vacío).
- `PASS=103 FAIL=0 SKIP=0`.
- `All 1125 tests passed.`

### Cobertura del fixture
- Tipos de `promise`, `resolve` y `reject`; `promise instanceof Promise`.
- Resolución básica, rechazo con `Error`, y primera llamada gana en ambos sentidos.
- Dos llamadas independientes.
- Adopción de una Promise pendiente resuelta después.
- `resolve()`/`reject()` sin argumentos.
- Resolver extraído del objeto.
- Destructuring con alias.
- Orden de propiedades con `Object.keys`.

### Tests unitarios añadidos
- `Promise.withResolvers` resuelve/rechaza promesas independientes y respeta la primera llamada.
- Adopta una Promise pendiente y expone resolvers con `typeof === "function"`.

## Archivos tocados
- `src/builtins/promise/promise.zig`
- `src/evaluator.zig`
- `tests/compat/promise-withresolvers.js`
- `tests/compat/promise-withresolvers.lou`
- `README.md`

## Edge cases y seguimiento
- Si se necesita compatibilidad total con `Function.prototype` para resolvers, promover un spec de metadatos de funciones internas.
- La asimilación de thenables genéricos corresponde a un spec propio del Promise runtime.
- Los timers del ejemplo original siguen fuera de alcance; el fixture usa resoluciones síncronas y microtareas.