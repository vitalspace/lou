# Lexer: Regex literals

## status

NOT IMPLEMENTED

## Problema

El lexer no soporta regex literals (`/pattern/flags`). El carácter `/` siempre produce `Divide` o `DivideAssign`. Esto impide parsear `var re = /abc/g;` y cualquier uso de regex como literal.

## Contexto

ECMAScript requiere desambiguar entre `/` (división) y `/regex/` dependiendo del token anterior. Si el token anterior puede terminar una expresión (identificador, literal, `)`, `]`, `++`, `--`), entonces `/` es división. Si no, inicia un regex.

## Baseline (qué existe ya)
- Lexer siempre emite `Divide` o `DivideAssign` para `/` (src/lexer.zig:183-190)
- NO hay tracking del token previo en `Lexer` (struct src/lexer.zig:121-127)
- `RegExp` builtin object YA existe (`src/builtins/regex/`) — solo falta el syntactic sugar del literal
- NO hay un `TokenType.Regex` en el enum

## Quick verify (estado actual)
```bash
echo 'var re = /hello/g; console.log(re);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (espera expresión después de =)
```

## Patrones a seguir
- `src/lexer.zig:121-127` — struct `Lexer`; agregar campo `prev_token_type: TokenType = .EOF` (o similar)
- `src/lexer.zig:183-190` — handler actual de `/` para división
- `src/lexer.zig:300-304` — lectura de strings/template como referencia para "leer hasta delimitador"
- `src/builtins/regex/` — cómo se construye un `RegExp` a partir de pattern + flags

## Gotchas
- Tracking de `prev_token`: setear en cada `nextToken()` return, ANTES de retornar
- Set "puede terminar expresión": `Identifier`, `Integer`, `Float`, `String`, `TemplateString`, `RParen`, `RBracket`, `Increment`, `Decrement`, `NullLiteral`, `VoidLiteral`, `True`/`False`, `This`
- Después de regex, setear `prev_token` a `.Regex` para que `/regex/ / 2` se parsee como `Regex / 2` correctamente
- Escape `\/` dentro del pattern NO termina el regex
- Flags válidos: `g`, `i`, `m`, `s`, `u`, `y`, `d`, `v` — duplicar flag es SyntaxError en strict mode (warning en sloppy)
- AST: nuevo nodo `RegexLiteral { pattern, flags }` o reusar literal string + builtin call — diseñar antes de implementar
- Si el regex no cierra (no encuentra `/` final), reportar error de lexer

## Código que falla

```js
var re = /hello/g;
var pattern = /\d{3}-\d{4}/;
if (/test/i.test("TEST")) { console.log("match"); }
str.replace(/foo/g, "bar");
```

**Salida actual:** Error de parseo — `/` se tokeniza como `Divide`.
**Salida esperada:** Regex literal parseado correctamente.

## Implementacion sugerida

1. Agregar `Regex` al `TokenType` enum
2. En `nextToken()`, cuando se encuentre `/`, verificar el token anterior:
   - Si el token anterior puede terminar una expresión → `Divide`
   - Si no → iniciar lectura de regex literal
3. Leer el patrón hasta el `/` de cierre (respetando escapes `\/`)
4. Leer flags (`g`, `i`, `m`, `s`, `u`, `y`, `d`, `v`) hasta que no sea una letra válida
5. Devolver token `Regex` con el patrón y flags

```zig
// En TokenType enum:
Regex, // /pattern/flags

// En nextToken, tracking previous token type:
// if previous_token can_end_expression → Divide
// else → readRegexLiteral()
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

- `src/lexer.zig:183-190` — manejo actual de `/`
- `src/builtins/regex/` — implementación de RegExp ya existente
- ECMAScript 12.9.5 Regular Expression Literals

### JS Examples Complejos

```js
// Basic regex
var re = /hello/i;
console.log(re.test("Hello World"));

// Regex with flags
var global = /foo/g;
var multiline = /^line/m;

// Regex in conditionals
if (/^\d{4}-\d{2}-\d{2}$/.test(date)) { console.log("valid date"); }

// Regex with special chars
var email = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;

// Escaped slash in pattern
var path = /\//;
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-regex-literal.js
node js/test-regex-literal.js
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
