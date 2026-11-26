# Igualdad abstracta (==) vs estricta (===)

## status

**completado** — 2026-11-26 (compat: 66 PASS / 19 FAIL / 1 SKIP)

`tests/compat/equality-coercion.{js,lou}` produce output byte-idéntico a Node.
El archivo estaba mal clasificado en `hechos/` mientras el test seguía en FAIL;
ahora el spec vive aquí y la suite lo verifica.

```bash
diff <(./zig-out/bin/lou run tests/compat/equality-coercion.lou) <(node tests/compat/equality-coercion.js)
# sin diferencias
```

## Problema original

`==` se comportaba igual que `===`: no había coerción. Los helpers
`looseValuesEqual` (evaluador) y `valEq` (VM) existían pero les faltaban
casos clave:

- `0 == ""` → `false` (el string vacío debe convertir a `0`)
- `1 == 1.0` → `false` (integer y float son el mismo tipo Number en JS)
- `[] == 0`, `[1] == 1`, `[] == ""`, `[1,2] == "1,2"` → `false` (faltaba
  `ToPrimitive` para arrays/objetos)
- `o == o` → `false` para objetos (`js_object`) y closures, porque la
  igualdad estricta no comparaba identidad en esas variantes

## Implementación

### `src/coercion.zig` (nuevo)

Módulo compartido por evaluador y VM:

- `stringToNumber`: `ToNumber` de strings al estilo ECMAScript (vacío y
  whitespace → `0`, `Infinity`, hex/binario/octal, decimales; resto NaN).
- `appendToString` / `toPrimitiveString`: `ToString` de primitivos y
  `ToPrimitive(default)` para arrays (join con `,`, null/undefined/holes como
  vacío) y objetos (`toString` si es string, si no `[object Object]`).
- `isObjectLike`: arrays, `js_object`, `object` y regexp.

### Igualdad abstracta (ES 7.2.14)

Mismo algoritmo en `looseValuesEqual` y `valEq`:

1. mismo tag → igualdad estricta (con identidad de punteros para
   arrays/objetos/funciones/closures/js_object/regexp/iteradores/generadores);
2. Number ↔ Number entre tags `integer`/`float`;
3. `null == undefined`; `null`/`undefined` contra cualquier otra cosa → false;
4. Boolean → 0/1 y recursión;
5. objeto ↔ primitivo → `ToPrimitive`, recursión con el string resultante;
6. BigInt ↔ String (parseo BigInt), Number ↔ String (`stringToNumber`),
   BigInt ↔ Number (solo si el número es entero exacto).

### Igualdad estricta

`valuesEqual` y `valStrictEq` ahora comparan identidad para todos los valores
de objeto: `array`, `object`, `function`, `closure`, `js_object`, `regexp`,
`iterator`, `array_iterator` y `generator`.

## Tests

- `tests/compat/equality-coercion.{js,lou}` — 30 casos: cadenas de coerción,
  null/undefined, objetos/arrays, `1 == 1.0`, `0 == -0`, `!==` y NaN.
- Casos extra verificados contra Node: `[[]] == ""`, `[[1]] == "1"`,
  `[null] == ""`, `o == o`, `{} == {}`, `f == f`, `true == 2`.
- `src/coercion.zig`: 3 tests (`stringToNumber`, join de arrays).
- `src/evaluator.zig`: 1 test de `looseValuesEqual` (number/string/bool).

## Limitaciones conocidas

- `ToPrimitive` no invoca `valueOf`/`toString` definidos por el usuario; usa
  el string del array o, para objetos, la propiedad `toString` si ya es un
  string, o `[object Object]`.
- Las funciones no se convierten a su código fuente en `==` contra un
  primitivo (la identidad `f == f` sí funciona).
- `Date`/`RegExp` usan el fallback de `[object Object]` en igualdad laxa.

## Referencias

- `src/coercion.zig`
- `src/evaluator.zig` (`valuesEqual`, `looseValuesEqual`)
- `src/vm.zig` (`valStrictEq`, `valEq`)