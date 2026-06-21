# Empty statement (;)

## status

NOT IMPLEMENTED

## Problema

El parser no maneja el empty statement (`;` solo en una línea). ECMAScript permite `;` como statement vacío. Esto es útil como body de loops vacíos o como separador.

## Contexto

ECMAScript 14.4 Empty Statement: `;` es un statement válido que no hace nada.

## Baseline (qué existe ya)
- TokenType YA tiene `.Semicolon` (`src/lexer.zig:104`)
- Lexer YA emite `Semicolon` para `;` (handler en `src/lexer.zig` línea ~221)
- AST NO tiene `EmptyStatement` (grep para confirmar)
- Parser NO maneja `;` como statement independiente
- Posible causa: el `;` se consume pero no genera nodo, o causa error

## Quick verify (estado actual)
```bash
echo ';' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error de parseo o no-op silencioso
echo 'if (true);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error porque if espera statement no-vacío después
```

## Patrones a seguir
- `src/lexer.zig:104` — `.Semicolon` token
- `src/parser.zig:88` — `parseStatement` switch (buscar la línea exacta del switch principal)
- `src/parser.zig:270` — `parseBlockStatement` que itera statements
- `src/parser.zig:1060` — `parseIfStatement` (el `;` puede aparecer como consequence)

## Gotchas
- Cambio MÍNIMO: agregar caso `.Semicolon` en `parseStatement` que consuma el token y retorne un nodo
- Decisión de diseño: ¿crear `EmptyStatement` AST node o retornar un marker? Más limpio crear el node
- Si agregás AST node, actualizar `freeAst` (~line 800), `printAst` (~line 470), switch en `evaluate` (~line 187)
- `while (cond);` con empty body debe funcionar — el `;` es el statement del while
- `for (;;);` debe crear infinite loop con body vacío
- `;;;` (múltiples) deben encadenar
- Verificar que `;` después de `if/while/for` no se interprete como empty statement adicional (consumir solo una vez)

## Código que falla

```js
;                    // Debería: parsear como empty statement
if (true);           // Debería: if con body vacío
while (false);       // Debería: while con body vacío
for (;;);            // Debería: infinite loop con body vacío
;;                   // Dos empty statements
```

## Implementacion sugerida

En `src/parser.zig:88` (parseStatement), agregar caso para `Semicolon`:

```zig
// Add to the switch in parseStatement:
.Semicolon => {
    this.nextToken(); // consume ';'
    return ast.Node{ .type = .EmptyStatement };
},
```

O simplemente retornar un nodo vacío/nulo que el evaluador ignore.

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

- `src/parser.zig:88` — `parseStatement` switch
- ECMAScript 14.4 Empty Statement

### JS Examples Complejos

```js
// Empty loop body
for (var i = 0; i < 10; i++) ;

// Empty if body
if (condition) ;
else doSomething();

// Consecutive empty statements
;;;
console.log("after empties");

// Empty function body
function noop() { ; }
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-empty-statement.js
node js/test-empty-statement.js
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
