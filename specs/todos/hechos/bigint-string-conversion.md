# BigInt — Conversión a string (string concat, template literals)

## status
implementado

## Problema
`"" + 42n` retornaba `"42n"` (con sufijo) cuando debería ser `"42"`.
La función `valToStr` en el VM añadía el sufijo `n` también para la
conversión a string implícita, contradiciendo JS ToPrimitive.

## Contexto
ECMAScript define que para conversión implícita a string (concatenación
con `+`, template literals), BigInt usa `ToPrimitive` que llama a
`toString()` (sin sufijo). El sufijo `n` solo aparece cuando el usuario
llama explícitamente a `String(big)` con mayúscula (que no existe en JS
estándar) o cuando se imprime directamente (e.g. `console.log`).

## Código que falla
```js
console.log("val=" + 42n);  // Antes: val=42n,  Esperado: val=42
console.log("" + 0n);       // Antes: 0n,      Esperado: 0
const x = 100n;
console.log(`x=${x}`);       // Antes: x=100n,  Esperado: x=100
```

## Implementación

### 1. VM `valToStr` (src/vm.zig)
Cuando se concatena con string (operador `+` con string), NO añadir el
sufijo `n`. La función `valToStr` se usa para `+` string, `+` template,
y cualquier conversión implícita:

```zig
.big_int => |big| {
    // String conversion strips the trailing 'n' (matches JS ToPrimitive).
    // Display formatting (which keeps the 'n') happens in printValueTo.
    const str = big.value.toString(a, 10, .lower) catch return;
    defer a.free(str);
    buf.appendSlice(a, str) catch {};
    // NO: buf.append(a, 'n') catch {};
},
```

### 2. Distinción entre display y conversión
- **`console.log(big)` / `printValueTo`** → imprime con sufijo `n`
  (formato de display, ver `bigint-print-format.md`).
- **`"" + big` / template literal / `String(big)`** → sin sufijo
  (conversión JS estándar).

### 3. `String(big)` constructor
`String` no existe como builtin callable en Lou. Spec dedicado:
`string-constructor-bigint.md` (pendiente). Cuando se implemente, debe
usar `valToStr` (sin sufijo).

### 4. Refactor de display
`BigIntValue.toString` (en `src/types/runtime.zig`) añade el sufijo `n`.
Era código muerto (todos los call sites usaban `big.value.toString` +
manual `'n'` append). Refactor:
- `src/builtins/console/log.zig` → usa `big.toString(allocator)`
- `src/builtins/console/error.zig` → usa `big.toString(allocator)`
- `src/vm.zig` `valToStr` → sigue usando `big.value.toString` directo
  (sin sufijo — esa es la conversión a string JS estándar)

## Archivos de referencia
- src/vm.zig — `valToStr` (línea ~2085, **strips `n`**)
- src/builtins/console/log.zig — `printValueTo` (línea ~87, **keeps `n`** via `BigIntValue.toString`)
- src/builtins/console/error.zig — `printValueTo` (idem)
- src/types/runtime.zig — `BigIntValue.toString` (añade sufijo, usado por display)
- src/builtins/bigint/bigint.zig — `BigIntToString` (método prototype, sin sufijo)

### JS Examples Complejos
```js
// Concatenación con string (sin sufijo)
console.log("val=" + 42n);          // val=42
console.log("" + 0n);               // 0
console.log("" + (-42n));           // -42
console.log("" + 100n);             // 100
console.log("a" + 1n + "b");        // a1b
console.log(1n + "" + 2n);          // 12  (¡concat, no suma!)

// Template literals (sin sufijo)
const x = 100n;
const y = 2n ** 64n;
console.log(`x=${x}, y=${y}`);      // x=100, y=18446744073709551616

// console.log (con sufijo)
console.log(42n);                   // 42n
console.log(0n);                    // 0n
console.log(2n ** 64n);             // 18446744073709551616n

// Mezcla de tipos en template
const flag = true;
console.log(`flag=${flag} n=${42n}`);  // flag=true n=42
```

### Verificación
- `"" + 42n` retorna `"42"`, no `"42n"` ✅
- `"val=" + 0n` retorna `"val=0"` ✅
- `` `${42n}` `` retorna `"42"` ✅
- Concatenación mixta: `1n + ""` produce `"1"`, no error ✅
- `console.log(42n)` sigue imprimiendo `42n` (display) ✅
- Números negativos: `"" + (-42n)` retorna `"-42"` ✅
- BigInt grandes: `"" + (2n ** 64n)` retorna `"18446744073709551616"` ✅

### Comparar salida raw (sin interpretar ANSI)
```
./zig-out/bin/lou run js/tests/bigint-string-conv.js 2>&1 | tee /tmp/lou.txt > /dev/null
node js/tests/bigint-string-conv.js > /tmp/node.txt
diff /tmp/lou.txt /tmp/node.txt
```
Nota: `>` directo pierde output por ANSI buffering en lou; usar `tee` o `| od -c`.

### Tests
- `js/tests/bigint-string-conv.js` — verificación directa contra Node
- `js/tests/bigint-print.js` — display format (incluye casos de concat)
- `tests/compat/bigint-prototype.js` — `.toString()`, `.toLocaleString()`, template literals

### pendiente
- [x] `valToStr` strip'ea el sufijo `n`
- [x] `printValueTo` mantiene el sufijo `n` (display)
- [x] `BigInt.prototype.toString([radix])` — ver `bigint-prototype-template.md`
- [x] `BigInt.prototype.toLocaleString()` — ver `bigint-prototype-template.md`
- [x] Template literals con `${expr}` interpolan sin sufijo `n` — ver `bigint-prototype-template.md`
- [x] Refactor: display usa `BigIntValue.toString` (antes era código muerto)
- [ ] `String(big)` constructor — ver `string-constructor-bigint.md` (pendiente)
