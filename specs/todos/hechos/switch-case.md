# Switch/Case

## status

**pendiente (drift corrected 2026-07-30)** — `tests/compat/switch-case.lou` FAILs per compat baseline (43P/39F/1S)

## Problema
El lexer tiene tokens `Switch`, `Case`, `Default` pero el parser y VM no implementan la sentencia `switch`.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los tokens existen en el lexer pero no hay parsing ni ejecución de switch/case.

## Baseline (qué existe ya)
- Lexer YA tiene tokens `.Switch`, `.Case`, `.Default` (`src/lexer.zig:79-81`)
- Lexer los mapea en `getKeywordType` (`src/lexer.zig:446-448`)
- AST NO tiene `SwitchStatement` (grep para confirmar)
- Evaluator NO maneja switch
- NOTA: `Match` existe como keyword alternativa (Lou-specific) — ver `src/lexer.zig:82` y cómo se implementa match para inspiración

## Quick verify (estado actual)
```bash
echo 'const x=2; switch(x){case 1: console.log("one"); break; case 2: console.log("two"); break;}' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error o comportamiento inesperado
```

## Patrones a seguir
- `src/lexer.zig:79-81` — tokens Switch/Case/Default (ya existen)
- `src/ast.zig` — buscar `IfStatement` (línea ~223) y `LabeledStatement` (línea ~222) como template de statement con sub-bloques
- `src/evaluator.zig:1939-1974` — `ThrowStatement`/`TryCatchFinally` como referencia de statements
- `src/environment.zig:54-58` — `break_hit`/`break_label` ya existen (pueden reusarse)
- `src/parser.zig:1060` — `parseIfStatement` como template de statement complejo

## Gotchas
- FALL-THROUGH es tricky: si no hay `break`, ejecutar también los cases siguientes
- `default` puede aparecer en cualquier posición (no solo al final)
- El discriminant se evalúa UNA vez y se compara con cada case usando `===` (no `==`)
- `break` en switch debe setear `env.break_hit = true` y verificarse después de cada case
- Si usás un AST node nuevo (`SwitchStatement`), actualizar `freeAst` (~line 800) y `printAst` (~line 470)
- Caso sin break al final: si no hay nada después, simplemente cae del switch sin acción
- `case` clauses múltiples con mismo valor: solo se ejecuta el primero (los siguientes son inalcanzables)
- Para fall-through, cada case es un bloque independiente pero sin break implícito

## Código que falla
```js
const x = 2;
switch (x) {
    case 1:
        console.log("one");
        break;
    case 2:
        console.log("two");
        break;
    default:
        console.log("other");
}
```

## Implementacion sugerida

### 1. AST (src/ast.zig)
Agregar `NodeType`:
- `SwitchStatement` — `{ discriminant, cases }`
- `SwitchCase` — `{ test, consequent }` (test=null para default)

### 2. Parser (src/parser.zig)
- `parseSwitchStatement()` — parsear `switch (expr) { case ...: ... default: ... }`
- Cada `case` tiene una expresión test y un bloque de consequents
- `default` tiene test=null

### 3. VM (src/vm.zig)
- Opcode `switch_` — evaluar discriminante y saltar al case correcto
- Opcode `case_test` — comparar valor con el case actual
- Opcode `case_jump` — saltar al siguiente case si no coincide
- Soporte para fall-through (sin break) vs break

### 4. Evaluator (src/evaluator.zig)
- `evaluateSwitchStatement()` — evaluar discriminante, iterar cases, ejecutar el que coincida
- Manejar `break` para salir del switch
- Fall-through: ejecutar todos los cases siguientes hasta break

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
- src/lexer.zig — tokens Switch, Case, Default
- src/ast.zig — NodeType enum
- src/parser.zig — parsePrimary(), parseStatement()
- src/vm.zig — Op enum

### JS Examples Complejos
```js
// Básico con fall-through
switch (day) {
    case "Mon":
    case "Tue":
    case "Wed":
    case "Thu":
    case "Fri":
        console.log("Weekday");
        break;
    case "Sat":
    case "Sun":
        console.log("Weekend");
        break;
}

// Sin break (fall-through intencional)
switch (action) {
    case "add":
        console.log("Adding...");
    case "process":
        console.log("Processing...");
    case "done":
        console.log("Done!");
        break;
}

// Default al final
switch (color) {
    case "red":
        console.log("Stop");
        break;
    case "green":
        console.log("Go");
        break;
    default:
        console.log("Unknown");
}

// Switch con expresiones
switch (true) {
    case x > 100:
        console.log("big");
        break;
    case x > 10:
        console.log("medium");
        break;
    default:
        console.log("small");
}

// Nested switch
switch (outer) {
    case "a":
        switch (inner) {
            case 1: console.log("a1"); break;
            case 2: console.log("a2"); break;
        }
        break;
    case "b":
        console.log("b");
        break;
}
```

### Verificacion
- `switch (expr)` evalúa la expresión discriminante
- `case expr:` compara con ===
- Fall-through funciona (sin break continúa al siguiente)
- `break` sale del switch
- `default:` se ejecuta si ningún case coincide
- Switch anidados funcionan correctamente

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/switch.js 2>&1 | od -c
node js/tests/switch.js 2>&1 | od -c

### pendiente
- Implementar AST nodes, parser, y VM opcodes para switch/case

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

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/switch-case.lou + tests/compat/switch-case.js to enable automatic PASS/FAIL tracking.

