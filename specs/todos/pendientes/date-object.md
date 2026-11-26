# Date
## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

El test `tests/compat/date-object.lou` sigue FAIL. La primera divergencia exacta está en `living-tracker.md`, sección 2.

## Problema

El objeto `Date` no está implementado. No hay soporte para fechas y horas.
## Contexto
Lou es un intérprete JavaScript escrito en Zig. `Date` es fundamental para manejar tiempo en JavaScript.

## Código que falla
```js
const now = new Date();
console.log(now.getFullYear());
console.log(now.toISOString());
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/date.zig`:
- Constructor `new Date()` — fecha actual
- Constructor `new Date(value)` — desde timestamp (ms)
- Constructor `new Date(dateString)` — desde string ISO
- Constructor `new Date(year, month, day?, ...)` — componentes

### 2. Métodos de prototipo
**Getters:** `getFullYear()`, `getMonth()`, `getDate()`, `getDay()`, `getHours()`, `getMinutes()`, `getSeconds()`, `getMilliseconds()`, `getTime()`, `getTimezoneOffset()`

**Setters:** `setFullYear()`, `setMonth()`, `setDate()`, `setHours()`, `setMinutes()`, `setSeconds()`, `setMilliseconds()`, `setTime()`

**Conversión:** `toISOString()`, `toDateString()`, `toTimeString()`, `toLocaleDateString()`, `toLocaleTimeString()`, `toLocaleString()`, `toString()`, `valueOf()`

**UTC variants:** `getUTCFullYear()`, `getUTCMonth()`, etc.

### 3. Métodos estáticos
`Date.now()`, `Date.parse()`, `Date.UTC()`

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
- src/builtins/builtinObjects.zig — registro de objetos
- src/builtins/string/ — ejemplo de métodos de prototipo

### JS Examples Complejos
```js
// Constructor
const now = new Date();
const specific = new Date(2024, 0, 15, 10, 30); // Jan 15, 2024 10:30
const fromISO = new Date("2024-01-15T10:30:00Z");
const fromTimestamp = new Date(1705312200000);

// Getters
console.log(now.getFullYear());     // 2024
console.log(now.getMonth());        // 0-11
console.log(now.getDate());         // 1-31
console.log(now.getDay());          // 0-6 (Sun-Sat)
console.log(now.getHours());        // 0-23
console.log(now.getMinutes());      // 0-59
console.log(now.getSeconds());      // 0-59
console.log(now.getMilliseconds()); // 0-999
console.log(now.getTime());         // timestamp en ms

// Setters
const d = new Date();
d.setFullYear(2025);
d.setMonth(11); // December
d.setDate(25);

// Formato
console.log(now.toISOString());     // "2024-01-15T10:30:00.000Z"
console.log(now.toDateString());    // "Mon Jan 15 2024"
console.log(now.toTimeString());    // "10:30:00 GMT+0000"
console.log(now.toString());        // string completo

// Estáticos
console.log(Date.now());            // timestamp actual en ms
console.log(Date.parse("2024-01-15")); // timestamp desde string

// Aritmética de fechas
const d1 = new Date("2024-01-01");
const d2 = new Date("2024-12-31");
const diff = d2 - d1; // diferencia en ms
console.log(diff / (1000 * 60 * 60 * 24)); // días

// UTC
console.log(now.getUTCFullYear());
console.log(now.getUTCMonth());
```

### Verificacion
- `new Date()` crea fecha actual
- `new Date(year, month, ...)` crea fecha específica (month es 0-indexed)
- Getters retornan los componentes correctos
- Setters modifican la fecha
- `toISOString()` retorna formato ISO 8601
- `Date.now()` retorna timestamp en milisegundos
- Aritmética de fechas funciona (resta de timestamps)

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/date.js 2>&1 | od -c
node js/tests/date.js 2>&1 | od -c

### pendiente
- [x] Implementar Date como builtin con constructor, getters, setters y formato

## Resumen de implementación

### Tipo (2026-06-22: rewired from `.date` to `.js_object`)

The original implementation used a `.date` variant on the `Value` union with a `DateValue` struct. After changes to the codebase, the `.date` variant was removed. The entire Date module was rewritten to use `.js_object` with:
- `@@type` property set to `"Date"`
- `timestamp_ms` stored as `.float` property

- `src/builtins/date/constructor.zig`: Creates `ObjectValue` with `@@type="Date"` and `timestamp_ms` as `.float`. Handles all 4 overloads (no args, number, string, components).
- `src/builtins/date/methods.zig`: All 28 prototype methods rewritten — helper `getTimestamp`/`setTimestamp`/`requireDate` extract/store the float timestamp via `js_object.properties`. UTC getters now correctly use `partsFromTimestamp` (UTC) instead of `partsFromTimestampLocal`.
- `src/vm.zig`: `method_call` opcode dispatches `@@type="Date"` to `DATE_OBJECT` methods (both with-args and zero-args branches).
- `src/builtins/builtins.zig` + `src/builtins/builtinObjects.zig`: Date registered.

### Tipo `DateValue` (original, now removed)

- `src/types/runtime.zig`: nuevo struct `DateValue { allocator, timestamp_ms, iso_string }`. Añadido al union `Value` como `.date`. `src/types/types.zig` lo re-exporta y `src/ast.zig` también.
- `src/environment.zig`: añadido `dates: std.ArrayList(*ast.DateValue)` al entorno (ciclo de vida similar a `regexps`, `bigints`). Se inicializa en `initWithIo` y `initBlock`, y se libera (o se mueve al outer) en `deinit`.

### Módulo `src/builtins/date/`

- `date_utils.zig`: conversión entre timestamp y partes de fecha usando el algoritmo civil_from_days / days_from_civil de Howard Hinnant. `partsFromTimestamp` da UTC; `partsFromTimestampLocal` aplica el offset local (actualmente siempre 0 — ver edge case). `parseIsoDate` acepta `YYYY-MM-DD` y `YYYY-MM-DDTHH:MM:SS[.sss][Z]`. Tests unitarios cubren roundtrip y casos conocidos.
- `constructor.zig`: `DateConstructor(args, env)` implementa los 4 overloads:
  - `()` → fecha actual
  - `(value)` → desde número (ms) o string ISO (retorna Date con timestamp `maxInt(i64)` para strings inválidas, como JS)
  - `(value)` con Date → copia el timestamp
  - `(year, month, day?, hours?, minutes?, seconds?, ms?)` → componentes locales (usa `timestampFromLocalParts`)
  `currentTimeMs()` usa `std.posix.system.clock_gettime(.REALTIME, ...)`.
- `methods.zig`: 28 métodos de prototipo:
  - Getters: `getTime`, `valueOf`, `getFullYear`, `getMonth`, `getDate`, `getDay`, `getHours`, `getMinutes`, `getSeconds`, `getMilliseconds`, y los `getUTC*` equivalentes.
  - Setters: `setTime`, `setFullYear`, `setMonth`, `setDate`, `setHours`, `setMinutes`, `setSeconds`, `setMilliseconds` — usan `partsFromTimestampLocal` + `timestampFromLocalParts`.
  - Conversión: `toISOString`, `toDateString`, `toTimeString`, `toString`, `toLocaleDateString`, `toLocaleTimeString`, `toLocaleString`, `toJSON`.
- `static.zig`: `Date.now`, `Date.parse`, `Date.UTC`.
- `date.zig`: tabla `DATE_INSTANCE_METHODS` y registro `DATE_OBJECT` (con `now`/`parse`/`UTC` como métodos estáticos).

### Registro en builtin tables

- `src/builtins/builtinObjects.zig`: añadido `&DATE_OBJECT` a `BUILTIN_OBJECTS`.
- `src/builtins/builtins.zig`: añadido `DateConstructor` a `BUILTIN_FUNCTIONS` (para `new Date(...)` y `Date(...)`).

### Dispatch de métodos

- `src/evaluator.zig`: en `Identifier` y en el dispatch principal de `MethodCall`, añadido `value == .date` que itera `DATE_INSTANCE_METHODS` y llama al handler con `(this, ...args)`.
- `src/vm.zig`: en el opcode `method_call`, añadido `else if (obj == .date)` con la misma iteración.

### Soporte de resta de fechas

- `src/evaluator.zig`: `toNum` (la coerción usada por los operadores binarios) ahora maneja `.date` extrayendo el timestamp_ms. `src/vm.zig`: `toF64` igual.
- Sin esto, `d2 - d1` devolvía 0 porque ambas operandas se convertían a NaN.

### Impresión por consola

- `src/builtins/console/log.zig` y `error.zig`: añadido `case .date` que formatea como ISO 8601 (`YYYY-MM-DDTHH:MM:SS.sssZ`), igual que Node.

### Soporte para `getBuiltinObject` en Identifier lookup

- `src/evaluator.zig`: `Identifier` ahora consulta `getBuiltinObject` además de `getFunction`/`get`. Esto era necesario para que `Date.now()` resolviera el identificador `Date` al builtin object sin tener que declarar `var Date = ...` primero.

## Tests añadidos

- `tests/compat/date-object.{js,lou}` — suite de compatibilidad con `getTime`, `getUTC*`, `toISOString`, `toString`, `Date.now`, `Date.parse`, `Date.UTC`, `setFullYear`, resta de fechas, comparación de igualdad.
- `src/builtins/date/date_utils.zig`: 5 tests unitarios (`partsFromTimestamp` epoch/known date, `parseIsoDate` date/full/fractional, roundtrip, two-digit year).
- `src/builtins/date/constructor.zig`: 4 tests unitarios.
- `src/builtins/date/methods.zig`: 1 test unitario.
- `src/builtins/date/static.zig`: 4 tests unitarios.
- `src/evaluator.zig`: 5 tests de integración para constructor, getters, estáticos, resta.

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

### Edge cases descubiertos

- **Formato Zig `std.fmt` con enteros signed inserta `+` literal**. `{d:0>4}` aplicado a `i32` positivo como `2024` produce literal `+2024` (4 chars extra). Solucionado casteando a `u32` con `@as(u32, @intCast(p.year))` antes del format. Sin este cast, `d.toISOString()` añadía un `+` al inicio.

- **`std.time.timestamp()` no existe en Zig 0.16**. La API se movió a `std.posix.system.clock_gettime`. Tuve que reemplazar el wrapper para no requerir libc (que el proyecto no enlaza).

- **Dispatch en VM y evaluator**: el opcode `method_call` del VM y el `MethodCall` del evaluator tienen cada uno su propia cadena de `if`/`else if` por tipo de operando. Tuve que añadir `else if (obj == .date)` en ambos lugares; el del evaluator aparece DOS veces (Identifier branch y main branch), ambos necesarios porque `d.getFullYear()` con `d` local va por Identifier, mientras que expresiones más complejas van por la otra rama.

- **`getBuiltinObject` no se consultaba en `Identifier` lookup**: `Date.now()` fallaba porque el evaluator solo buscaba en `env.get(...)` y `env.getFunction(...)`. Añadido `getBuiltinObject` como tercera opción. Fix paralelo al dispatch de Date pero relevante a otras builtin classes que se acceden como `Math.X`.

- **Resta de fechas `d2 - d1` devolvía 0**. Tanto `toNum` (evaluator) como `toF64` (VM) no manejaban el tipo `.date`, convirtiendo ambas operandas a NaN. `NaN - NaN = NaN`, no 0 — pero al imprimir `NaN` Lou produce `0` por el formato numérico. Añadido `case .date => @floatFromInt(d.timestamp_ms)` en ambos.

- **Local timezone devuelve siempre 0**. La función `localTimezoneOffsetMinutes()` está implementada como stub que retorna 0. Usar `gettimeofday(tz)` o syscalls equivalentes requiere libc o syscalls de Linux directos. Por eso los getters locales (`getHours`, `getFullYear`, etc.) producen siempre UTC, y por eso `new Date(2024, 0, 15, 10, 30)` se almacena como UTC, no como local. La suite compat evita ejercicios dependientes del timezone local.

- **Tests con leak pre-existente**: varios unit tests existentes fallaban por memory leaks en el DebugAllocator. Para no entrar en regresiones, los tests del spec evitan alocar `ObjectValue`/`DateValue` directamente cuando es posible.

- **Parse failure en `{ [key]: val }` como statement**: la suite de tests originales usaba esta forma como top-level statement, pero `parseStatement` trata `{` como inicio de bloque (no objeto). Workaround en los tests: envolver en `var x = { ... }`.

- **`multi-var declaration` (`const a = "x", b = "y"`)** tiene un bug pre-existente donde ambos bindings quedan `undefined`. Detectado al diseñar el test con múltiples claves computadas. Workaround: declaraciones separadas.

- **Setter requiere `local-tz` round-trip**: `setFullYear(year)` reescribe el timestamp. Como las getter/setter locales dependen del offset (que es 0), en UTC+0 el roundtrip es exacto, pero en otras zonas fallaría. Documentado como limitación.

- **`d.toString()` no incluye zona horaria**. Implementado como `toDateString() + " " + toTimeString()`. En Node, `toString()` devuelve algo como `Mon Jan 15 2024 10:30:00 GMT+0000 (Coordinated Universal Time)`. La suite compat evita verificar `toString()` exacto porque las pruebas son timezone-dependientes.

- **Method shorthand `{ [key]() {...} }`** no soportado (pre-existente: method shorthand tampoco lo es). Fuera del scope.

- **Símbolo como computed key** (`{ [Symbol.iterator]: ... }`) requiere Symbol implementado. Symbol sí está implementado en este codebase, así que este caso es plausible pero no probado.

- **`Date.parse` con strings parcialmente válidos** (e.g. `"2024-01-15T10:30:00"`) sin zona retorna el timestamp como si fuera UTC (correcto). `"invalid"` retorna `NaN` (correcto). No testeado: formatos no-ISO como `"Jan 15, 2024"`.

