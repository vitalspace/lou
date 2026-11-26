# Builtins: propagación de throws

## status

**pendiente** — detectado 2026-11-26 mientras se arreglaba `map-groupby`
(compat: 63 PASS / 22 FAIL / 1 SKIP)

Quedan dos familias de builtins que se tragan el throw:

## 1. Callbacks de iteración

```js
try { [1].forEach(function () { throw new Error("x"); }); }
catch (e) { console.log("caught", e.message); }
// Node: caught x     Lou: sigue de largo
```

Pasa igual con `Array.prototype.map` y `Map.prototype.forEach`. Los builtins
ejecutan el callback con un `Environment` propio y no copian
`func_env.throw_hit`/`throw_value` al `env` del caller. `Map.groupBy` y
`Object.groupBy` sí lo hacen (ver `../completadas/map-groupby.md`) y la VM ya
enruta `env.throw_hit` a su handler (`VM.deliverBuiltinThrow`).

Arreglo: en cada builtin que invoca callbacks (`src/builtins/array/*.zig`,
`src/builtins/map/*.zig`), tras `evaluate(...)` comprobar `func_env.throw_hit`
y, si está puesto, copiarlo al env del caller y devolver `.void` antes de
seguir iterando. Patrón de referencia: `MapGroupBy`.

## 2. `BigInt` con string inválido

```js
BigInt("abc");   // Node: SyntaxError: Cannot convert abc to a BigInt
                  // Lou : undefined
```

`BigIntValue.fromString` ya rechaza el string; el builtin hace
`catch return .{ .value = .{ .void = {} } }` en `src/builtins/bigint/bigint.zig:19`.
Cambiarlo por `throwError(env, "SyntaxError", ...)` con el mensaje de Node para
que `deliverBuiltinThrow` lo enrute a `try/catch`.

## Tests

- Fixture nuevo `builtin-callback-throws.{js,lou}`: `forEach`/`map`/
  `Map.forEach` con callback que lanza, y `BigInt("abc")` dentro de `try/catch`.
- `zig build test` no debe perder los unit tests de los builtins tocados.
