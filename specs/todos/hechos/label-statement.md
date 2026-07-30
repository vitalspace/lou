# Label Statements

## status
pendiente

## Problema
Las etiquetas (labels) para `break` y `continue` no están implementadas.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los labels permiten `break`/`continue` de loops anidados específicos.

## Baseline (qué existe ya)
- AST YA tiene `LabeledStatement` (`src/ast.zig:60`, struct en línea 222-225)
- Parser YA maneja labeled statements parcialmente (`src/parser.zig:171` — `node.* = .{ .LabeledStatement = .{...} }`)
- Environment YA tiene `break_label`, `continue_label`, `pending_loop_label` (`src/environment.zig:56-59`)
- FALTA: `BreakStatement` y `ContinueStatement` con campo `label` opcional — ver AST actual

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
outer: for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 3; j++) {
        if (j === 1) break outer;
        console.log(i, j);
    }
}
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error de parseo o "break outer" se ignora
```

## Patrones a seguir
- `src/ast.zig:60` — `LabeledStatement` enum (existe)
- `src/ast.zig:222-225` — `LabeledStatement` struct
- `src/parser.zig:171` — ya se crea el nodo LabeledStatement
- `src/environment.zig:56-59` — campos de label ya están listos
- `src/ast.zig` — buscar `BreakStatement` y `ContinueStatement` para agregar `label` opcional

## Gotchas
- `LabeledStatement` es un wrapper alrededor de un loop — el parser lo crea ANTES de saber si el body es un loop
- Solo se permiten labels en `for`/`while`/`do-while` — labels en bloques `{}` o `if` son SyntaxError
- `break label` debe buscar el loop con ese label y setear `break_label`
- Cross-check con `switch-case.md` — `switch` no acepta labels pero el `break` de switch puede usar label
- Cambios necesarios:
  - Agregar campo `label: ?[]const u8` a `BreakStatement` y `ContinueStatement` structs en AST
  - En parser, cuando se ve `break ident`, leer el identificador
  - En evaluator, comparar label con el del loop activo y propagar a través de labeled statements
- Stack de labels activos: cada `LabeledStatement` debe pushear su label al entrar y pop al salir

## Código que falla
```js
outer: for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 3; j++) {
        if (j === 1) break outer;
        console.log(i, j);
    }
}
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Los labels usan identificadores existentes seguidos de `:`. No se necesitan tokens nuevos.

### 2. AST (src/ast.zig)
- `LabelStatement` — `{ label, body }`
- Modificar `BreakStatement` y `ContinueStatement` para aceptar label opcional

### 3. Parser (src/parser.zig)
- Detectar `identificador:` antes de un loop como label
- `break label` y `continue label` parsean el identificador

### 4. VM (src/vm.zig)
- Opcode `break_label` y `continue_label` — saltar al loop con el label dado
- Mantener stack de labels activos

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
- src/parser.zig — parseStatement()
- src/ast.zig — BreakStatement, ContinueStatement
- src/vm.zig — jump opcodes

### JS Examples Complejos
```js
// Break con label
outer: for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 3; j++) {
        if (j === 1) break outer;
        console.log(i, j);
    }
}
// Solo imprime: 0 0

// Continue con label
outer: for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 3; j++) {
        if (j === 1) continue outer;
        console.log(i, j);
    }
}
// Imprime: 0 0, 1 0, 2 0

// Label en while
let i = 0;
outer: while (i < 3) {
    let j = 0;
    while (j < 3) {
        if (j === 1) { i++; continue outer; }
        console.log(i, j);
        j++;
    }
    i++;
}

// Label en do-while
let x = 0;
loop: do {
    x++;
    if (x === 2) continue loop;
    console.log(x);
} while (x < 3);
```

### Verificacion
- `label:` antes de un loop crea un label
- `break label` sale del loop etiquetado
- `continue label` continúa el loop etiquetado
- Labels anidados funcionan correctamente
- `break label` solo funciona con loops, no con bloques arbitrarios

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/labels.js 2>&1 | od -c
node js/tests/labels.js 2>&1 | od -c

### pendiente
- Implementar labels en parser, AST, y VM

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

- Compat test match: `-` (NO-MATCH)
- Test status: `-`

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/label-statement.lou + tests/compat/label-statement.js to enable automatic PASS/FAIL tracking.

