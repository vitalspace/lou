# Lexer: $ en identificadores

## status

NOT IMPLEMENTED

## Problema

El lexer no reconoce `$` como carácter válido para iniciar un identificador. `std.ascii.isAlphabetic` no incluye `$`, y la condición en `lexer.zig:318` solo verifica `isAlphabetic` o `_`.

## Contexto

ECMAScript permite identificadores que empiezan con `$`, `_`, o cualquier letra Unicode (`ID_Start`). `$` es extremadamente común en JS: jQuery (`$`, `$$`), generadores de código, template engines, y convenciones de naming.

## Baseline (qué existe ya)
- Lexer ya maneja identificadores ASCII y `_` (src/lexer.zig:318-321)
- `getKeywordType()` mapea keywords (`src/lexer.zig` ~line 440-600)
- `$` actualmente NO se reconoce — falla como carácter inválido

## Quick verify (estado actual)
```bash
echo 'var $x = 1; console.log($x);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou
# Actual: error de parseo o tokenización incorrecta (EOF o identificador vacío)
```

## Patrones a seguir
- `src/lexer.zig:318` — condición actual de inicio de identificador (`isAlphabetic` o `_`)
- `src/lexer.zig:320` — loop de continuación (incluye dígitos)
- `src/lexer.zig:442-460` — `getKeywordType` como ejemplo de switch sobre literal

## Gotchas
- Agregar `$` solo al inicio Y al loop de continuación — sino `$1` no funcionará como identificador
- Asegurarse de que `$` no interfiera con template strings (`` ` ``) — están en lexer.zig:304
- Si se añade `$` al loop, también afecta a strings que contengan `$` — pero el lexer ya procesa strings antes de llegar al loop de identificadores
- El parser/evaluator no requieren cambios — el token `Identifier` ya soporta cualquier literal alfanumérico

## Código que falla

```js
var $el = document.getElementById("app");
var $$ = require("cheerio");
var $0 = getSelectedElement();
console.log($el, $$, $0);
```

**Salida actual:** EOF inesperado o error de parseo.
**Salida esperada:** funciona normalmente.

## Implementacion sugerida

En `src/lexer.zig:318`, agregar `$` a la condición de inicio de identificador:

```zig
// Antes:
} else if (std.ascii.isAlphabetic(this.ch) or this.ch == '_') {

// Después:
} else if (std.ascii.isAlphabetic(this.ch) or this.ch == '_' or this.ch == '$') {
```

También en el loop de continuación (línea 320):
```zig
// Antes:
while (std.ascii.isAlphabetic(this.ch) or std.ascii.isDigit(this.ch) or this.ch == '_') {

// Después:
while (std.ascii.isAlphabetic(this.ch) or std.ascii.isDigit(this.ch) or this.ch == '_' or this.ch == '$') {
```

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
- ECMAScript 12.7.1 Identifier Names

### JS Examples Complejos

```js
// jQuery patterns
var $ = jQuery;
var $$ = (sel) => document.querySelectorAll(sel);
var $el = $(".container");

// Generated code patterns
var _private = 1;
var $internal = 2;
var $$observable = Symbol("observable");
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-dollar-identifiers.js
node js/test-dollar-identifiers.js
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
