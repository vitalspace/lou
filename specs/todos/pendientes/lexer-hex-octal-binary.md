# Lexer: Hex, Octal, Binario

## status

NOT IMPLEMENTED

## Problema

El lexer solo soporta números decimales. `0xFF` se tokeniza como `0` + identificador `xFF`. Lo mismo para `0o77` (octal) y `0b1010` (binario).

## Contexto

ECMAScript soporta literales numéricos en múltiples bases:
- Hexadecimal: `0xFF`, `0xFF`
- Octal: `0o77`, `0O77`
- Binario: `0b1010`, `0B1010`

## Baseline (qué existe ya)
- Lexer parsea enteros decimales (src/lexer.zig:305-317)
- No hay detección de prefijo `0x`/`0o`/`0b` — se trata `0` como decimal 0
- `std.ascii.isHex` y comparaciones `>= '0'` están disponibles en std

## Quick verify (estado actual)
```bash
echo 'console.log(0xFF);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: 0 + xFF (parse error o identificador inesperado)
```

## Patrones a seguir
- `src/lexer.zig:305-317` — bloque actual de parseo numérico; agregar rama específica cuando `this.ch == '0'`
- `src/lexer.zig:30` — uso de `std.ascii.isDigit` para delimitar el while
- Para conversión: `std.fmt.parseInt(i64, literal, 16)` (hex), `8` (oct), `2` (bin) — disponible en std

## Gotchas
- Cross-check con `lexer-exponential-notation.md` y `lexer-numeric-separators.md` — `0xFF_FF` y `0x1e10` (hex) deben funcionar
- `0` solo (sin prefijo) debe seguir siendo decimal 0, no disparar rama de hex/oct/bin
- En octal, solo dígitos `0-7` son válidos — validar y reportar error si hay `8` o `9`
- Si el literal después de `0x` no tiene dígitos hex válidos, es SyntaxError (no consumir el `x`)
- Devolver como `Integer` token — pero ojo: `0xFFFFFFFF` excede i64 en sistemas 32-bit; si querés soportar números grandes, el evaluador debe detectar overflow
- BigInt literal (`0xFFn`) es otro spec — no mezclar acá

## Código que falla

```js
var hex = 0xFF;       // Debería ser 255, actualmente: 0 + xFF
var oct = 0o77;       // Debería ser 63
var bin = 0b1010;     // Debería ser 10
var hex2 = 0x1A2B;    // Debería ser 6699
```

## Implementacion sugerida

En `src/lexer.zig:305-317`, después de leer dígitos, verificar si empieza con `0`:

```zig
else => if (std.ascii.isDigit(this.ch)) {
    const start = this.position;
    
    // Check for hex, octal, binary
    if (this.ch == '0') {
        this.readChar();
        if (this.ch == 'x' or this.ch == 'X') {
            // Hex literal
            this.readChar();
            while (std.ascii.isHex(this.ch)) this.readChar();
            return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
        } else if (this.ch == 'o' or this.ch == 'O') {
            // Octal literal
            this.readChar();
            while (this.ch >= '0' and this.ch <= '7') this.readChar();
            return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
        } else if (this.ch == 'b' or this.ch == 'B') {
            // Binary literal
            this.readChar();
            while (this.ch == '0' or this.ch == '1') this.readChar();
            return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
        }
    }
    
    // Decimal (existing code)
    while (std.ascii.isDigit(this.ch)) this.readChar();
    // ...
}
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

- `src/lexer.zig:305-317` — parsing de números
- ECMAScript 12.9.3 Numeric Literals

### JS Examples Complejos

```js
// Hex
var maxColor = 0xFFFFFF;
var alpha = 0xFF;

// Octal
var perms = 0o755;
var oct = 0O77;

// Binary
var flags = 0b1010_1100;
var mask = 0B1111_0000;

// In expressions
var sum = 0xFF + 0b1010; // 255 + 10 = 265
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-hex-octal-binary.js
node js/test-hex-octal-binary.js
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
