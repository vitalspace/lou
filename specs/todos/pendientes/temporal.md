# Temporal

## status
pendiente

## Problema
El objeto `Temporal` no está implementado. No hay alternativa moderna al problemático `Date`.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `Temporal` es la nueva API de fecha/hora de TC39 (Stage 3) que reemplaza a `Date` con una API más limpia.

## Baseline (qué existe ya)
- `Date` YA implementado (`src/builtins/date/`) — base para Temporal
- 12 tipos de Temporal — ninguno implementado
- Temporal es MUY extenso (Stage 3, no standard todavía)

## Quick verify (estado actual)
```bash
echo 'console.log(Temporal.Now.plainDateTimeISO());' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Temporal is not defined"
```

## Patrones a seguir
- `src/builtins/date/` — Date implementation (referencia más cercana)
- `src/builtins/builtinObjects.zig` — registrar TEMPORAL_OBJECT
- `src/builtins/number/number.zig` — patrón de constructor
- `std.time` de Zig — para nanosegundos/epoch

## Gotchas
- Feature ENORME: 12 tipos + muchos métodos cada uno
- IMPLEMENTACIÓN MÍNIMA viable: solo `Temporal.Now` y `Temporal.PlainDate`
- Timezone data: problema similar a Intl — sin ICU, datos limitados
- Cross-check con `intl.md` y `date-object-regression.md`
- Para fechas sin timezone, no se necesita ICU
- PlainDate: año/mes/día como integers (i32)
- Aritmética: implementar `add(duration)` y `subtract(duration)`
- `.until(other)`: calcular diferencia en días/meses/años
- `.toString()`: formato ISO 8601 ("YYYY-MM-DD")
- Solo implementar tipos básicos al inicio (PlainDate, PlainTime, PlainDateTime)
- ZonedDateTime requiere timezone database — complejo
- Tests: verificar API básica, no todos los edge cases de timezone

## Código que falla
```js
const now = Temporal.Now.plainDateTimeISO();
console.log(now.year, now.month, now.day);
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/temporal.zig`:
- `Temporal.Instant` — punto absoluto en el tiempo (nanosegundos)
- `Temporal.ZonedDateTime` — fecha/hora con timezone
- `Temporal.PlainDateTime` — fecha/hora sin timezone
- `Temporal.PlainDate` — solo fecha
- `Temporal.PlainTime` — solo hora
- `Temporal.PlainYearMonth` — año y mes
- `Temporal.PlainMonthDay` — mes y día
- `Temporal.Duration` — duración
- `Temporal.Calendar` — calendario
- `Temporal.TimeZone` — timezone
- `Temporal.Now` — fecha/hora actual

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
- src/builtins/date.zig — implementación de Date (referencia)

### JS Examples Complejos
```js
// Ahora
const now = Temporal.Now.plainDateTimeISO();
console.log(`${now.year}-${now.month}-${now.day}`);

// Crear fecha
const date = new Temporal.PlainDate(2024, 1, 15);
console.log(date.dayOfWeek); // 1 (lunes)

// Duración
const duration = new Temporal.Duration(1, 2, 3); // 1y 2m 3d
console.log(duration.toString()); // "P1Y2M3D"

// Aritmética de fechas
const tomorrow = date.add({ days: 1 });
const nextWeek = date.add({ weeks: 1 });
console.log(tomorrow.toString());

// Diferencia entre fechas
const d1 = new Temporal.PlainDate(2024, 1, 1);
const d2 = new Temporal.PlainDate(2024, 12, 31);
const diff = d1.until(d2);
console.log(diff.days); // 365

// ZonedDateTime
const zdt = Temporal.Now.zonedDateTimeISO();
console.log(zdt.timezone);
console.log(zdt.toInstant().epochMilliseconds);

// PlainTime
const time = new Temporal.PlainTime(14, 30, 0);
console.log(time.toString()); // "14:30:00"

// Comparación
const a = new Temporal.PlainDate(2024, 1, 1);
const b = new Temporal.PlainDate(2024, 6, 15);
console.log(Temporal.PlainDate.compare(a, b)); // -1
```

### Verificacion
- `Temporal.Now` retorna fecha/hora actual
- Constructores crean objetos correctos
- Aritmética de fechas funciona con `.add()` y `.subtract()`
- `.until()` calcula diferencias
- `.toString()` produce formato ISO
- Comparación con `Temporal.PlainDate.compare()`

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/temporal.js 2>&1 | od -c
node js/tests/temporal.js 2>&1 | od -c

### pendiente
- Implementar Temporal como builtin (API extensa)
- Considerar dependencia de datos de timezone

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

- Compat test match: `-` (NO-MATCH)
- Test status: `-`

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/temporal.lou + tests/compat/temporal.js to enable automatic PASS/FAIL tracking.

