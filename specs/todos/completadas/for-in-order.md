# for-in: orden de enumeración

## status

**COMPLETADO** — verificado 2026-11-26 (compat: 62 PASS / 23 FAIL / 1 SKIP)

`tests/compat/for-in-order.lou` pasa byte-identical contra Node en los 5 casos
(enteros ascendentes, strings en inserción, mezcla, solo strings, solo enteros).

```bash
diff <(./zig-out/bin/lou run tests/compat/for-in-order.lou) \
     <(node tests/compat/for-in-order.js) && echo OK
```

## Problema

`for-in` iteraba el `StringArrayHashMap` directamente, es decir, en orden de
inserción: `{b:1, 0:3, a:2}` daba `b,0,a` en vez de `0,b,a`. ECMAScript
(14.7.5.9 / [[OwnPropertyKeys]]) exige índices de array ascendentes primero y
después el resto de claves string en orden de inserción.

## Causa real: drift entre spec y código

`ObjectValue.getForInKeys()` **ya existía** en `src/types/runtime.zig`, con
seis unit tests propios, y el spec anterior se había marcado resuelto el
2026-06-23 asegurando que el opcode de la VM y el evaluador lo usaban. No era
cierto: `get_for_in_keys` (`src/vm.zig`) construía el array de claves inline
iterando el mapa, y `ForInLoop` (`src/evaluator.zig`) iteraba el mapa también.
El helper estaba muerto y el fixture seguía FAIL pese al spec en `hechos/`.

## Solución

- `src/vm.zig` (`.get_for_in_keys`): en la rama `.js_object` usa
  `obj.getForInKeys(env.allocator, &env.arrays)`; el array ya queda registrado
  en `env.arrays` dentro del helper, así que no se vuelve a apilar.
- `src/evaluator.zig` (`.ForInLoop`): itera `ordered.elements.items` en vez de
  `obj.properties.iterator()`.
- `src/types/runtime.zig` (`getForInKeys`): además de canonicalidad y del skip
  de claves internas `@@`, ahora exige `num < 4294967295`; según ES
  `4294967295` y mayores son claves string, no array indices.
- Unit test nuevo para ese límite (`getForInKeys: 4294967295 is a string key`).

## Gotchas

- `{b:1, 0:3, a:2}` → `0,b,a`; `{z,a,10,2,m}` → `2,10,z,a,m`.
- `{a:1, 4294967295:2, b:3}` → `a,4294967295,b` (`4294967295` no es índice).
- `"007"`, `"1e2"`, `"+5"` no son canónicos: se tratan como strings.
- Las claves internas `@@...` (Map/Set) no se enumeran.
- `for-in` todavía no recorre la cadena de prototipos; `Object.keys` y
  `JSON.stringify` siguen en orden de inserción (ver
  `../pendientes/object-key-order.md`).

## Tests

- `tests/compat/for-in-order.{js,lou}` (5 casos).
- 7 unit tests de `getForInKeys` en `src/types/runtime.zig`.
- `zig build test` incluye el fixture en la suite de compatibilidad.
