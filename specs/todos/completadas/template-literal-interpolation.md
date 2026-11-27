# Template literals: interpolación de expresiones

## status

**completada** — implementada (compat: 81 PASS / 4 FAIL / 1 SKIP)

## Problema

Los template literals (backtick strings) almacenan `${expr}` como texto crudo. No hay parsing de interpolación. ECMAScript requiere que `${expr}` se evalúe como expresión y se concatene al string.

## Contexto

ECMAScript 12.9 Template Literals: un template literal con `${}` produce una llamada a `TaggedTemplateExpression` o una concatenación de template spans con expresiones evaluadas.

## Baseline (qué existe ya)
- Lexer YA tiene `TemplateString` token (`src/lexer.zig:397-415`)
- `readTemplateString` lee byte-por-byte hasta backtick de cierre
- NO detecta `${` ni cambia a contexto de expresión
- AST `StringLiteral` (`src/ast.zig:75-77`) usado para strings normales
- Template string se almacena como literal crudo

## Quick verify (estado actual)
```bash
echo 'var n = "World"; console.log(`Hello ${n}!`);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Hello ${n}!" — interpolación no se evalúa
```

## Patrones a seguir
- `src/lexer.zig:397-415` — `readTemplateString` actual (referencia a modificar)
- `src/lexer.zig:383-395` — `readString` como template de "leer hasta delimitador"
- `src/ast.zig` — `StringLiteral` (template para node de span)
- `src/parser.zig:293` — `parsePrecedece` (para parsear la expresión dentro de `${}`)
- `src/evaluator.zig` — buscar dónde se evalúa `TemplateString`

## Gotchas
- CAMBIO INVASIVO: el lexer debe cooperar con el parser para alternar entre string mode y expression mode
- Opción A (estándar ES): tokenizar en TemplateHead/Middle/Tail, parser maneja spans
- Opción B (simple): un único TemplateString con `${...}` que el evaluador post-procesa
- Opción A es más correcta pero requiere lexer/parser coordinated
- Opción B es suficiente para el caso común
- Si vas con Opción A, agregar tokens `TemplateHead`, `TemplateMiddle`, `TemplateTail`
- Si vas con Opción B, parsear `${expr}` con mini-parser dentro del evaluador — más fácil
- Coerción: `${42}` → "42", `${true}` → "true", `${null}` → "null", `${undefined}` → "undefined"
- Cross-check con `string-escapes.md` (lexer) — el escape `\$` debe ser literal
- Nested templates: `\`outer ${\`inner ${42}\`}\`` — lexer debe contar depth de backticks

## Código que falla

```js
var name = "World";
console.log(`Hello ${name}!`);  // Debería: "Hello World!", Actual: "Hello ${name}!"
console.log(`1 + 1 = ${1 + 1}`); // Debería: "1 + 1 = 2", Actual: "1 + 1 = ${1 + 1}"
```

## Implementacion sugerida

Opción A — En el lexer, tokenizar template literals en partes:
- `TemplateHead`: texto antes de `${`
- `TemplateMiddle`: texto entre `}` y `${`
- `TemplateTail`: texto después de `}`
- Cada `${` inicia un contexto de expresión normal

Opción B — En el evaluador, procesar `${expr}` como string interpolation:
- Al evaluar un `TemplateString`, buscar `${` en el literal
- Parsear la expresión entre `${` y `}`
- Evaluar la expresión y convertir a string
- Concatenar las partes

Opción B es más simple pero menos estándar.

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

- `src/lexer.zig:397-415` — `readTemplateString`
- `src/ast.zig` — TemplateString node
- ECMAScript 12.9 Template Literals

### JS Examples Complejos

```js
var user = { name: "Alice", age: 30 };
console.log(`Name: ${user.name}, Age: ${user.age}`);

// Expression evaluation
console.log(`Sum: ${1 + 2 + 3}`);

// Nested templates
console.log(`outer ${`inner ${42}`}`);

// Multi-line
var html = `
  <div>
    <h1>${user.name}</h1>
    <p>Age: ${user.age}</p>
  </div>
`;
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-template-interpolation.js
node js/test-template-interpolation.js
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


## Estado del test (auto 2026-06-22)

- Compat test match: `-` (NO-MATCH)
- Test status: `-`

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/template-literal-interpolation.lou + tests/compat/template-literal-interpolation.js to enable automatic PASS/FAIL tracking.

