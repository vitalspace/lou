# Object.keys / JSON.stringify: orden de claves

## status

**pendiente** — detectado 2026-11-26 mientras se arreglaba `for-in-order`
(compat: 62 PASS / 23 FAIL / 1 SKIP)

`for-in` ya enumera con el orden de ECMAScript (`getForInKeys`), pero
`Object.keys` y `JSON.stringify` siguen iterando el `StringArrayHashMap` en
orden de inserción. Node usa [[OwnPropertyKeys]] en los tres casos, así que los
índices enteros deben salir primero y en orden ascendente.

```js
Object.keys({b: 1, 0: 2});      // Node: ["0", "b"]  Lou: ["b", "0"]
JSON.stringify({b: 1, 0: 2});   // Node: {"0":2,"b":1} Lou: {"b":1,"0":2}
JSON.stringify({2: 1, 1: 2});   // Node: {"1":2,"2":1} Lou: {"2":1,"1":2}
```

## Solución sugerida

Extraer de `getForInKeys` un helper `ObjectValue.orderedKeys(allocator)` que
devuelva `[]const []const u8` (índices ascendentes + strings en inserción,
saltando `@@`) y reutilizarlo en:

- `src/builtins/object/keys.zig` (`Object.keys`)
- el serializador de objetos de `src/builtins/json/stringify.zig`
- `getForInKeys`, que solo tendría que envolver el resultado en un `ArrayObject`

## Gotchas

- `4294967295` y mayores son claves string, no array indices.
- `"007"`, `"1e2"`, `"+5"` no son canónicos.
- Filtrar claves internas `@@` en los tres consumidores.
- `JSON.stringify` de arrays no cambia (los índices ya van en orden).

## Tests

Añadir un fixture `object-key-order.{js,lou}` que cubra `Object.keys`,
`JSON.stringify`, `Object.entries` y el límite `4294967295`.
