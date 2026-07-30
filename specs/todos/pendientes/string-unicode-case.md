# Unicode case mapping en toLowerCase/toUpperCase

## status

❌ PENDIENTE

## Problema

`toLowerCase` y `toUpperCase` solo manejan ASCII (A-Z ↔ a-z). Caracteres como `"Ü"`, `"Ñ"`, `"Ç"` no se convierten. Node.js usa el Unicode case mapping completo (UCD).

## Contexto

**Prioridad: media**

- Se necesita una tabla de mapeo case-fold para el rango Unicode relevante
- Alternativa: integrar ICU (pero ~25MB)
- Alternativa: generar tabla compacta de `UnicodeData.txt` + `SpecialCasing.txt`

## Baseline (qué existe ya)
- `String` YA implementado (`src/builtins/string/`)
- `toLowerCase` y `toUpperCase` YA existen (`src/builtins/string/toLowerCase.zig`, `toUpperCase.zig`)
- Solo manejan ASCII (A-Z ↔ a-z)
- Tabla Unicode: NO existe, no hay ICU

## Quick verify (estado actual)
```bash
echo 'console.log("Ü".toLowerCase());' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Ü" (sin cambios); esperado: "ü"
```

## Patrones a seguir
- `src/builtins/string/toLowerCase.zig` — implementación ASCII actual
- `src/builtins/string/toUpperCase.zig` — implementación ASCII actual
- `src/builtins/string/` — otros métodos de string como template
- ECMAScript 22.1.3.26 — toLowerCase con Unicode

## Gotchas
- Estrategia: tabla hardcoded en Zig con los pares case más comunes (no full ICU)
- Mantener ASCII fast-path (ch < 128) — table lookup solo si Unicode
- Casos especiales: `ß` → `SS` (German sharp s — DOSP en upper case)
- Locale-independent: en JS `toUpperCase`/`toLowerCase` no son locale-aware
- Strings resultantes deben allocarse con `env.allocator` y tracked en `env.owned_strings`
- Tabla compacta: array de `struct { upper: u21, lower: u21 }` ordenado por upper
- Binary search en la tabla para lookup O(log n)
- Si la tabla tiene muchos entries, considerar sorted array + binary search
- Cross-check con `string-icu.md` (separado)

## Código que falla

```js
console.log("ÜBER".toLowerCase());
console.log("CAFÉ".toLowerCase());
console.log("ÑOÑO".toLowerCase());
console.log("über".toUpperCase());
console.log("café".toUpperCase());
console.log("straße".toUpperCase());
```

## Implementacion sugerida

1. Generar tabla Unicode case mapping desde `UnicodeData.txt` + `SpecialCasing.txt`
2. Integrar tabla en `src/builtins/string/toLowerCase.zig` y `toUpperCase.zig`
3. Alternativa: integrar ICU si el tamaño es aceptable

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

- `specs/strings/toLowerCase.md`
- `specs/strings/toUpperCase.md`
- `src/builtins/string/` — builtins de string existentes

### JS Examples

```js
// toLowerCase con Unicode
console.log("ÜBER".toLowerCase());     // → "über"
console.log("CAFÉ".toLowerCase());     // → "café"
console.log("ÑOÑO".toLowerCase());     // → "ñoño"

// toUpperCase con Unicode
console.log("über".toUpperCase());     // → "ÜBER"
console.log("café".toUpperCase());     // → "CAFÉ"
console.log("straße".toUpperCase());    // → "STRASSE"

// ASCII debe seguir funcionando
console.log("HELLO".toLowerCase());     // → "hello"
console.log("hello".toUpperCase());     // → "HELLO"
```

### Vereficacion

```js
console.log("ÜBER".toLowerCase());
console.log("CAFÉ".toLowerCase());
console.log("ÑOÑO".toLowerCase());
console.log("über".toUpperCase());
console.log("café".toUpperCase());
console.log("straße".toUpperCase());
console.log("HELLO".toLowerCase());
console.log("hello".toUpperCase());
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente

- [ ] Decidir estrategia: tabla custom vs ICU
- [ ] Implementar Unicode case mapping en `toLowerCase`
- [ ] Implementar Unicode case mapping en `toUpperCase`
- [ ] Verificar casos especiales (ej: `straße` → `STRASSE`)
- [ ] Verificación con `od -c` vs Node.js

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

- Compat test match: `string-length.lou` (FUZZY — string)
- Test status: `FAIL`

- Diff excerpt:

```
1,9c1,2
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
< false
```

- Disposition: stays in pendientes/ — fuzzy-matched test currently FAILS, see diff excerpt below.

