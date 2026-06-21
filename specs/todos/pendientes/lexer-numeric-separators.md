# Lexer: Numeric separators

## status

NOT IMPLEMENTED

## Problema

El lexer no soporta separadores numéricos (`_`). `1_000_000` se tokeniza como `1` + identificador `_000_000`. ES2021 introdujo esta feature.

## Contexto

ECMAScript 12.9.3 Numeric Literals (ES2021): los `_` pueden aparecer entre dígitos en literales numéricos. No pueden estar al inicio, al final, ni duplicados (`1__2`).

## Baseline (qué existe ya)
- Lexer parsea enteros y decimales básicos (src/lexer.zig:305-317)
- `_` actualmente es tratado como identificador — `1_000` se rompe en `1` + ident `_000`
- `_` es ASCII pero no es dígito — agregar al loop de dígitos con validación

## Quick verify (estado actual)
```bash
echo 'console.log(1_000_000);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error (1 seguido de _000 que es identificador)
```

## Patrones a seguir
- `src/lexer.zig:305-317` — bloque de dígitos; agregar `or this.ch == '_'` al while
- `src/lexer.zig:30` — `std.ascii.isDigit` para validar dígitos
- `std.fmt.parseInt` / `parseFloat` — si decidís quitar `_` en el lexer, esto convierte la cadena limpia

## Gotchas
- Decisión de diseño: ¿quitar `_` en el lexer (devolver literal limpio) o dejarlo y limpiar en evaluador? Lo más simple es remover en lexer — evita ramificación en cada path de conversión
- Validar: NO leading `_` (`_100` inválido), NO trailing `_` (`100_` inválido), NO consecutivos (`1__2` inválido)
- Cross-check con `lexer-hex-octal-binary.md` — separadores en hex/bin deben funcionar (`0xFF_FF`)
- Cross-check con `lexer-exponential-notation.md` — `1_000e10` debe funcionar
- Cross-check con `lexer-dollar-identifier.md` — `$` y `_` son distintos, no mezclar
- Si validás en lexer, devolver error claro al usuario con la línea

## Código que falla

```js
var million = 1_000_000;          // Debería: 1000000
var hex = 0xFF_FF;                // Debería: 65535
var bin = 0b1010_0101;            // Debería: 165
var float = 1_000.5_0;            // Debería: 1000.5
var billion = 1_000_000_000;      // Debería: 1000000000
```

## Implementacion sugerida

En el lexer, durante el parsing de números, permitir `_` entre dígitos:

```zig
// In number parsing:
while (std.ascii.isDigit(this.ch) or this.ch == '_') {
    if (this.ch == '_') {
        // Validate: no leading _, no trailing _, no consecutive __
        this.readChar();
        if (!std.ascii.isDigit(this.ch)) {
            // error: invalid numeric separator
        }
        continue;
    }
    this.readChar();
}
```

El literal retornado debe incluir los `_` para que el evaluador/VM los quite al convertir a número, O quitarlos en el lexer y devolver el número limpio.

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
// Large numbers
var worldPopulation = 8_000_000_000;
var bytes = 0xFF_FF_FF_FF;

// Credit card style
var card = 4111_1111_1111_1111;

// Binary flags
var permissions = 0b1111_0000_1010_0101;

// Floats
var pi = 3.14_15_92_65;
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-numeric-separators.js
node js/test-numeric-separators.js
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
