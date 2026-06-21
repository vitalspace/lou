# Lexer: Float con punto inicial (.5)

## status

NOT IMPLEMENTED

## Problema

`.5` se tokeniza como `Dot` + `Integer(5)` en vez de `Float(0.5)`. ECMAScript permite `.5` como literal de punto flotante válido.

## Contexto

ECMAScript 12.9.3 Numeric Literals: `.5` es un `DecimalLiteral` válido equivalente a `0.5`.

## Baseline (qué existe ya)
- Lexer tiene handler para `.` (src/lexer.zig ~line 289-300) — emite `Dot`, `DotDot`, o `DotDotDot`
- Float parsing existente solo se activa si hay dígitos ANTES del `.`
- `.5` actualmente produce `Dot` + `Integer(5)`

## Quick verify (estado actual)
```bash
echo 'var x = .5; console.log(x);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (Dot no puede ir seguido de Integer en esa posición)
```

## Patrones a seguir
- `src/lexer.zig:289-300` — handler actual de `.` con `blk:` para returns múltiples
- `src/lexer.zig:305-317` — float parsing con `start = this.position`; usar `start - 1` para incluir el `.` en el literal
- `this.peekChar()` para mirar el siguiente sin consumir

## Gotchas
- `..` (DotDot — range operator en Lou) y `...` (DotDotDot — spread) tienen prioridad sobre `.5` — verificar `peekChar() == '.'` ANTES de chequear dígito
- Asegurarse de guardar `start = this.position - 1` (o guardar antes de consumir `.`) para que el literal incluya el punto
- Después del `.`, NO debe seguir otro `.` (sería DotDot) — cortar el while si aparece
- El token es siempre `Float`, nunca `Integer` — `.0` es float 0.0, no int 0
- Cross-check con member access (`obj.prop`) — el `.` después de identificador NO debe disparar este path (ya está consumido por el member access path del parser)
- Si el `.` no va seguido de dígito, `.` ni nada (e.g. fin de input), seguir emitiendo `Dot` normal

## Código que falla

```js
var x = .5;           // Debería: Float(0.5), Actual: Dot + Integer(5)
var y = .125;         // Debería: Float(0.125)
console.log(x + .5);  // Debería: 1, Actual: error
```

## Implementacion sugerida

En `src/lexer.zig`, en el handler de `.` (línea 289-300), verificar si el siguiente carácter es un dígito:

```zig
'.' => blk: {
    if (this.peekChar() == '.') {
        // existing: DotDot / DotDotDot
    } else if (std.ascii.isDigit(this.peekChar())) {
        // Float starting with dot: .5, .125
        this.readChar(); // consume '.'
        while (std.ascii.isDigit(this.ch)) {
            this.readChar();
        }
        break :blk .{ .type = .Float, .literal = this.input[start..this.position] };
    } else {
        break :blk .{ .type = .Dot, .literal = "." };
    }
},
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

- `src/lexer.zig:289-300` — handler de `.`
- ECMAScript 12.9.3 Numeric Literals

### JS Examples Complejos

```js
var half = .5;
var quarter = .25;
var small = .001;

// In expressions
var result = .5 + .5;        // 1
var product = .5 * .5;       // 0.25
var comparison = .1 + .2;    // 0.30000000000000004 (IEEE 754)
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-leading-dot-float.js
node js/test-leading-dot-float.js
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
