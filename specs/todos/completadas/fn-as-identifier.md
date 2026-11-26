# `fn` como identificador

## status

**COMPLETADO** — verificado 2026-07-30

`fn-as-identifier.lou` PASSes with byte-identical output to Node.js. Removed `fn` from lexer keyword map (Opción A del spec `fn-keyword-identifier.md`). Updated tests.

## Problema

En Lou, `fn` es tratado como keyword que siempre inicia una declaración de función (`function`). Pero en JavaScript, `fn` no es una palabra reservada — es un identificador válido.

El test `fn-as-identifier.lou` espera que `fn` pueda ser usado como:
- Nombre de variable: `var fn = 5;`
- Nombre de propiedad: `obj.fn = 5;`
- Parámetro de función: `function(fn) {}`

## Contexto

La issue fue documentada en el spec `fn-keyword-identifier.md`. Hay dos opciones:

- **Opción A**: Eliminar `fn` del keyword map en el lexer (`src/lexer.zig`). `function` queda como la única keyword para function declarations/expressions. Esta opción está documentada como "aplicada" en el spec, pero el test sigue fallando.

- **Opción B**: Mantener `fn` como keyword (función Lou-only) y ajustar el parser para que no lo trate como función en posiciones donde un identificador es más probable.

El test actual falla con error de parseo porque `fn` se tokeniza como `.Fn` y el parser espera `function` declarations.

## Código que falla

```js
var fn = 5;
console.log(fn);  // Should print: 5 (FAILs with parse error)
```

## Dependencias

- `specs/todos/hechos/fn-keyword-identifier.md` — spec que documenta las opciones de implementación

## Verificación

```bash
./zig-out/bin/lou run tests/compat/fn-as-identifier.lou 2>&1
node tests/compat/fn-as-identifier.js 2>&1
diff <(./zig-out/bin/lou run tests/compat/fn-as-identifier.lou 2>&1) <(node tests/compat/fn-as-identifier.js 2>&1)
```
