# Number

## status

implementado
pendiente

## Problema
El objeto `Number` no está implementado como constructor. Faltan métodos estáticos y de prototipo.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los números se manejan como primitivos (`float`/`integer` en Value) pero no hay wrapper `Number`.

## Baseline (qué existe ya)
- `NumberConstructor` YA existe (`src/builtins/number/number.zig`) — convierte a número
- Faltan: Number como BuiltinObject (registrado en builtinObjects.zig)
- Faltan propiedades estáticas (`MAX_VALUE`, `NaN`, etc.) — algunas están en `src/builtins/properties.zig` como globales
- Faltan métodos estáticos (`Number.isNaN`, `Number.isFinite`, etc.)
- Faltan métodos de prototipo (`toFixed`, `toString`, etc.) — actualmente `(42).toFixed()` falla

## Quick verify (estado actual)
```bash
echo 'console.log(Number.isNaN(NaN));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Number.isNaN is not a function" o undefined
echo 'console.log((42).toFixed(2));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error (42 no es un objeto)
```

## Patrones a seguir
- `src/builtins/number/number.zig` — constructor ya existe
- `src/builtins/math/math.zig` — patrón de BuiltinObject con methods
- `src/builtins/math/abs.zig` — ejemplo de método individual
- `src/builtins/builtinObjects.zig` — registro central de objetos
- `src/builtins/properties.zig` — propiedades globales ya registradas
- `src/builtins/string/` — métodos de prototipo (template más completo)

## Gotchas
- `Number()` como función YA existe; el problema es `Number.method` y `(42).method`
- Prototipo: agregar métodos al `Number.prototype` y hacer que el constructor bindee prototipos en `new Number(...)`
- Number primitives (i64, f64) NO son `js_object` — para llamar `.toFixed()` hay que auto-boxing
- Auto-boxing: cuando se llama un método sobre primitivo Number, crear wrapper temporal
- Constantes: `MAX_VALUE`, `MIN_VALUE`, `EPSILON` — usar los de Zig `std.math`
- `Number.isNaN("hello")` debe ser `false` (sin coerción); global `isNaN("hello")` debe ser `true` (con coerción)
- `toString(radix)`: soportar bases 2-36, default 10
- Si añadís campos a Environment, actualizar initWithIo, initBlock, deinit
- `valueOf()` debe retornar el primitivo Number

## Código que falla
```js
console.log(Number.isNaN(NaN));     // true
console.log(Number.isInteger(42));  // true
console.log((42).toFixed(2));       // "42.00"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/number.zig`:
- Constructor `Number(value)` — convertir a número
- Propiedades estáticas: `Number.MAX_VALUE`, `Number.MIN_VALUE`, `Number.NaN`, `Number.POSITIVE_INFINITY`, `Number.NEGATIVE_INFINITY`, `Number.EPSILON`, `Number.MAX_SAFE_INTEGER`, `Number.MIN_SAFE_INTEGER`
- Métodos estáticos: `Number.isNaN()`, `Number.isFinite()`, `Number.isInteger()`, `Number.isSafeInteger()`, `Number.parseFloat()`, `Number.parseInt()`
- Métodos de prototipo: `toFixed()`, `toExponential()`, `toPrecision()`, `toString()`, `valueOf()`, `toLocaleString()`

### 2. Registro
Registrar en `builtinObjects.zig` como `NUMBER_OBJECT`.

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
- src/builtins/builtinObjects.zig — objetos builtin existentes
- src/builtins/string/ — ejemplo de implementación de métodos de prototipo
- src/types/runtime.zig — Value union

### JS Examples Complejos
```js
// Constructor
console.log(Number("42"));       // 42
console.log(Number(true));       // 1
console.log(Number(false));      // 0
console.log(Number(null));       // 0
console.log(Number(undefined));  // NaN
console.log(Number(""));         // 0
console.log(Number("hello"));    // NaN

// Propiedades estáticas
console.log(Number.MAX_VALUE);           // 1.7976931348623157e+308
console.log(Number.MIN_VALUE);           // 5e-324
console.log(Number.NaN);                 // NaN
console.log(Number.EPSILON);             // 2.220446049250313e-16
console.log(Number.MAX_SAFE_INTEGER);    // 9007199254740991
console.log(Number.MIN_SAFE_INTEGER);    // -9007199254740991

// Métodos estáticos
console.log(Number.isNaN(NaN));           // true
console.log(Number.isNaN(42));            // false
console.log(Number.isNaN("hello"));       // false (diferente de isNaN global)
console.log(Number.isFinite(42));         // true
console.log(Number.isFinite(Infinity));   // false
console.log(Number.isInteger(42));        // true
console.log(Number.isInteger(42.5));      // false
console.log(Number.isSafeInteger(42));    // true
console.log(Number.isSafeInteger(2**53)); // false

// Métodos de prototipo
console.log((42).toFixed(2));            // "42.00"
console.log((42.123).toFixed(1));        // "42.1"
console.log((42).toString());            // "42"
console.log((255).toString(16));         // "ff"
console.log((42).toString(2));           // "101010"
console.log((42.5).toExponential());     // "4.25e+1"
console.log((42.5).toPrecision(4));      // "42.50"
console.log((42).valueOf());             // 42
```

### Verificacion
- `Number("42")` convierte string a número
- Propiedades estáticas tienen los valores correctos
- `Number.isNaN` NO hace coerción (diferente de `isNaN`)
- `Number.isFinite` NO hace coerción
- `toFixed`, `toString`, `toExponential`, `toPrecision` funcionan
- `toString(radix)` soporta bases 2-36

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/number.js 2>&1 | od -c
node js/tests/number.js 2>&1 | od -c

### pendiente
- Implementar Number como builtin object
- Implementar métodos estáticos y de prototipo

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


## Estado del test (auto 2026-06-22)

- Compat test match: `date-object.lou` (FUZZY — object)
- Test status: `FAIL`

- Diff excerpt:

```
1,19c1,21
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
```

- Disposition: stays in pendientes/ — fuzzy-matched test currently FAILS, see diff excerpt below.

