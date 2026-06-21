# BigInt.asIntN / BigInt.asUintN

## status
implementado

## Problema
`BigInt.asIntN(bits, bigint)` y `BigInt.asUintN(bits, bigint)` no están implementados. Son funciones estáticas de BigInt para truncar a un número fijo de bits.

## Contexto
- `BigInt.asIntN(bits, n)` — retorna un BigInt del mismo valor que `n` módulo 2^bits, interpretado como entero con signo.
- `BigInt.asUintN(bits, n)` — retorna un BigInt del mismo valor que `n` módulo 2^bits, interpretado como entero sin signo.

Per ES spec (sec-bigint.asintn, sec-bigint.asuintn):
- `asUintN(bits, n)` = `n mod 2^bits` (always non-negative, `[0, 2^bits)`).
- `asIntN(bits, n)` = if `n mod 2^bits >= 2^(bits-1)`, then `n mod 2^bits - 2^bits`, else `n mod 2^bits` (range `[-2^(bits-1), 2^(bits-1))`).
- For `bits == 0`, the result is always `0n`.

## Código que falla
```js
console.log(BigInt.asIntN(8, 255n));    // -1n (255 mod 256, signed)
console.log(BigInt.asUintN(8, 255n));   // 255n
console.log(BigInt.asUintN(8, -1n));    // 255n
console.log(BigInt.asIntN(8, 128n));    // -128n
```

## Implementacion

### Builtins (src/builtins/bigint/bigint.zig)

Añadidos `BigIntAsUintN` y `BigIntAsIntN` y registrados en `BIGINT_METHODS`
junto a `toString`/`valueOf`/`toLocaleString`.

Algoritmo común:
1. Extraer `bits` de `args[0]`. Si no es integer no-negativo, retornar `void`.
2. Validar que `args[1]` sea `big_int`; si no, retornar `void`.
3. Calcular `modulus = 2^bits` con `BigIntValue(1).shiftLeft(bits)`.
4. Calcular `r = n mod modulus` usando `Managed.divFloor(q, r, n, modulus)`.
   - `Managed.divFloor` siempre produce `r >= 0` (con `0 <= r < |modulus|`),
     por lo que sirve directamente como `asUintN`.
5. Para `asIntN`, comparar `r >= 2^(bits-1)`. Si es cierto, restar `modulus`
   para envolver el resultado al rango negativo.
6. Edge case `bits == 0`: retornar `0n` directamente.

```zig
pub fn BigIntAsUintN(args, env) BuiltinResult {
    if (args.len < 2) return void;
    const bits: usize = switch (args[0]) {
        .integer => |i| if (i < 0) 0 else @intCast(i),
        else => return void,
    };
    if (args[1] != .big_int) return void;
    const n = args[1].big_int;

    const modulus = fromString("1");  // shiftLeft by `bits` → 2^bits
    env.bigints.append(modulus);

    const result = fromString("0");
    env.bigints.append(result);
    var quot = fromString("0");
    env.bigints.append(quot);
    quot.value.divFloor(&result.value, &n.value, &modulus.value);  // result = n mod 2^bits
    return .{ .big_int = result };
}

pub fn BigIntAsIntN(args, env) BuiltinResult {
    // ... same setup, then:
    // 1. result = n mod 2^bits  (same as asUintN)
    // 2. half = 2^(bits-1)
    // 3. if result >= half: result -= modulus  (sign-correct)
    // 4. if bits == 0: skip step 3, return 0n
}
```

No hay cambios en `builtinObjects.zig` — el registro de los métodos se hace
directamente en `BIGINT_METHODS` (que ya estaba conectado a `BIGINT_OBJECT`).

## Tests

Compat test `tests/compat/bigint-asintn-asuintn.{js,lou}`. Cubre:
- `asIntN(8, ...)` basics (255n, 128n, 127n, 0n)
- `asUintN(8, ...)` basics (255n, -1n, 256n, -2n)
- 64-bit boundaries (`2^63-1`, `2^63`, `2^64-1`, `2^64`, `-1n`)
- `bits == 0` → `0n`
- `bits == 1` → signed/unsigned single-bit wrap
- Más allá de i64 (128-bit, 200-bit con BigInts grandes)
- Round-trip: `asUintN(bits, asIntN(bits, n)) === n mod 2^bits`
- Negativos asIntN (`-128n`, `-129n`)

Tests unitarios añadidos en `bigint.zig`:
- `BigInt.asIntN 8 bits signed boundary`
- `BigInt.asIntN 64 bits full range`
- `BigInt.asUintN 8 bits unsigned boundary`
- `BigInt.asUintN 64 bits full range`
- `BigInt.asUintN larger than i64`
- `BigInt.asIntN bits zero returns 0`
- `BigInt.asIntN round trip via asUintN`
- 4 tests de error handling (missing args, non-BigInt second arg)

`zig build test`: 908/908 ✓. Compat test pasa idéntico a Node.js.

## Archivos de referencia
- src/builtins/bigint/bigint.zig — `BigIntAsUintN`, `BigIntAsIntN`, `BIGINT_METHODS`
- tests/compat/bigint-asintn-asuintn.js, .lou

### JS Examples Complejos (validados contra Node.js)
```js
// Wrap-around behavior
console.log(BigInt.asIntN(8, 255n));     // -1n
console.log(BigInt.asIntN(8, 128n));     // -128n
console.log(BigInt.asUintN(8, -1n));     // 255n
console.log(BigInt.asUintN(8, 256n));    // 0n

// 64-bit signed range
console.log(BigInt.asIntN(64, 2n**63n - 1n));   // 9223372036854775807n
console.log(BigInt.asIntN(64, 2n**63n));        // -9223372036854775808n

// 64-bit unsigned range
console.log(BigInt.asUintN(64, -1n));           // 18446744073709551615n
console.log(BigInt.asUintN(64, 2n**64n - 1n));  // 18446744073709551615n

// Beyond i64
console.log(BigInt.asIntN(128, 2n**127n));      // -170141183460469231731687303715884105728n
console.log(BigInt.asUintN(200, 123456789012345678901234567890n));  // 123456789012345678901234567890n

// Round-trip
const signed = BigInt.asIntN(8, -42n);
console.log(signed);                            // -42n
console.log(BigInt.asUintN(8, signed));         // 214n

// bits == 0
console.log(BigInt.asIntN(0, 5n));              // 0n
console.log(BigInt.asUintN(0, 5n));             // 0n
```

### Verificacion
```bash
zig build test                                       # 908/908
./zig-out/bin/lou run tests/compat/bigint-asintn-asuintn.lou
node tests/compat/bigint-asintn-asuintn.js
bash tests/compat/run.sh
```

Diff esperado: ninguna línea difiere para el compat test (todos los casos
principales coinciden con Node.js v25).

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/bigint-asintn-asuintn.lou 2>&1 | od -c
node tests/compat/bigint-asintn-asuintn.js 2>&1 | od -c
```

### pendiente
- [x] Implementar `BigInt.asIntN(bits, n)`
- [x] Implementar `BigInt.asUintN(bits, n)`
- [x] Registrar como propiedades estáticas de BigInt (vía BIGINT_METHODS)
- [x] Tests de compatibilidad
- [x] Tests unitarios

## Edge cases encontrados durante implementación

### 1. divFloor argumento quotient vs remainder invertido (BUG FIX)
**Síntoma**: `BigInt.asIntN(8, 255n)` retornaba `0n` en vez de `-1n`.
**Causa**: `Managed.divFloor(q, r, a, b)` pone `q = floor(a/b)` y `r = a - q*b`.
Llamé `result.value.divFloor(&quot.value, ...)` pensando que `r` quedaba en `result`,
pero la firma es `divFloor(q, r, ...)` — entonces `result` recibía el cociente
(0 en este caso), no el residuo.
**Fix**: invertir los argumentos — `quot.value.divFloor(&result.value, &n.value, &modulus.value)`.
**Verificación**: `asIntN(8, 255n)` → `-1n` después del fix.

### 2. Bits inválidos no lanza RangeError, retorna `void`
**Spec (Node.js)**: `BigInt.asIntN(-1, 5n)` lanza `RangeError: Invalid value: not
(convertible to) a safe integer`. `BigInt.asIntN(8, 255)` lanza `TypeError`.
**Lou**: en vez de lanzar, retorna `undefined` (consistente con el patrón de
otros builtins como `Array.sort` sobre tipos incorrectos).
**Decisión**: documentado como diferencia conocida. Lanzar errores reales
requeriría implementar `throw` en builtin functions (ya parcialmente hecho
en `BigInt.toString`, pero solo para RangeError tipados). Promover a spec
separado si se quiere paridad total.

### 3. Coerción de bits (NaN, undefined, null → 0; "8" → 8; 8n → throws)
**Spec**: `bits` se convierte con `ToIntegerOrInfinity` antes de validar.
**Lou**: requiere estrictamente `integer`; cualquier otro tipo retorna `void`.
**Decisión**: misma razón que (2). No se intenta replicar coerción parcial.

### 4. `bits == 0` siempre retorna `0n`
**Spec**: `BigInt.asIntN(0, 5n)` → `0n`. Para `bits=0`, `2^(bits-1) = 2^-1` no
existe, pero la spec lo define igual como `0n` porque `2^0 = 1` y `n mod 1 = 0`.
**Lou**: rama especial en `BigIntAsIntN` antes de calcular `half` (evita el
shiftLeft de -1 que no tiene sentido para `usize`).
**Verificación**: `asIntN(0, 5n)` y `asUintN(0, 5n)` ambos → `0n`.

### 5. Tests con `BigIntValue.fromString` requieren append a `env.bigints`
**Síntoma**: `zig build test` reportaba memory leaks en los nuevos tests.
**Causa**: `env.deinit()` libera los `BigIntValue`s registrados en
`env.bigints`. Los tests creaban `BigIntValue`s con `fromString` pero no los
registraban, así que se filtraban al destruir el env.
**Fix**: añadir `env.bigints.append(allocator, n) catch {};` para cada
`BigIntValue` creado en tests. Sigue el patrón existente en `BigInt.toString`.
