# BigInt — Loose equality (==) con coerción

## status

**COMPLETADO** — verificado 2026-11-26 (compat: 61 PASS / 24 FAIL / 1 SKIP)

`tests/compat/bigint-loose-eq.lou` pasa byte-identical. Fallaban dos tramos de ECMAScript
7.2.14 `IsLooselyEqual`: la coerción Booleano→Número→BigInt (`1n == true`) y la de
String→BigInt (`0n == "0.0"` daba `true` porque se parseaba como número).

```bash
diff <(./zig-out/bin/lou run tests/compat/bigint-loose-eq.lou) \
     <(node tests/compat/bigint-loose-eq.js) && echo OK
```

## Problema

1. **Boolean ↔ BigInt**: el bloque BigInt↔Number intentaba `coerceNumberToBigInt` con el
   booleano, fallaba y hacía `return false` antes de llegar al paso Boolean→ToNumber. Resultado:
   `1n == true`, `0n == false`, `false == 0n` y `true == 1n` daban `false`.
2. **BigInt ↔ String**: se usaba `std.fmt.parseFloat`, así que `"0.0"`, `"1.0"` y `"0e0"`
   parseaban a 0/1 y comparaban iguales. `BigIntValue.fromString` tampoco aceptaba `""`,
   espacios ni prefijos `0x`/`0o`/`0b` (`BigInt("0x10")` devolvía `undefined`).

## Solución

- `src/vm.zig` (`valEq`) y `src/evaluator.zig` (`looseValuesEqual`), mismo orden:
  Boolean→número se aplica **antes** de los bloques BigInt; BigInt↔String usa
  `BigIntValue.fromString` (sintaxis de entero, sin `.`/`e`/`n`); el bloque BigInt↔Number solo
  actúa cuando el otro lado es `integer`/`float`.
- `src/types/runtime.zig` (`BigIntValue.fromString`): recorta whitespace, `""` → `0n`, acepta
  prefijos `0x`/`0o`/`0b`, y el signo solo vale en decimal (`BigInt("-0x10")` → inválido).

## Gotchas

- `1n == 1.0` → `true` (entero exacto); `1n == 1.5` → `false`.
- `0n == NaN` → `false` (NaN nunca es igual).
- `0n == ""` y `0n == " 0 "` → `true`; `16n == "0x10"` → `true`; `0n == "0.0"` → `false`.
- Objetos siguen sin ToPrimitive: `0n == {}` es `false` y `0n == []` debería ser `true`, pero
  queda fuera, igual que el resto de `==` con objetos.

## Tests

- `tests/compat/bigint-loose-eq.lou` + `.js`: 75 líneas con number/string/boolean/float/null/NaN,
  simetría, `!=`, `===` y strings inválidos.
- `zig build test` incluye el fixture en la suite de compatibilidad.
