# BigInt — Print/format con sufijo `n`

## status
implementado

## Problema
`console.log(42n)` y otros mecanismos de impresión muestran el debug-format
del struct `BigIntValue` (allocator pointer, limbs) en vez de la
representación numérica con sufijo `n`. La salida es ilegible.

## Contexto
Lou es un intérprete JavaScript escrito en Zig. `BigInt` se representa
internamente como `std.math.big.int.Managed`. La función de impresión
(genéricamente `printValueTo` en `src/builtins/console/log.zig`) debe
usar `big.value.toString(allocator, 10, .lower)` y añadir el sufijo `n`,
nunca `{}` que invoca el debug-format del struct.

## Código que falla
```js
const big = 42n;
console.log(big);
// Esperado: 42n
// Antes del fix: .{ .allocator = .{ .ptr = anyopaque@..., .vtable = ... }, .limbs = { 42, 0, 0, 0 }, .metadata = 1 }n
```

## Implementacion sugerida

### 1. Print en consola (src/builtins/console/log.zig)
En `printValueTo`, manejar `.big_int` específicamente:
```zig
.big_int => |big| {
    const digits = big.value.toString(big.allocator, 10, .lower) catch "";
    defer big.allocator.free(digits);
    out.print("{s}{s}n{s}", .{ Y, digits, R }) catch {};
},
```

### 2. Concatenación con string (src/vm.zig `valToStr`)
Para `+` y template strings, `valToStr` debe strip'ear el sufijo `n`
porque `"" + 42n === "42"`, no `"42n"`. El sufijo `n` solo aparece
cuando se imprime el valor explícitamente (e.g. `console.log`).

```zig
.big_int => |big| {
    const str = big.value.toString(a, 10, .lower) catch return;
    defer a.free(str);
    buf.appendSlice(a, str) catch {};  // NO añadir 'n'
},
```

### 3. `BigIntValue.toString` (src/types/runtime.zig)
La función `toString` de `BigIntValue` ya añade el sufijo `n` — usarla
para display pero NO para conversión a string JS.

## Archivos de referencia
- src/builtins/console/log.zig — `printValueTo`
- src/vm.zig — `valToStr` (concatenación de strings)
- src/types/runtime.zig — `BigIntValue.toString`

### JS Examples Complejos
```js
// Print directo
console.log(42n);                     // 42n
console.log(0n);                      // 0n
console.log(-42n);                    // -42n
console.log(123456789012345678901234567890n);  // 123456789012345678901234567890n
console.log(2n ** 64n);               // 18446744073709551616n

// Concatenación con string (sin sufijo n)
console.log("value=" + 42n);          // value=42
console.log("" + 0n);                 // 0
console.log("" + (-42n));             // -42

// Template literals
const x = 100n;
console.log(`x = ${x}`);              // x = 100  (NO "x = 100n")

// BigInt.prototype.toString() debería añadir 'n' cuando se llama
// explícitamente (aún no implementado)
```

### Vereficacion
- `console.log(42n)` imprime `42n`, no el debug-format del struct
- `"" + 42n` es `"42"`, no `"42n"`
- Template literals strip'pean el `n`
- Números negativos muestran el signo correctamente
- Números muy grandes (> 64 bits) se imprimen completos

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/bigint-print.js 2>&1 | od -c
node js/tests/bigint-print.js 2>&1 | od -c

### pendiente
- [x] `printValueTo` usa `toString` con sufijo `n`
- [x] `valToStr` strip'ea sufijo `n` para concatenación
- [x] Negativos grandes se imprimen con signo (parser fix: `-42n` ahora
  compila a `0n - 42n` en vez de `0.0 - 42n`, evitando el TypeError)
- [x] `BigInt.prototype.toString()` — spec `bigint-prototype-template.md`
- [x] `BigInt.prototype.toLocaleString()` — spec `bigint-prototype-template.md`
- [x] Template literals con `${expr}` — spec `bigint-prototype-template.md`
