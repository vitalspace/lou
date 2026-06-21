# Lexer: Escape sequences en strings

## status

NOT IMPLEMENTED

## Problema

`readString` en `lexer.zig:383-395` no procesa escape sequences. Simplemente escanea byte por byte hasta encontrar el delimitador. Esto causa que `\"` dentro de un string termine la lectura prematuramente, y que secuencias como `\n`, `\t`, `\u0041` se almacenen como texto crudo.

## Contexto

ECMAScript requiere que los strings procesen secuencias de escape: `\\`, `\'`, `\"`, `\n`, `\r`, `\t`, `\b`, `\f`, `\v`, `\0` (sin dígito siguiente), `\xHH`, `\uHHHH`, `\u{HHHHHH}`.

## Baseline (qué existe ya)
- Lexer tiene `readString` (src/lexer.zig ~line 383-395) que lee byte-por-byte hasta el delimitador
- No procesa escapes — `\"` corta prematuramente, `\n` se almacena como 2 caracteres
- Tanto `"..."` (línea 302) como `'...'` (línea 303) usan la misma función `readString`

## Quick verify (estado actual)
```bash
echo 'var s = "a\\nb"; console.log(s);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: s contiene literal "a\nb" (4 chars), no newline real
```

## Patrones a seguir
- `src/lexer.zig:383-395` — `readString` actual (referencia exacta a modificar)
- `src/lexer.zig:1` — `const std = @import("std")` — da acceso a `std.ascii`
- `std.unicode.utf8Encode` para escribir el escape procesado al output buffer

## Gotchas
- Decisión de diseño: ¿procesar escapes en el lexer (más estándar, literal final = bytes correctos) o en el parser/evaluador (más simple)? Lexer es lo correcto
- Si usás un buffer de output, recordá allocar con `this.allocator` y guardarlo en `owned_strings` del environment (ver `env.owned_strings.append`)
- Para `\u{...}` (codepoint arbitrario), usar `std.unicode.utf8EncodeToSlice` o equivalente para escribir UTF-8 multibyte
- Template strings (`src/lexer.zig:304`) tienen su propia lectura — no comparte `readString`
- Validar que `\u` sin `{` tenga EXACTAMENTE 4 hex digits, sino error
- `\` seguido de fin de archivo es SyntaxError
- Después de procesar el escape, NO salir del loop — continuar leyendo hasta el delimitador final

## Código que falla

```js
var s1 = "hello\"world";  // Termina en \" — debería ser: hello"world
var s2 = "line1\nline2";  // Almacena \n literal — debería ser salto real
var s3 = "tab\there";     // Almacena \t literal
var s4 = "\x41\x42\x43"; // Debería ser "ABC"
var s5 = "\u0041";        // Debería ser "A"
var s6 = "back\\\\slash"; // Debería ser "back\\slash"
```

## Implementacion sugerida

Modificar `readString` para procesar escapes:

```zig
fn readString(this: *Lexer, delimiter: u8) Token {
    const start = this.position + 1;
    this.readChar(); // consume opening quote
    while (this.ch != delimiter and this.ch != 0) {
        if (this.ch == '\\') {
            this.readChar(); // consume backslash
            // Process escape sequence
            switch (this.ch) {
                'n', 't', 'r', 'b', 'f', 'v', '\\', '\'', '"' => {
                    this.readChar();
                },
                '0' => { // \0 only if not followed by digit
                    this.readChar();
                    if (std.ascii.isDigit(this.ch)) {
                        // octal not supported in strict mode
                    }
                },
                'x' => { // \xHH
                    this.readChar(); this.readChar(); this.readChar();
                },
                'u' => { // \uHHHH or \u{HHHHHH}
                    this.readChar();
                    if (this.ch == '{') {
                        while (this.ch != '}' and this.ch != 0) this.readChar();
                        this.readChar(); // consume }
                    } else {
                        this.readChar(); this.readChar(); this.readChar(); this.readChar();
                    }
                },
                else => { this.readChar(); },
            }
        } else {
            this.readChar();
        }
    }
    // ... rest of function
}
```

Alternativa: procesar escapes en el evaluador/parser en vez del lexer (simpler, pero menos estándar).

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

- `src/lexer.zig:383-395` — `readString`
- ECMAScript 12.8.4 String Literals

### JS Examples Complejos

```js
// Escaped quotes
var msg = "She said \"hello\"";
var path = "C:\\Users\\dev";
var html = '<div class=\"test\">';

// Special characters
var multiline = "line1\nline2\nline3";
var tabbed = "col1\tcol2\tcol3";

// Unicode escapes
var star = "\u2605";        // ★
var emoji = "\u{1F600}";   // 😀
var hex = "\x48\x65\x6C\x6C\x6F"; // "Hello"
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-string-escapes.js
node js/test-string-escapes.js
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
