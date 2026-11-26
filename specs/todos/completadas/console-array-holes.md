# Huecos de array: formato `<empty>` vs `<N empty items>`

## status

**COMPLETADO** — verificado 2026-11-26 (compat: 59 PASS / 26 FAIL / 1 SKIP)

`console.log` agrupa los huecos contiguos como V8 (`<1 empty item>` / `<N empty items>`), y
`tests/compat/delete-operator.lou` pasa. Se arreglaron además dos fugas del mismo bug: leer un
hueco (`a[0]`) devuelve `undefined` en vez de `<empty>`, y el spread de arrays materializa
`undefined` en vez de propagar huecos.

## Problema

El formateador imprimía un `<empty>` por cada hueco (`src/builtins/console/format.zig`),
mientras que V8 agrupa huecos consecutivos en un solo token con conteo y plural:

```js
console.log([1,,3]);         // [ 1, <1 empty item>, 3 ]
console.log([,]);            // [ <1 empty item> ]
console.log([1,,,4]);        // [ 1, <2 empty items>, 4 ]
console.log(new Array(3));   // [ <3 empty items> ]
console.log([1,undefined,3]);// [ 1, undefined, 3 ]   (undefined no es hueco)
```

## Solución

- `src/builtins/console/format.zig`: nuevos `printHoleRun` y `holeRunWidth`;
  `printArrayInline` y `printArrayWrapped` recorren con índice y agrupan runs de `.hole`;
  `shouldFormatArrayWrapped` mide el ancho agrupado para decidir el wrap.
- `src/vm.zig`: nuevo `arrayGet`, que mapea `.hole` a `undefined`; `index_get` ya no devuelve
  el `.hole` crudo.
- `src/evaluator.zig`: el spread de un array (`[...[1,,3]]`) convierte huecos a `undefined`,
  que es lo que hace el ArrayIterator de Node.

## Quick verify

```bash
diff <(./zig-out/bin/lou run tests/compat/array-holes.lou) <(node tests/compat/array-holes.js)
```

## Gotchas

- `undefined` no es hueco: nunca se agrupa con ellos.
- El token completo va en gris (`ansi.Gray`), como el `undefined` de Node.
- El spread en argumentos de llamada (`f(...[1,,3])`) sigue sin ejecutar la llamada: es un bug
  aparte de call/apply/bind, no de huecos.

## Tests

- `tests/compat/array-holes.lou` + `.js` (nuevo): formato, `new Array(n)`, arrays sparse,
  lectura de huecos y spread.
- `tests/compat/delete-operator.lou` cubre `delete arr[i]` seguido de `console.log`.
