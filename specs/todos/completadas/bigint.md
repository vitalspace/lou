# BigInt

## status
implementado

## Problema
El tipo `BigInt` no está implementado. No se pueden representar enteros arbitrariamente grandes.

## Contexto
Lou es un intérprete JavaScript escrito en Zig. `BigInt` permite trabajar con enteros más allá del límite de `Number.MAX_SAFE_INTEGER`.

## Código que falla
```js
const big = 9007199254740991n;
console.log(big + 1n); // 9007199254740992n
console.log(typeof big); // "bigint"
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar token: `BigInt` — número seguido de `n` (ej: `42n`)

### 2. AST (src/ast.zig)
Agregar `BigIntLiteral` a `NodeType`

### 3. Runtime (src/types/runtime.zig)
Agregar `bigint` a `Value` union — usar `std.math.big.int.Managed` de Zig

### 4. VM (src/vm.zig)
- Opcode `bigint` para constantes BigInt
- Operaciones aritméticas con BigInt
- No se puede mezclar con Number (lanzar TypeError)
- Operador `**` debe funcionar con BigInt (right-associative, RangeError en exponente negativo)
- Operadores `==` y `!=` deben coercionar Number/String/Boolean a BigInt (loose equality)
- Operadores `===` y `!==` deben ser estrictos (no coercion)
- Print/format: usar `value.toString()` con sufijo `n`, no debug format del struct

## Archivos de referencia
- src/lexer.zig — tokenization
- src/types/runtime.zig — Value union
- src/vm.zig — operaciones aritméticas
- src/builtins/bigint/bigint.zig — constructor BigInt()
- src/builtins/number/number.zig — constructor Number() con soporte BigInt

### JS Examples Complejos
```js
// Literales
const a = 42n;
const b = 123456789012345678901234567890n;

// Constructor
const c = BigInt(42);
const d = BigInt("12345678901234567890");

// Aritmética
console.log(1n + 2n);         // 3n
console.log(10n - 3n);        // 7n
console.log(4n * 5n);         // 20n
console.log(10n / 3n);        // 3n (trunca)
console.log(10n % 3n);        // 1n
console.log(2n ** 100n);      // gran número
console.log(2n ** 3n ** 2n);  // 2n ** (3n ** 2n) = 2n ** 9n (right-associative)

// Comparación
console.log(1n === 1);        // false (tipos diferentes)
console.log(1n !== 1);        // true
console.log(1n == 1);         // true (coerción Number)
console.log(1n == "1");       // true (coerción String)
console.log(1n == true);      // true (true → 1)
console.log(1n == 1.5);       // false (Number no entero no coerce a BigInt)
console.log(2n > 1n);         // true
console.log(1n < 2n);         // true

// typeof
console.log(typeof 42n);     // "bigint"

// No mezclar con Number → TypeError (capturable con try/catch)
try { console.log(1n + 1); } catch (e) { console.log("caught:", e); }
// caught: TypeError: Cannot mix BigInt and other types
try { console.log(1n - 1.5); } catch (e) { console.log("caught"); }
try { console.log(1n * "x"); } catch (e) { console.log("caught"); }
try { console.log(1n / true); } catch (e) { console.log("caught"); }
try { console.log(1n % null); } catch (e) { console.log("caught"); }

// Exponente negativo en BigInt → RangeError
try { console.log(2n ** -1n); } catch (e) { console.log("caught:", e); }
// caught: RangeError: BigInt negative exponent

// Conversión
console.log(Number(42n));    // 42
console.log(Number(0n));     // 0
console.log(BigInt(42));     // 42n
console.log(BigInt("42"));   // 42n
console.log(BigInt(3.14));   // undefined (NaN → 0n en JS, aquí void)

// Uso práctico
const MAX_ID = 2n ** 64n;
console.log(MAX_ID);         // 18446744073709551616n
```

### Edge cases encontrados durante implementación

Los siguientes edge cases se descubrieron durante la implementación. Cada
uno fue promovido a su propio spec en `specs/todos/pendientes/`:

1. **Print format**: Ver `bigint-print-format.md` —
   `console.log(42n)` debe imprimir `42n` con la representación numérica,
   no el debug-format del struct `BigIntValue`.

2. **TypeError propagación**: Ver `bigint-mix-typeerror.md` —
   `1n + 1` debe lanzar `TypeError` capturable por `try/catch` JS, no un
   error Zig que aborte el proceso. Aplica a todas las operaciones
   aritméticas con mix de tipos.

3. **Loose vs strict equality**: Ver `bigint-loose-equality.md` —
   `==` y `===` deben diferenciarse. `1n == 1` debe ser `true`
   (coerción), `1n === 1` debe ser `false` (estricto).

4. **Conversión a string**: Ver `bigint-string-conversion.md` —
   `"" + 42n` debe ser `"42"` (sin sufijo `n`), no `"42n"`.
   El sufijo solo aparece en display (`console.log`).

5. **División por cero**: Ver `bigint-zero-division.md` —
   `1n / 0n` debe lanzar `RangeError: Division by zero`,
   `1n % 0n` igual. (Aún no implementado.)

6. **Exponente negativo**: Documentado en `bigint-mix-typeerror.md` —
   `2n ** -1n` lanza `RangeError: BigInt negative exponent`.
   (Implementado.)

### Verificacion
- `42n` crea un BigInt ✓
- `BigInt(42)` crea un BigInt ✓
- `BigInt("123")` crea un BigInt ✓
- Operaciones aritméticas (+, -, *, /, %, **) funcionan entre BigInts ✓
- No se puede mezclar BigInt con Number (TypeError) — capturable con try/catch ✓
- `typeof` retorna "bigint" ✓
- `===`/`!==` son estrictos (sin coerción) ✓
- `==`/`!=` coercionan Number/String/Boolean a BigInt ✓
- `2n ** -1n` lanza RangeError ✓
- `2 ** 3 ** 2` es 512 (right-associative) ✓
- Conversión Number(42n) y BigInt(42) funciona ✓
- Print muestra "Nn" con dígitos correctos, no debug-format ✓
- `"" + 42n` es `"42"` (sin sufijo `n`) ✓

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/test-bigint.js 2>&1 | od -c
node js/test-bigint.js 2>&1 | od -c

### pendiente
- [x] Implementar token, AST node, runtime type y operaciones para BigInt
- [x] Print BigInt correctamente (no debug-format)
- [x] TypeError capturable para mezcla BigInt/Number
- [x] Loose equality (==) con coerción BigInt↔Number
- [x] Operador `**` con right-associativity
- [x] Number() constructor global con soporte BigInt
- [x] Negación unaria sobre BigInt (`-1n`)
- [x] BigInt.prototype.toString() method
- [x] BigInt.prototype.valueOf() method
- [x] Bitwise operations: `&`, `|`, `^`, `<<`, `>>` para BigInt
- [x] BigInt as object property keys
- [x] División por cero BigInt (`1n / 0n` → RangeError)
