# Lexer: Notación exponencial

## status

NOT IMPLEMENTED

## Problema

El lexer no soporta notación exponencial. `1e10` se tokeniza como `1` + identificador `e10`. `3.14e-2` se tokeniza como `3.14` + identificador `e` + `-` + `2`.

## Contexto

ECMAScript permite notación exponencial: `1e10`, `1E10`, `3.14e-2`, `2.5e+3`, `1e-5`.

## Baseline (qué existe ya)
- Lexer parsea enteros y decimales (src/lexer.zig:305-317)
- Float se reconoce por presencia de `.` antes de dígitos
- Notación exponencial NO se reconoce — `1e10` se tokeniza como Integer(1) + Identifier("e10")

## Quick verify (estado actual)
```bash
echo 'console.log(1e10);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error (e10 es identificador, no número)
```

## Patrones a seguir
- `src/lexer.zig:305-317` — bloque actual de parseo numérico, agregar lógica después del while de dígitos/fracción
- `src/lexer.zig:30` — uso de `std.ascii.isDigit` para validar dígitos del exponente
- Si vas a usar `@pow()` o `std.math.pow`, importar `std` ya está en lexer.zig:1

## Gotchas
- El lexer actualmente distingue Integer de Float solo por presencia de `.`. Si agregás exponencial, devolve siempre `Float` (nunca `Integer`) porque `1e10` es float en JS
- Validar que después de `e/E` venga opcionalmente `+/-` y luego al menos un dígito — si no, es SyntaxError
- El `peekChar()` retorna `0` al final del input — usarlo como check de fin puede enmascarar errores si no validás dígitos del exponente primero
- El literal retornado se pasa al parser/evaluador — verificar que ambos esperan `.Float` con la cadena completa (e.g. "1e10") o convertir a f64 ya en el lexer (más simple: convertir en lexer)
- Cross-check con `lexer-hex-octal-binary.md` — `0x1e10` no debe interpretarse como exponencial, sino como hex

## Código que falla

```js
var big = 1e10;          // Debería ser 10000000000
var small = 3.14e-2;     // Debería ser 0.0314
var sci = 2.5E+3;        // Debería ser 2500
var tiny = 1e-5;         // Debería ser 0.00001
```

## Implementacion sugerida

En `src/lexer.zig`, después de leer dígitos (enteros o decimales), verificar si sigue `e` o `E`:

```zig
// After reading decimal digits and optional fractional part:
if (this.ch == 'e' or this.ch == 'E') {
    this.readChar(); // consume 'e'
    if (this.ch == '+' or this.ch == '-') {
        this.readChar(); // consume sign
    }
    if (!std.ascii.isDigit(this.ch)) {
        // error: exponent has no digits
    }
    while (std.ascii.isDigit(this.ch)) {
        this.readChar();
    }
    return .{ .type = .Float, .literal = this.input[start..this.position], .line = tok_line };
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
var avogadro = 6.022e23;
var planck = 6.626e-34;
var speed = 3e8;
var precise = 1.23456789e+10;

// In expressions
var result = 1e10 + 1e-10;
var ratio = 3.14e2 / 2e1;
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-exponential.js
node js/test-exponential.js
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
