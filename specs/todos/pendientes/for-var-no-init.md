# for (var x; ...) sin inicializador

## status

NOT IMPLEMENTED

## Problema

El parser crashea con `ExpectedAssign` cuando un `for` loop tiene una declaración `var`/`let`/`const` sin inicializador. ECMAScript permite `for (var i; i < 10; i++)`.

## Contexto

ECMAScript permite declaraciones de variables sin inicializador en el init de un for loop:
- `for (var i; i < 10; i++)` — válido
- `for (let x;;)` — válido
- `for (var i = 0, j; i < 10; i++)` — válido

## Baseline (qué existe ya)
- Parser maneja `for (init; cond; incr)` (`src/parser.zig` — buscar `parseForStatement`)
- AST `ForLoop` tiene `init: ?*Node` opcional (`src/ast.zig:125-129`)
- FALLA: cuando init es una `VariableDeclaration` o `LetDeclaration` sin `=`, el parser exige `=` con `error.ExpectedAssign`
- Similar para `for (let x;;)` — el loop sin condición es válido en JS

## Quick verify (estado actual)
```bash
echo 'for (var i; i < 3; i++) console.log(i);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error "ExpectedAssign"
```

## Patrones a seguir
- `src/parser.zig` — buscar `parseForStatement` (probablemente línea ~986)
- `src/parser.zig` — buscar `parseVariableDeclaration` o donde se parsea `var x = ...`
- `src/ast.zig:114-121` — `VariableDeclaration` y `LetDeclaration` structs (ver si `value` es opcional)
- `src/evaluator.zig` — buscar `ForLoop =>` para entender cómo se evalúa el init

## Gotchas
- `for (var i; ...)` — `i` queda undefined
- `for (let x;;)` — infinite loop con `x` undefined (no condición)
- `for (var i = 0, j; ...)` — múltiples declaraciones, algunas con init y otras sin
- En `VariableDeclaration` y `LetDeclaration`, hacer `value` opcional (`?*Node` en vez de `*Node`)
- Si haces el campo opcional, actualizar TODOS los lugares que lo usan (evaluator, freeAst, printAst)
- O alternativa: crear un nuevo nodo `VariableDeclarationNoInit` o usar `VoidLiteral` como sentinel
- Cross-check con `let-per-iteration.md` — para `let`, también debe crear nuevo binding cada iteración
- `for (const x = 1;;) ...` — `const` sin init es SyntaxError en JS

## Código que falla

```js
var i;
for (var i; i < 10; i++) {
    console.log(i);  // Debería: error (i es undefined) o 0-9 si se inicializa antes
}

for (let x;;) {
    break;  // Debería: funcionar
}
```

## Implementacion sugerida

En `src/parser.zig:886`, verificar si hay `=` antes de exigirlo:

```zig
// Antes:
if (this.current_token.type != .Assign) return error.ExpectedAssign;

// Después:
if (this.current_token.type == .Assign) {
    this.nextToken(); // consume '='
    const value = try this.parseExpression(.Lowest);
    // ... create init node with value
} else if (this.current_token.type == .Semicolon or this.current_token.type == .Comma) {
    // No initializer — var x; or var x, y;
    // ... create init node without value
} else {
    return error.ExpectedAssign;
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

- `src/parser.zig:886` — verificación de `Assign` en for loop
- ECMAScript 14.7.4.2 Runtime Semantics: ForLoopEvaluation

### JS Examples Complejos

```js
// Uninitialized var in for
var i = 10;
for (var i; i < 5; i++) {
    console.log(i); // undefined < 5 is false, loop body never executes
}

// Multiple vars, some without init
for (var i = 0, j; i < 3; i++) {
    console.log(i);
}

// Let without init
for (let x;;) {
    console.log("infinite");
    break;
}
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-for-no-init.js
node js/test-for-no-init.js
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
