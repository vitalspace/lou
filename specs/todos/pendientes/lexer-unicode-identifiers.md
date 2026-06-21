# Lexer: Identificadores Unicode

## status

NOT IMPLEMENTED

## Problema

El lexer solo acepta identificadores ASCII (`std.ascii.isAlphabetic`). Caracteres unicode como `café`, `変数`, `переменная` no son válidos como identificadores. ECMAScript permite cualquier carácter en las categorías Unicode `ID_Start` e `ID_Continue`.

## Contexto

ECMAScript 12.7.1 Identifier Names: los identificadores pueden contener cualquier carácter Unicode que coincida con `ID_Start` (letras, `_`, `$`) seguido de `ID_Continue` (letras, dígitos, `_`, `$`, combinadores, etc.).

## Baseline (qué existe ya)
- Lexer `ch` es `u8` (src/lexer.zig:125) — solo lee ASCII byte-por-byte
- `std.ascii.isAlphabetic` solo cubre ASCII A-Z/a-z
- `$` actualmente NO está implementado (ver `lexer-dollar-identifier.md`)
- `std.unicode.utf8Decode` disponible para leer codepoints de múltiples bytes

## Quick verify (estado actual)
```bash
echo 'var café = 1; console.log(café);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error de parseo o tokenización incorrecta
```

## Patrones a seguir
- `src/lexer.zig:125` — cambiar `ch: u8` a `ch: u21` (codepoint Unicode) o mantener u8 y agregar `codepoint: u21`
- `src/lexer.zig:336-345` — `readChar` debe actualizarse para leer multi-byte UTF-8
- `src/lexer.zig:318-321` — condición de identificador: usar `std.unicode` o categorías ID_Start/ID_Continue
- `std.unicode.utf8ByteSequenceLength` para saber cuántos bytes leer

## Gotchas
- Cambio grande: afecta TODO el lexer que asume `ch: u8`. Si no querés refactor masivo, alternativa pragmática: chequear rango Unicode en cada byte (e.g. `ch >= 0x80` permite todo el rango extendido)
- ECMAScript real usa las propiedades Unicode `ID_Start` e `ID_Continue`. Zig `std.unicode` solo tiene categorías generales — para spec completa necesitarías una tabla Unicode o librería externa
- Strings (`src/lexer.zig:383-395`) usan la misma `readChar` — cambiar a UTF-8 afecta el escaneo de strings (que ya lo hace byte-por-byte, OK)
- Source code mismo es UTF-8 — el `main.zig` debe leer el archivo con esa encoding (verificar `readFile` no hace nada raro)
- Cross-check con `lexer-dollar-identifier.md` — al agregar `$`, también soportar Unicode `$` (poco común pero válido)

## Código que falla

```js
var café = "coffee";        // Error: 'é' no es ASCII alphabetic
var 变数 = "variable";       // Error: caracteres CJK
var π = 3.14159;            // Error: griego
var 世界 = "world";          // Error
```

## Implementacion sugerida

Reemplazar `std.ascii.isAlphabetic` con una verificación Unicode:

```zig
// Option 1: Use std.unicode
fn isIdStart(ch: u21) bool {
    return ch == '_' or ch == '$' or std.unicode.isAlphabetic(ch);
    // Or use a lookup table for ID_Start category
}

fn isIdContinue(ch: u21) bool {
    return isIdStart(ch) or std.ascii.isDigit(@intCast(ch));
    // Or include ID_Continue category
}
```

El lexer necesita leer UTF-8 multi-byte para estos caracteres. Actualmente lee byte por byte (`u8`). Cambiar a `u21` para soporte unicode completo.

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

- `src/lexer.zig:318-321` — condición de identificadores
- `src/lexer.zig:124` — `ch: u8` (limita a ASCII)
- ECMAScript 12.7.1 Identifier Names

### JS Examples Complejos

```js
// Accented characters
var café = "coffee";
var naïve = true;
var résumé = "CV";

// CJK
var 名前 = "Alice";
var 変数 = 42;

// Greek
var π = 3.14159;
var Σ = function(arr) { return arr.reduce((a, b) => a + b, 0); };

// Cyrillic
var привет = "hello";
var мир = "world";
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-unicode-identifiers.js
node js/test-unicode-identifiers.js
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- [ ] *(Pendiente: detallar los pasos concretos de implementación derivados de las secciones anteriores.)*

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
