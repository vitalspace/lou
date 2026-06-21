# Intl (Internationalization)

## status
pendiente

## Problema
El objeto `Intl` no está implementado. No hay soporte para formateo de fechas, números, ni collation localizados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `Intl` proporciona APIs para formateo sensible al idioma y locale.

## Baseline (qué existe ya)
- `Date` YA implementado parcialmente (`src/builtins/date/`)
- `Number` parcialmente (`src/builtins/number/number.zig`)
- `Intl` NO existe
- Sin ICU library: datos de locale limitados

## Quick verify (estado actual)
```bash
echo 'console.log(new Intl.NumberFormat("en").format(1234));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Intl is not defined"
```

## Patrones a seguir
- `src/builtins/date/` — Date implementation (referencia para DateTimeFormat)
- `src/builtins/number/number.zig` — Number reference
- `src/builtins/builtinObjects.zig` — registrar INTL_OBJECT
- `src/builtins/number/number.zig` — patrón de constructor

## Gotchas
- Feature MONUMENTAL: requiere ICU library para datos reales
- IMPLEMENTACIÓN MÍNIMA viable: NumberFormat y DateTimeFormat para "en-US" solamente
- Locale fallback: si locale desconocido, usar "en-US"
- Sin ICU: implementar formateo básico manualmente (separadores de miles, decimales)
- Date format: usar `std.fmt` de Zig con formatos simples ("YYYY-MM-DD")
- Para ICU propiamente: linkear contra libicu (complejo de buildear)
- Alternativa: usar `std.fmt` con tabla hardcoded de formatos por locale
- Cross-check con `date-object-regression.md` y `string-icu.md`
- 9 sub-objetos Intl — implementar gradualmente
- Tests: solo verificar formatos básicos, no exhaustivo

## Código que falla
```js
console.log(new Intl.NumberFormat("de-DE").format(1234567.89));
// "1.234.567,89"

console.log(new Intl.DateTimeFormat("en-US").format(new Date()));
// "1/15/2024"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/intl.zig`:
- `Intl.NumberFormat(locale, options)` — formateo de números
- `Intl.DateTimeFormat(locale, options)` — formateo de fechas
- `Intl.Collator(locale, options)` — comparación de strings
- `Intl.PluralRules(locale, options)` — reglas plurales
- `Intl.RelativeTimeFormat(locale, options)` — tiempo relativo
- `Intl.ListFormat(locale, options)` — formateo de listas
- `Intl.DisplayNames(locale, options)` — nombres de display
- `Intl.Locale(tag)` — representación de locale
- `Intl.Segmenter(locale, options)` — segmentación de texto

### 2. Dependencia
Usar libicu o implementación Zig para datos de locale.

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
- src/builtins/string/ — formateo de strings

### JS Examples Complejos
```js
// NumberFormat
const nf = new Intl.NumberFormat("es-MX", {
    style: "currency",
    currency: "MXN"
});
console.log(nf.format(1234567.89)); // "$1,234,567.89"

// DateTimeFormat
const dtf = new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "long"
});
console.log(dtf.format(new Date())); // "2024年1月15日月曜日"

// Collator
const collator = new Intl.Collator("de", { sensitivity: "base" });
console.log(["a", "ä", "o", "ö"].sort(collator.compare));

// PluralRules
const pr = new Intl.PluralRules("en-US");
console.log(pr.select(0));  // "other"
console.log(pr.select(1));  // "one"
console.log(pr.select(2));  // "other"

// RelativeTimeFormat
const rtf = new Intl.RelativeTimeFormat("es", { numeric: "auto" });
console.log(rtf.format(-1, "day")); // "ayer"
console.log(rtf.format(1, "day"));  // "mañana"

// ListFormat
const lf = new Intl.ListFormat("en", { style: "long", type: "conjunction" });
console.log(lf.format(["A", "B", "C"])); // "A, B, and C"

// DisplayNames
const dn = new Intl.DisplayNames("es", { type: "region" });
console.log(of.of("US")); // "Estados Unidos"

// Segmenter
const segmenter = new Intl.Segmenter("en", { granularity: "word" });
const segments = segmenter.segment("Hello world");
for (const s of segments) {
    console.log(s.segment);
}
```

### Verificacion
- `Intl.NumberFormat` formatea números según locale
- `Intl.DateTimeFormat` formatea fechas según locale
- `Intl.Collator` compara strings según reglas de locale
- Métodos funcionan con diferentes locales
- Opciones de formateo se respetan

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/intl.js 2>&1 | od -c
node js/tests/intl.js 2>&1 | od -c

### pendiente
- Implementar Intl como builtin con al menos NumberFormat y DateTimeFormat
- Dependencia de datos de locale (ICU o similar)

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
