# RegExp v Flag (Unicode Sets)

## status
pendiente

## Problema
El flag `v` de RegExp (Unicode Sets, ES2024) no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. El flag `v` extiende el modo unicode con operaciones de conjuntos (unión, intersección, diferencia) en patrones de caracteres.

## Baseline (qué existe ya)
- `RegExp` builtin YA existe (`src/builtins/regex/`)
- Regex parser YA existe (`src/builtins/regex/engine/parser.zig`)
- Cross-check con `lexer-regex-literals.md` (pendiente) — flag v depende de poder parsear literals
- ES2024 feature — relativamente nueva

## Quick verify (estado actual)
```bash
echo 'const re = /[a]/v; console.log(re.test("a"));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: probablemente error (lexer no soporta regex literals o flag v)
```

## Patrones a seguir
- `src/builtins/regex/` — engine existente
- `src/builtins/regex/engine/parser.zig` — parser de patterns (modificar para sets)
- `src/builtins/regex/engine/` — compiler/executor
- ECMAScript 22.2 — RegExp specification

## Gotchas
- DEPENDE de `lexer-regex-literals.md` — implementar primero
- `v` activa un modo nuevo con sintaxis adicional (no retrocompatible con `u`)
- `&&` en `[...]` significa intersección de sets
- `--` significa diferencia
- `\q{...}` permite strings literales multi-char dentro de `[...]`
- `[\p{ASCII}&&\p{Letter}]` = chars que son ASCII Y Letter
- Sin ICU/Unicode data, `\p{...}` está limitado
- Cross-check con `string-unicode-case.md` — Unicode properties relacionados
- Set operations requieren modificar el parser de character class
- Tests: verificar casos básicos solamente

## Código que falla
```js
const re = /[\p{ASCII}&&\p{Letter}]/v;
console.log(re.test("a")); // true
console.log(re.test("1")); // false
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar flag `v` a RegExp.

### 2. Regex Engine (src/builtins/regex/engine/)
- Soportar operaciones de conjuntos: `&&` (intersección), `--` (diferencia)
- Soportar `\p{...}` con operaciones de conjuntos dentro de `[]`
- Soportar strings literales dentro de `[...]` con `\q{...}`

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
- src/builtins/regex/ — engine de regex existente
- src/builtins/regex/engine/parser.zig — parser de patrones

### JS Examples Complejos
```js
// Intersección
const re1 = /[\p{ASCII}&&\p{Letter}]/v;
console.log(re1.test("a")); // true (ASCII + Letter)
console.log(re1.test("1")); // false (ASCII pero no Letter)
console.log(re1.test("α")); // false (Letter pero no ASCII)

// Diferencia
const re2 = /[\p{Letter}--\p{ASCII}]/v;
console.log(re2.test("a")); // false (ASCII)
console.log(re2.test("α")); // true (Letter pero no ASCII)

// Unión implícita
const re3 = /[\p{ASCII}\p{Greek}]/v;
console.log(re3.test("a")); // true
console.log(re3.test("α")); // true

// String literal en set
const re4 = /[a\q{hello|world}b]/v;
console.log(re4.test("hello")); // true
console.log(re4.test("world")); // true
console.log(re4.test("hey"));   // false

// Nested operations
const re5 = /[[\p{ASCII}&&\p{Letter}]\p{Number}]/v;
console.log(re5.test("a")); // true
console.log(re5.test("1")); // true

// Property escapes con set operations
const re6 = /[\p{Script_Extensions: Greek}&&\p{Letter}]/v;
```

### Verificacion
- Flag `v` activa Unicode Sets mode
- `&&` hace intersección de conjuntos de caracteres
- `--` hace diferencia de conjuntos
- `\q{...}` permite strings literales dentro de sets
- Operaciones se pueden anidar
- Compatible con `\p{...}` property escapes

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/regex-v.js 2>&1 | od -c
node js/tests/regex-v.js 2>&1 | od -c

### pendiente
- Implementar flag v en el regex engine
- Implementar operaciones de conjuntos (&&, --)
- Implementar \q{...} para strings literales

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

- Compat test match: `regex-properties.lou` (FUZZY — regex)
- Test status: `FAIL`

- Diff excerpt:

```
1,19c1,19
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
```

- Disposition: stays in pendientes/ — fuzzy-matched test currently FAILS, see diff excerpt below.

