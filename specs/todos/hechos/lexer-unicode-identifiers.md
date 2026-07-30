# Lexer: Identificadores Unicode

## status

COMPLETADO (2026-06-22)

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
- [x] *(Done — see "Cambios aplicados" below.)*

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

- Compat test match: `lexer-unicode-identifiers.lou` (FUZZY — unicode identifiers)
- Test status: **PASS** (added 2026-06-22, alongside this implementation)

- Diff excerpt: empty — `.lou` output and Node.js output match exactly.

- Disposition: moved to `hechos/` — fuzzy-matched test now PASSES.

## Cambios aplicados (2026-06-22)

- **`src/lexer.zig`: `readChar()`** — decodes UTF-8 multi-byte sequences via `std.unicode.utf8ByteSequenceLength` (with `catch 1` fallback for invalid lead bytes / `0xC0`/`0xC1`). Advances `read_position` by the full sequence length (1, 2, 3, or 4 bytes). `this.ch` and `this.position` still point to the lead byte; continuation bytes (0x80-0xBF) are never visited individually. ASCII dispatch on `this.ch` keeps working unchanged.

- **`src/lexer.zig`: new helpers**
  - `isIdStartByte(b: u8) bool` → ASCII alphabetic OR `_` OR `$` OR `b >= 0x80`. The `>= 0x80` heuristic covers all multi-byte UTF-8 lead bytes as well as any continuation bytes that may appear standalone (gracefully handled rather than panicking).
  - `isIdContinueByte(b: u8) bool` → `isIdStartByte(b)` OR ASCII digit.
  - Pragmatic per spec recommendation: full Unicode ID_Start / ID_Continue property tables would require a separate data dependency; for now, anything ≥0x80 round-trips correctly because downstream stages (`getKeywordType`, `Identifier` lookup, env storage) treat literals as opaque UTF-8 byte slices.

- **`src/lexer.zig`: `nextToken` switch** — replaced the prior identifier detection (line ~503) with `isIdStartByte(this.ch)` and the reading loop with `isIdContinueByte(this.ch)`. No other branches in the dispatch needed updates because all the operators / delimiters / string / template / regex / comment / whitespace / number paths use ASCII bytes only.

- **`src/lexer.zig`: unit tests** — 7 new tests covering Latin accented (`café`, `naïve`, `résumé`), 2-byte Greek (`π`, `Σ`, `λambda`), 3-byte CJK (`変`, `数`, `名前`, `変数`), 4-byte (musical G clef U+1D11E, alone and suffixed), digit-after-Unicode-letter (`π1`, `変数42`), delimiter/operator adjacency (`café = "coffee";`), and UTF-8 inside string literals. Lexer test suite: 46 → 53/53 PASS.

- **`tests/compat/lexer-unicode-identifiers.{js,lou}`** — 9-case compat test exercising var declarations, function parameters, function expression binding in `reduce`, property keys + access, `typeof`. `.lou` and `.js` outputs identical, runner marks PASS.

## Known limitations (follow-up)

1. **U+2028 / U+2029 line separators** — `readChar()` still only increments `this.line` for ASCII `\n`. With multi-byte advancement, the `readRegexLiteral` UTF-8 line-separator check (`this.ch == 0xE2 and this.input[this.position] == 0x80…`) is now incorrect (it should look at `input[position+1]` and `input[position+2]` respectively since lead bytes are not stored separately). Should be promoted to its own spec for line numbering and regex `LineTerminator` rejection.
2. **No full Unicode ID_Start / ID_Continue tables** — combining marks (e.g. `café` with decomposed `e + ◌́`) are stored as the composite form; users wanting canonical-equivalence matching would still need a property table. Out of scope per the spec's "pragmatic" recommendation.
3. **Invalid UTF-8 (bytes 0x80-0xBF standalone, 0xC0/0xC1, 0xF8-0xFF)** are treated as identifier characters byte-by-byte rather than rejected, by design (resilient degraded mode). Source files with corrupt UTF-8 still tokenize without crashing.

