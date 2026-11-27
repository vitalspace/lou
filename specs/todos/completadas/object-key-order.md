# Object.keys / JSON.stringify: orden de claves

## status

**completada** — implementada (compat: 90 PASS / 0 FAIL / 0 SKIP,
2026-11-27). `tests/compat/object-key-order.lou` PASS.

## Problema

`for-in` ya enumeraba con [[OwnPropertyKeys]], pero `Object.keys`,
`Object.values`, `Object.entries` y `JSON.stringify` iteraban el
`StringArrayHashMap` en orden de inserción, sin mover los índices enteros
al principio.

```js
Object.keys({b: 1, 0: 2});      // Node: ["0", "b"]  Lou: ["b", "0"]
JSON.stringify({b: 1, 0: 2});   // Node: {"0":2,"b":1} Lou: {"b":1,"0":2}
```

## Implementación

### `src/builtins/object/{keys,values,entries}.zig`

- Reutilizan `ObjectValue.getForInKeys` (el helper de `for-in`), que
  devuelve índices canónicos ascendentes seguidos de strings en orden de
  inserción y salta las claves internas `@@`.
- `keys` devuelve directamente el `ArrayObject` del helper; `values` y
  `entries` recorren esas claves y buscan el valor en `properties`.

### `src/builtins/json/stringify.zig`

- El bloque `.js_object` construye primero las claves ordenadas y luego
  cuenta/serializa sobre ellas (con y sin indentación).
- Si el replacer es un array, el orden de **ese array** define el orden de
  las propiedades (spec JSON.stringify). Para conservarlo, `allowed_keys`
  pasa de `StringHashMap` a `StringArrayHashMapUnmanaged`; se construye
  una lista filtrada en orden del replacer y se usa como claves.

## Verificación

- Fixture `object-key-order` con `Object.keys/values/entries`,
  `JSON.stringify` compacto/indentado y replacer array.
- Test unitario en `keys.zig` (índices primero) y en `evaluator.zig`
  (`JSON.stringify({b:1,0:2})` → `{"0":2,"b":1}`).
