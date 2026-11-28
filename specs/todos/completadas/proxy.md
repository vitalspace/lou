# Proxy

## status
✅ COMPLETADO

## Problema
`Proxy` no existía. `new Proxy(target, handler)` fallaba con `Proxy is not defined` y no era posible interceptar lecturas, escrituras, búsquedas, borrados, llamadas ni construcciones.

## Contexto

Lou es un intérprete JavaScript escrito en Zig. El runtime ya tenía `ObjectValue` con `properties`, prototipo, flags de extensibilidad y accessors, además de `MemberAccess`, `ArrayIndex`, `MethodCall`, `FunctionCall`, `NewExpression`, asignaciones, `in` y `delete`. Todo eso pasaba directamente al objeto, sin punto de intercepción.

## Baseline (al iniciar el spec)
- `Proxy` no estaba registrado como builtin.
- `new Proxy({}, {})` fallaba con `Proxy is not defined`.
- No existía `src/builtins/proxy.zig`.
- Las operaciones de propiedad se resolvían directamente sobre `ObjectValue` en el evaluador; el VM no tiene soporte de proxy.
- `typeof` no reconocía objetos internos callables salvo los ya marcados con `@@callable`.

## Implementación

### Representación
- El proxy es un `.js_object` normal con propiedades internas:
  - `@@type = "Proxy"`
  - `@@proxy_target`
  - `@@proxy_handler`
  - `@@callable` cuando el target es función/clase/bound function.
- No se agregó una variante nueva a `Value`, así que no hubo que tocar todos los switches ni `freeValue`.
- `src/builtins/proxy.zig` expone `isProxy`, `getTarget`, `getHandler`, `ProxyConstructor` y `PROXY_OBJECT`.

### Builtin
- `ProxyConstructor` valida que target y handler sean objetos y registra el proxy en `env.objects`.
- Registrado en `BUILTIN_FUNCTIONS` como `Proxy` y en `BUILTIN_OBJECTS` como namespace sin métodos estáticos.
- `Proxy.name` devuelve `"Proxy"`.
- `typeof Proxy` devuelve `"function"` aunque el namespace interno sea un builtin object.
- `Proxy(...)` sin `new` lanza `TypeError: Constructor Proxy requires 'new'`.

### Traps implementados
Se implementaron seis traps:
- `get(target, prop, receiver)`
- `set(target, prop, value, receiver)`
- `has(target, prop)`
- `deleteProperty(target, prop)`
- `apply(target, thisArg, args)`
- `construct(target, args, newTarget)`

Cada trap se invoca con `this` igual al handler. Si el trap no existe, la operación se aplica al target. Si el trap existe pero no es callable, se lanza `TypeError`.

### Puntos de intercepción
- `MemberAccess` y `ArrayIndex` en el evaluador.
- `ocMember` y `ocIndex` para optional chaining y helpers internos.
- `MethodCall` para receptores proxy, incluyendo cadenas de método.
- `FunctionCall`, `callFunctionValue` y `ocCall` para `apply`.
- `NewExpression` para `construct`.
- Asignación simple, compuesta, lógica y `++`/`--` para `set` y `get`.
- `DeleteExpression` para `deleteProperty`.
- Operador `in` para `has`.
- Lecturas y escrituras indexadas (`p["x"]`, arrays proxy).

### Routing
- `src/main.zig` agrega `"Proxy"` a `needs_evaluator`, por lo que los programas que usan Proxy se ejecutan en `src/evaluator.zig` y no en el VM.

## Limitaciones conocidas
- Solo están implementados 6 de los 13 traps. Faltan `getPrototypeOf`, `setPrototypeOf`, `isExtensible`, `preventExtensions`, `ownKeys`, `defineProperty` y `getOwnPropertyDescriptor`.
- No está implementado `Proxy.revocable()`.
- No hay soporte de Proxy en el VM; los programas con Proxy se derivan al evaluador.
- Los invariantes de proxy (target no extensible, propiedades no configurables, proxy revocado) no se validan.
- En un proxy de array funcionan lecturas/escrituras por índice y `length`, pero no los métodos de array a través del proxy (`push`, `map`, etc.).
- Las propiedades extra de arrays proxificados no se propagan al target.
- Las propiedades arbitrarias sobre funciones proxificadas no se almacenan.
- `Object.keys`, `for...in` y `JSON.stringify` no consultan el target ni un trap `ownKeys`; ven las propiedades internas ocultas del wrapper.
- `console.log(proxy)` imprime `{}` para un proxy de `{ a: 1 }`, mientras Node imprime `{ a: 1 }`.
- En modo no estricto, un trap `set` que devuelve `false` no lanza; la asignación devuelve el valor pero no escribe en el target.

## Verificación

```bash
./zig-out/bin/lou run tests/compat/proxy.lou
node tests/compat/proxy.js
diff <(./zig-out/bin/lou run tests/compat/proxy.lou) \
     <(node tests/compat/proxy.js)
bash tests/compat/run.sh
zig test src/main.zig
```

Resultados:
- Fixture `proxy.lou` idéntico a Node (`diff` vacío).
- `PASS=104 FAIL=0 SKIP=0`.
- `All 1129 tests passed.`

### Cobertura del fixture
- `typeof Proxy` y `Proxy.name`.
- `get` con fallback a `"default"`.
- `set` con log y escritura en el target.
- `has`, incluyendo una propiedad ocultada por el trap.
- `deleteProperty` y verificación posterior con `in`.
- Borrado de propiedades ausentes y de índices fuera de rango (devuelven `true`); `delete length` devuelve `false`.
- Lectura/escritura por corchetes, asignación compuesta e incremento.
- Proxy de array: índice y `length`, escritura de un índice nuevo.
- `apply` con trap y pass-through sin trap.
- `construct` con trap y pass-through sin trap.
- Método a través de proxy conservando `this`.
- Proxy anidado (proxy de proxy).
- `set`/`deleteProperty` que devuelven `false`.
- Errores de target primitivo y de `Proxy(...)` sin `new`.

### Tests unitarios añadidos
- El constructor guarda target/handler y `isProxy` lo reconoce.
- Rechaza targets primitivos con `TypeError`.
- Marca targets callables con `@@callable`.
- Test de integración del evaluador: get/set/has/delete/apply/construct y orden de traps.

## Archivos tocados
- `src/builtins/proxy.zig`
- `src/builtins/builtins.zig`
- `src/builtins/builtinObjects.zig`
- `src/evaluator.zig`
- `src/main.zig`
- `tests/compat/proxy.js`
- `tests/compat/proxy.lou`
- `README.md`

## Edge cases y seguimiento
- Implementar los siete traps restantes y `Proxy.revocable()` en un spec propio.
- Integrar `ownKeys`, `getOwnPropertyDescriptor` y `defineProperty` con `Object.keys`, `for...in`, `JSON.stringify` y descriptores.
- Soportar métodos de array a través de proxy y propiedades extra.
- Evaluar si el VM necesita soporte de Proxy o si el routing al evaluador es suficiente a largo plazo.
- Validar invariantes de proxies no extensibles/no configurables/revocados.
