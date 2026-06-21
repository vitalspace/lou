# Lexer: unsigned right shift >>>

## status

NOT IMPLEMENTED

## Problema

El operador `>>>` (unsigned right shift) no está en el lexer ni en el TokenType enum. ECMAScript lo requiere como operador bitwise fundamental.

## Contexto

ECMAScript define:
- `>>` — right shift (sign-preserving)
- `>>>` — unsigned right shift (zero-fill)
- `>>=` — right shift assignment
- `>>>=` — unsigned right shift assignment
- `<<=` — left shift assignment

## Baseline (qué existe ya)
- TokenType tiene `RightShift` (`>>`) y `LeftShift` (`<<`) — NO tiene las versiones de asignación ni `>>>`
- Lexer handler de `>` está en `src/lexer.zig:210-219` (solo maneja `>`, `>=`, `>>`)
- Lexer handler de `<` está en `src/lexer.zig:199-209` (solo maneja `<`, `<=`, `<<`)
- Evaluator ya maneja `LeftShift` y `RightShift` como `BinaryExpression`

## Quick verify (estado actual)
```bash
echo 'console.log(-1 >>> 1);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (>>> no se reconoce, queda como > > > o similar)
```

## Patrones a seguir
- `src/lexer.zig:199-209` — handler de `<`, agregar rama `<<=`
- `src/lexer.zig:210-219` — handler de `>`, agregar ramas `>>>`, `>>>=`, `>>=`
- `src/lexer.zig:11-50` — enum `TokenType` (agregar 4 nuevos tokens)
- Evaluator: buscar el switch sobre `BinaryExpression.operator` para `RightShift` y agregar `UnsignedRightShift`

## Gotchas
- `>>>` y `>>>=` tienen prioridad sobre `>>` y `>>=` — chequear 3 `>` antes que 2
- `>>>=` requiere chequear 4 caracteres consecutivos (`>`, `>`, `>`, `=`)
- En Zig, `>>>` para i64 con signo es UB si el resultado no entra en i64 — usar `@as(u64, @intCast(value)) >> shift` y luego `@bitCast` a i64 (técnica de zero-fill)
- JavaScript convierte operandos a Int32 (`ToInt32`) antes de shift — `1.5 >>> 0` da `1`, no `1.5`
- El operador `>>>` sobre BigInt es TypeError — pero BigInt tiene su propio spec
- Shift count está enmascarado a 0-31 en JS — `x >>> 32` es equivalente a `x >>> 0` (ToUint32)

## Código que falla

```js
console.log(-1 >> 1);    // Debería: -1 (sign-preserving)
console.log(-1 >>> 1);   // Debería: 2147483647 (zero-fill)
console.log(8 >>> 1);    // Debería: 4
```

## Implementacion sugerida

1. Agregar a `TokenType`:
```zig
UnsignedRightShift,       // >>>
UnsignedRightShiftAssign, // >>>=
LeftShiftAssign,          // <<=
RightShiftAssign,         // >>=
```

2. En el lexer, el handler de `>` (línea 210-219) necesita:
```zig
'>' => blk: {
    if (this.peekChar() == '>') {
        this.readChar();
        if (this.peekChar() == '>') {
            this.readChar();
            if (this.peekChar() == '=') {
                this.readChar();
                break :blk .{ .type = .UnsignedRightShiftAssign, .literal = ">>>=" };
            }
            break :blk .{ .type = .UnsignedRightShift, .literal = ">>>" };
        }
        if (this.peekChar() == '=') {
            this.readChar();
            break :blk .{ .type = .RightShiftAssign, .literal = ">>=" };
        }
        break :blk .{ .type = .RightShift, .literal = ">>" };
    }
    // ... existing >= check
},
```

3. Similar para `<` handler — agregar `<<=`.

4. En el evaluador/VM, implementar la operación bitwise unsigned right shift.

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

- `src/lexer.zig:210-219` — handler de `>`
- `src/lexer.zig:199-209` — handler de `<`
- ECMAScript 12.12 Binary Bitwise Operators

### JS Examples Complejos

```js
// Unsigned right shift
console.log(-1 >>> 0);   // 4294967295
console.log(-1 >>> 1);   // 2147483647
console.log(255 >>> 4);  // 15

// Assignment
var x = -1;
x >>>= 1;
console.log(x); // 2147483647

// Left shift assignment
var y = 1;
y <<= 4;
console.log(y); // 16
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-unsigned-right-shift.js
node js/test-unsigned-right-shift.js
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
