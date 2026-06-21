# isFinite y isNaN

## status
pendiente

## Problema
Las funciones globales `isFinite()` y `isNaN()` no están implementadas.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Estas funciones son esenciales para validación numérica.

## Baseline (qué existe ya)
- `src/builtins/builtins.zig` — registro de funciones globales (cómo se añaden nuevas)
- `src/builtins/math/` — directorio de math builtins (referencia de patrón)
- `src/builtins/properties.zig` — propiedades globales como `undefined`, `NaN`, `Infinity`
- `NaN`, `Infinity` ya están en el environment (probablemente como `properties.zig`)
- `Number` object existe (`src/builtins/number/`)
- `parseInt`/`parseFloat` están en spec separado — ver `parseint-parsefloat.md`

## Quick verify (estado actual)
```bash
echo 'console.log(isFinite(42));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: ReferenceError "isFinite is not defined"
```

## Patrones a seguir
- `src/builtins/builtins.zig` — `initBuiltins` para registrar nuevas funciones globales
- `src/builtins/properties.zig` — para `NaN`, `Infinity`, `undefined`
- `src/builtins/math/` — ejemplo de builtin con coerción numérica
- `src/evaluator.zig` — buscar `evaluateArgs` para entender cómo se llama un builtin

## Gotchas
- `isFinite(value)`:
  1. Convertir value a número (coerción: `Number(value)`)
  2. Si resultado es NaN, ±Infinity → false; sino true
- `isNaN(value)`:
  1. Convertir value a número
  2. Si resultado es NaN → true; sino false
- DIFERENCIA con `Number.isFinite` y `Number.isNaN`: los globales SÍ hacen coerción, los del Number object NO
- Cross-check con `parseint-parsefloat.md` y `number-object.md`
- JS coerción de tipos a number: `null → 0`, `undefined → NaN`, `true → 1`, `false → 0`, `"" → 0`, `"abc" → NaN`, `[1] → 1`, `[] → 0`
- Necesitas implementar helper `toNumber(value)` para reusar en varias funciones

## Código que falla
```js
console.log(isFinite(42));        // true
console.log(isFinite(Infinity));  // false
console.log(isNaN(NaN));          // true
console.log(isNaN("hello"));      // true (convierte a número)
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Registrar `isFinite` y `isNaN` como funciones globales.

### 2. Implementación
- `isFinite(value)` — verificar si el valor es un número finito
- `isNaN(value)` — verificar si el valor es NaN
- Ambas convierten el argumento a número primero (coerción)

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
- src/builtins/builtins.zig — registro de funciones
- src/types/runtime.zig — Value union, coerción a número

### JS Examples Complejos
```js
// isFinite
console.log(isFinite(0));          // true
console.log(isFinite(42));         // true
console.log(isFinite(-1));         // true
console.log(isFinite(1.5));        // true
console.log(isFinite(Infinity));   // false
console.log(isFinite(-Infinity));  // false
console.log(isFinite(NaN));        // false
console.log(isFinite("42"));       // true (convierte "42" a 42)
console.log(isFinite("hello"));    // false (convierte a NaN)
console.log(isFinite(null));       // true (null → 0)
console.log(isFinite(undefined));  // false (undefined → NaN)
console.log(isFinite(true));       // true (true → 1)
console.log(isFinite(false));      // true (false → 0)
console.log(isFinite(""));         // true ("" → 0)

// isNaN
console.log(isNaN(NaN));           // true
console.log(isNaN(undefined));     // true (undefined → NaN)
console.log(isNaN("hello"));       // true ("hello" → NaN)
console.log(isNaN(42));            // false
console.log(isNaN("42"));          // false
console.log(isNaN(null));          // false (null → 0)
console.log(isNaN(true));          // false (true → 1)
console.log(isNaN(""));            // false ("" → 0)
console.log(isNaN({}));            // true ({} → NaN)

// Number.isNaN vs isNaN (diferencia)
console.log(isNaN("hello"));       // true (coerción)
console.log(Number.isNaN("hello")); // false (sin coerción)

// Number.isFinite vs isFinite (diferencia)
console.log(isFinite("42"));       // true (coerción)
console.log(Number.isFinite("42")); // false (sin coerción)
```

### Verificacion
- `isFinite(42)` → true
- `isFinite(Infinity)` → false
- `isNaN(NaN)` → true
- `isNaN("hello")` → true (coerción)
- Ambas realizan coerción de tipos
- `null` se convierte a 0 (finito)
- `undefined` se convierte a NaN

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/isfinite-isnan.js 2>&1 | od -c
node js/tests/isfinite-isnan.js 2>&1 | od -c

### pendiente
- Registrar isFinite y isNaN como funciones globales
- Implementar con coerción de tipos

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
