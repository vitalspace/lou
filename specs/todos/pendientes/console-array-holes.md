# Huecos de array: formato `<empty>` vs `<N empty items>`

## status

**pendiente** — detectado 2026-11-26 por el barrido `./bench.sh compat`.

`tests/compat/delete-operator.lou` falla **solo** por esto: tras `delete arr[1]`, Lou imprime
`[ 1, <empty>, 3, 4 ]` y Node imprime `[ 1, <1 empty item>, 3, 4 ]`.

## Problema

El formateador de console imprime un `<empty>` por cada hueco
(`src/builtins/console/format.zig:277`), mientras que V8 agrupa huecos consecutivos en un
solo token con conteo y plural:

```js
console.log([1,,3]);         // [ 1, <1 empty item>, 3 ]
console.log([,]);            // [ <1 empty item> ]
console.log([1,,,4]);        // [ 1, <2 empty items>, 4 ]
console.log(new Array(3));   // [ <3 empty items> ]
console.log([1,undefined,3]);// [ 1, undefined, 3 ]   (undefined no es hueco)
```

## Contexto

- Util.inspect de Node agrupa cada run contiguo de huecos: `<1 empty item>` o
  `<N empty items>` si N > 1. No agrupa huecos separados por valores.
- `JSON.stringify` ya coincide (`null` para huecos): no tocar.

## Baseline (qué existe ya)

- `src/builtins/console/format.zig:277` — `.hole => out.print("{s}<empty>{s}")`.
- `printArray`, `printArrayInline` y `printArrayWrapped` recorren `a.elements.items` y
  delegan en `printValueCtx`, que no conoce a los vecinos.

## Quick verify (estado actual)

```bash
cat > /tmp/holes.js <<'EOF'
console.log([1,,3]);
console.log([,]);
console.log([1,,,4]);
console.log(new Array(3));
EOF
./zig-out/bin/lou run /tmp/holes.js
node /tmp/holes.js
```

Actual: Lou imprime `<empty>` suelto por cada hueco; Node agrupa y pluraliza.

## Gotchas

- `undefined` no es hueco: nunca agruparlo con ellos.
- El color gris (`Gy`) que hoy usa `.hole` debe conservarse.
- Leer un hueco (`a[0]`) devuelve hoy un `.hole` y se imprime `<empty>`; Node devuelve
  `undefined`. Es un bug relacionado, pero de lectura, no de formato (ver `in-operator`).

## Implementacion sugerida

- Detectar runs de `.hole` al recorrer el array (en `printArrayInline`/`printArrayWrapped`),
  no en `printValueCtx`, que no tiene acceso a los vecinos.
- Emitir `<{d} empty item{s}>`: sufijo `s` solo si N > 1.
- Añadir un helper `printHoleRun(out, n, color)` para no duplicar el formato en las dos
  variantes de impresión.

## Tests

- `tests/compat/delete-operator.lou` cubre el caso básico y debe pasar tras el fix.
- Añadir `tests/compat/array-holes.lou` + `.js` con `[1,,3]`, `[,]`, `[1,,,4]`,
  `new Array(3)`, `[1,undefined,3]`, varios arrays anidados con huecos y `[,].length`.
