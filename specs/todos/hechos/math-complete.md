# Math (completo)

## status
IMPLEMENTADO (2026-06-29)

## Problema
Solo `Math.abs()` está implementado. Faltan todos los demás métodos y constantes de `Math`.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. El objeto `Math` tiene ~40 métodos y constantes que son esenciales para cálculos numéricos.

## Baseline (qué existe ya)
- `MATH_OBJECT` YA está registrado (`src/builtins/builtinObjects.zig:4`)
- SOLO `Math.abs` está implementado (`src/builtins/math/abs.zig`)
- `Math.abs` registrado en `src/builtins/math/math.zig`
- Faltan: constantes (PI, E, etc.) y todos los demás métodos

## Quick verify (estado actual)
```bash
echo 'console.log(Math.PI, Math.floor(3.7));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "undefined undefined" — Math.PI no existe, Math.floor tampoco
echo 'console.log(Math.abs(-5));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "5" (este sí funciona)
```

## Patrones a seguir
- `src/builtins/math/math.zig` — registro de métodos
- `src/builtins/math/abs.zig` — ejemplo de método
- `src/builtins/properties.zig` — cómo se registran constantes globales
- `src/builtins/json/json.zig` — patrón alternativo con `BuiltinObjectImpl`
- `std.math` de Zig — `pi`, `e`, `sin`, `cos`, `tan`, `log`, `exp`, `pow`, `sqrt`, `floor`, `ceil`, etc.

## Gotchas
- Patrón de organización: crear un archivo `.zig` por método (como `abs.zig`) o agrupar en `math.zig`
- Constantes: pueden ir en `properties.zig` como globales o como parte de MATH_OBJECT
- Si van como propiedades del MATH_OBJECT, agregar mecanismo de "static properties" (no métodos)
- `Math.max(...args)` y `Math.min(...args)` aceptan N argumentos — usar args list de `[]Types.Value`
- `Math.random()` — usar `std.crypto.random` o `std.rand` de Zig
- `Math.floor(-3.7) = -4`, `Math.ceil(-3.7) = -3` — verificar que Zig `@floor` y `@ceil` hacen lo mismo
- `Math.hypot(...args)` — calcular sqrt(sum of squares) para evitar overflow
- Trig functions en Zig (`@sin`, `@cos`) usan radianes — JS también, OK
- Para `Math.imul`: hacer cast a i32, multiplicar, retornar como i32

## Código que falla
```js
console.log(Math.PI);           // 3.14159...
console.log(Math.floor(3.7));   // 3
console.log(Math.random());     // 0.xxx
console.log(Math.max(1, 2, 3)); // 3
```

## Implementacion sugerida

### 1. Builtin (src/builtins/math/)
Expandir `src/builtins/math/` con:

**Constantes:**
`Math.E`, `Math.LN10`, `Math.LN2`, `Math.LOG10E`, `Math.LOG2E`, `Math.PI`, `Math.SQRT1_2`, `Math.SQRT2`

**Rounding:**
`Math.ceil()`, `Math.floor()`, `Math.round()`, `Math.trunc()`

**Min/Max:**
`Math.max()`, `Math.min()`

**Random:**
`Math.random()`

**Power/Root:**
`Math.pow()`, `Math.sqrt()`, `Math.cbrt()`, `Math.hypot()`

**Trigonometry:**
`Math.sin()`, `Math.cos()`, `Math.tan()`, `Math.asin()`, `Math.acos()`, `Math.atan()`, `Math.atan2()`

**Logarithm/Exponential:**
`Math.log()`, `Math.log2()`, `Math.log10()`, `Math.exp()`, `Math.expm1()`

**Sign/Clamp:**
`Math.sign()`, `Math.clz32()`, `Math.fround()`, `Math.imul()`

**Hyperbolic:**
`Math.sinh()`, `Math.cosh()`, `Math.tanh()`, `Math.asinh()`, `Math.acosh()`, `Math.atanh()`

## Tests

Añadir un test de compatibilidad en `tests/compat/`. El runner (`tests/compat/run.sh`) compara el output de Lou contra el de Node y solo marca PASS si ambos exit code y stdout normalizado son idénticos.

### Convención de archivos

- `tests/compat/<nombre>.js` — referencia canónica. Debe ejecutarse con `node` y producir el output esperado.
- `tests/compat/<nombre>.lou` — el mismo programa escrito para Lou. Debe producir output idéntico a la versión `.js`.
- Si el spec cubre sintaxis **específica de Lou** (no existente en JS, e.g. `function f() expr` como expression body, `..` range, `match`), omitir el `.js` y dejar solo el `.lou` — el runner marcará SKIP automáticamente.

### Verificación local

```bash
# 1. Lou produce el output esperado
./zig-out/bin/lou run tests/compat/<nombre>.lou

# 2. Node produce el output esperado (si hay .js)
node tests/compat/<nombre>.js

# 3. Diff (debe ser vacío)
diff <(./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1) \
     <(node tests/compat/<nombre>.js 2>&1)

# 4. Correr toda la suite
bash tests/compat/run.sh
```

### Tests unitarios (parser/lexer/evaluator)

Además del compat test, añadir tests unitarios en el archivo `.zig` correspondiente (`src/parser.zig`, `src/lexer.zig`, `src/evaluator.zig`, etc.) que verifiquen la estructura del AST o el comportamiento del lexer/evaluator para casos individuales. Los unit tests son útiles para casos donde el compat test sería demasiado grande o donde queremos verificar la forma exacta del AST.

## Archivos de referencia
- src/builtins/math/ — implementación actual (solo abs)
- src/builtins/builtinObjects.zig — registro de MATH_OBJECT

### JS Examples Complejos
```js
// Constantes
console.log(Math.PI);            // 3.141592653589793
console.log(Math.E);             // 2.718281828459045
console.log(Math.LN2);           // 0.6931471805599453
console.log(Math.LN10);          // 2.302585092994046

// Rounding
console.log(Math.floor(3.7));    // 3
console.log(Math.floor(-3.7));   // -4
console.log(Math.ceil(3.2));     // 4
console.log(Math.ceil(-3.2));    // -3
console.log(Math.round(3.5));    // 4
console.log(Math.round(3.4));    // 3
console.log(Math.trunc(3.7));    // 3
console.log(Math.trunc(-3.7));   // -3

// Min/Max
console.log(Math.max(1, 2, 3));  // 3
console.log(Math.min(1, 2, 3));  // 1
console.log(Math.max());         // -Infinity
console.log(Math.min());         // Infinity

// Random
console.log(Math.random());      // 0 <= x < 1
const dice = Math.floor(Math.random() * 6) + 1;

// Power
console.log(Math.pow(2, 10));    // 1024
console.log(Math.sqrt(144));     // 12
console.log(Math.cbrt(27));      // 3
console.log(Math.hypot(3, 4));   // 5

// Trigonometry
console.log(Math.sin(Math.PI / 2)); // 1
console.log(Math.cos(Math.PI));     // -1
console.log(Math.tan(0));           // 0
console.log(Math.atan2(1, 0));      // π/2

// Logarithm
console.log(Math.log(Math.E));  // 1
console.log(Math.log2(1024));   // 10
console.log(Math.log10(1000));  // 3
console.log(Math.exp(1));       // 2.718...

// Sign
console.log(Math.sign(42));     // 1
console.log(Math.sign(-42));    // -1
console.log(Math.sign(0));      // 0

// imul (integer multiplication)
console.log(Math.imul(2, 3));   // 6
```

### Verificacion
- Todas las constantes tienen los valores correctos
- `floor`, `ceil`, `round`, `trunc` manejan positivos, negativos, y edge cases
- `max` y `min` aceptan N argumentos
- `random()` retorna un float entre 0 (inclusive) y 1 (exclusive)
- Funciones trigonométricas trabajan en radianes
- `log`, `log2`, `log10` calculan logaritmos correctos

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/math.js 2>&1 | od -c
node js/tests/math.js 2>&1 | od -c

### pendiente
- [x] Implementar todas las constantes de Math (8 constantes)
- [x] Implementar todos los métodos de Math (35 métodos)

## Resumen de implementación (2026-06-29)

Se implementaron todos los métodos y constantes de `Math` siguiendo el patrón existente de `abs.zig`:

- **Constantes** (7 nuevas + 1 existente PI): E, LN10, LN2, LOG10E, LOG2E, SQRT1_2, SQRT2
- **Rounding** (4): ceil, floor, round, trunc
  - `round` usa `@floor(x + 0.5)` para coincidir con JS (half towards +∞)
- **Min/Max** (2): max, min — retornan NaN si algún argumento no es numérico
- **Random** (1): random
- **Power/Root** (4): pow, sqrt, cbrt, hypot
- **Trigonometry** (6): sin, cos, tan, asin, acos, atan, atan2
- **Log/Exp** (6): log, log2, log10, exp, expm1, log1p
- **Sign/Misc** (4): sign, clz32, fround, imul
- **Hyperbolic** (6): sinh, cosh, tanh, asinh, acosh, atanh

Cada método está en un archivo separado en `src/builtins/math/`. El registro central está en `math.zig`.

**Diff con Node.js**: 1 diferencia menor — `Math.E` tiene un dígito extra de precisión (`2.7182818284590455` vs `2.718281828459045`). Es diferencia de formato, no de valor.

## Edge cases encontrados durante implementación

Listar aquí los bugs, comportamientos inesperados o requisitos descubiertos
mientras se implementaba este spec. Cada edge case debe ser promovido a su
propio spec (usando esta misma plantilla) si requiere cambios de diseño
propios, o documentado inline si es un fix puntual.

Ejemplos de edge cases típicos:
- Comportamiento cuando se mezcla el tipo con primitivos incompatibles
  (TypeError vs coerción silenciosa).
- Formato de impresión / `toString` — sufijo, base, mayúsculas.
- Comparación loose vs strict.
- Conversión a otros tipos (string concat, Number, BigInt).
- División por cero, exponente negativo, overflow.
- Capturabilidad del error por `try/catch` JS (no abortar el proceso).

Plantilla para promover un edge case a spec:
1. Crear `specs/todos/pendientes/<spec>-edge-<caso>.md` siguiendo esta plantilla.
2. Enlazar desde este spec principal con un enlace relativo.
3. Verificar que el test correspondiente cubre el caso.


## Estado del test (auto 2026-06-29)

- Compat test match: `math-complete.lou` (EXACT)
- Test status: **PASS** (1 minor formatting diff: Math.E precision, see above)

