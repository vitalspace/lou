# Integración ICU para localeCompare / normalize / toLocale*

## status

❌ PENDIENTE

## Problema

`localeCompare`, `normalize`, `toLocaleLowerCase`, `toLocaleUpperCase` no tienen soporte ICU real. Sus implementaciones son stub/proxys con soporte mínimo.

## Contexto

**Prioridad: baja** (bloqueante: ~25MB al binario)

- ICU agrega ~25MB al binario — hay que decidir si vale la pena
- Alternativa: implementar solo el subset necesario (collation básico, NFC/NFD para Latin-1)
- Alternativa: compilar ICU data con filtro para reducir tamaño
- Hay que diseñar la integración C API de ICU4C o usar ICU4X (Rust/WASM)

## Baseline (qué existe ya)
- `String` YA implementado (`src/builtins/string/`)
- `localeCompare`, `normalize`, `toLocaleLowerCase`, `toLocaleUpperCase` YA existen como stubs
- Sin ICU library: comportamiento mínimo/incompleto
- Cross-check con `string-unicode-case.md` — caso similar sin ICU

## Quick verify (estado actual)
```bash
echo 'console.log("ä".localeCompare("z"));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: comparación ASCII (ä como bytes, probablemente > z); esperado: negativo en locale alemán
```

## Patrones a seguir
- `src/builtins/string/localeCompare.zig` (existente)
- `src/builtins/string/normalize.zig` (existente)
- `src/builtins/string/toLocaleLowerCase.zig` (existente)
- ICU4C (C library) o ICU4X (Rust/WASM)
- `build.zig` para linkear C library

## Gotchas
- DECISIÓN: ¿vale la pena 25MB? Si no, implementar subset mínimo
- ICU4C requiere linkear — `build.zig` debe agregar `linkLibC` y `addLibraryPath`
- ICU4X es WASM — no ideal para Lou
- Para collation: comparar punto de código (suficiente para ASCII)
- Para `normalize` NFC/NFD: tabla de composición/decomposición
- Cross-check con `intl.md` — ambos dependen de ICU
- Si la decisión es NO usar ICU, documentar limitaciones
- Tests: solo verificar subset implementado
- Cross-check con `temporal.md` — ICU también afecta timezone data

## Código que falla

```js
console.log("ä".localeCompare("z", "de"));
console.log("é".normalize("NFD"));
console.log("I".toLocaleLowerCase("tr"));
```

## Implementacion sugerida

1. Decidir estrategia de integración ICU (nativa C API vs ICU4X vs subset custom)
2. Implementar collation para `localeCompare`
3. Implementar `normalize` con NFC/NFD
4. Implementar `toLocaleLowerCase`/`toLocaleUpperCase` con soporte de locale

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

- `specs/strings/localeCompare.md`
- `specs/strings/normalize.md`
- `specs/strings/toLocaleLowerCase.md`
- `specs/strings/toLocaleUpperCase.md`

### JS Examples

```js
console.log("ä".localeCompare("z", "de"));  // negativo (ä < z en alemán)
console.log("é".normalize("NFD"));          // "e\u0301"
console.log("I".toLocaleLowerCase("tr"));   // "ı" (sin punto)
```

### Vereficacion

```js
console.log("ä".localeCompare("z", "de"));
console.log("é".normalize("NFD"));
console.log("I".toLocaleLowerCase("tr"));
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente

- [ ] Decidir estrategia ICU (C API / ICU4X / subset custom)
- [ ] Implementar `localeCompare` con collation básico
- [ ] Implementar `normalize` NFC/NFD
- [ ] Implementar `toLocaleLowerCase`/`toLocaleUpperCase`
- [ ] Verificar tamaño binario final (~25MB overhead)

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

