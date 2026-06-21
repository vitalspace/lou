# Destructuring

## status
pendiente

## Problema
No existe soporte para destructuring de arrays ni objetos en asignaciones, declaraciones, ni parámetros de función.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. El destructuring es una feature esencial de ES2015+ que permite extraer valores de arrays/objetos de forma concisa.

## Baseline (qué existe ya)
- `ArrayLiteral` ya existe (`src/ast.zig:83`)
- `ObjectLiteral` ya existe (`src/ast.zig:90`)
- `VariableDeclaration`/`LetDeclaration`/`ConstantDeclaration` ya existen
- Function parameters ya existen (parsing en `src/parser.zig:1189`)
- Destructuring NO está implementado

## Quick verify (estado actual)
```bash
echo 'const [a, b] = [1, 2]; console.log(a, b);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (destructuring no se reconoce)
```

## Patrones a seguir
- `src/ast.zig:83-92` — `ArrayLiteral`, `ObjectLiteral` (referencias)
- `src/parser.zig:114-121` — VariableDeclaration/LetDeclaration/ConstantDeclaration structs
- `src/parser.zig:1189` — `parseFunctionDeclaration` (parámetros)
- `src/parser.zig:770-830` — `parseAssignment`
- `src/evaluator.zig` — buscar `VariableDeclaration =>`

## Gotchas
- Destructuring aparece en 3 contextos:
  1. Declaraciones: `const [a, b] = ...`, `let { x } = ...`
  2. Asignaciones: `[a, b] = ...`, `{ x } = ...`
  3. Parámetros: `function({ a }) {}`, `([a, b]) => ...`
- 3 formas de patterns: array, object, nested
- Defaults: `const [a = 10] = []` — a es 10
- Rest: `[a, ...rest] = arr` — rest es array
- Rename: `{ name: n } = obj` — n toma el valor de obj.name
- IMPLEMENTACIÓN MÍNIMA: array destructuring + object destructuring simples (sin rest, sin defaults)
- Decisión: AST node `DestructuringAssignment` con `pattern: ArrayPattern | ObjectPattern`
- O alternativa: desugar destructuring a múltiples assignments en el parser (más simple)
- Cross-check con `default-parameters-compat.md` y `rest-parameters.md`
- `function f([a, b]) {}` requiere el pattern en parámetros — mismo parser path

## Código que falla
```js
// Array destructuring
const [a, b, c] = [1, 2, 3];
console.log(a, b, c); // 1 2 3

// Object destructuring
const { name, age } = { name: "Alice", age: 30 };
console.log(name, age);

// Nested destructuring
const { x: { y } } = { x: { y: 42 } };

// Default values
const [p = 10, q = 20] = [1];
```

## Implementacion sugerida

### 1. AST (src/ast.zig)
Agregar `NodeType`:
- `ArrayDestructuring` — `[a, b, ...rest] = expr`
- `ObjectDestructuring` — `{ a, b: renamed } = expr`
- `RestElement` — `...rest` en destructuring

### 2. Parser (src/parser.zig)
- En `parsePrimary()`, detectar `[` o `{` seguido de `=` para destructuring
- `parseArrayPattern()` — parsear `[a, , b, ...rest]`
- `parseObjectPattern()` — parsear `{ a, b: rename, c = default }`
- Soporte en declaraciones: `const [a, b] = ...`, `let { x } = ...`
- Soporte en parámetros de función: `function({ a, b }) {}`

### 3. VM (src/vm.zig)
- Opcode `destr_array` — extraer elementos por índice
- Opcode `destr_object` — extraer propiedades por nombre
- Opcode `rest_array` / `rest_object` — capturar resto

### 4. Evaluator (src/evaluator.zig)
- `evaluateArrayDestructuring()` — iterar array asignando por posición
- `evaluateObjectDestructuring()` — buscar propiedades por nombre

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
- src/ast.zig — NodeType enum
- src/parser.zig — parsePrimary(), parseAssignment()
- src/vm.zig — Op enum

### JS Examples Complejos
```js
// Array con defaults y skip
const [x, , z = 10] = [1, 2];
// x=1, z=10

// Object con rename y default
const { name: n, age: a = 25 } = { name: "Bob" };
// n="Bob", a=25

// Nested
const { coords: { x, y } } = { coords: { x: 10, y: 20 } };

// Rest en array
const [first, ...rest] = [1, 2, 3, 4];
// first=1, rest=[2,3,4]

// Rest en object
const { a, ...others } = { a: 1, b: 2, c: 3 };
// a=1, others={b:2, c:3}

// Destructuring en for-of
const pairs = [[1, "a"], [2, "b"]];
for (const [num, letter] of pairs) {
    console.log(num, letter);
}

// Destructuring en parámetros
function greet({ name, greeting = "Hello" }) {
    return greeting + " " + name;
}

// Swap variables
let m = 1, n = 2;
[m, n] = [n, m];
```

### Verificacion
- Array destructuring asigna por posición
- Object destructuring asigna por nombre de propiedad
- Defaults se usan cuando el valor es undefined
- Rest captura elementos/propiedades restantes
- Nested destructuring funciona a cualquier profundidad
- Funciona en `const`, `let`, `var`, y asignaciones simples

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/destructuring.js 2>&1 | od -c
node js/tests/destructuring.js 2>&1 | od -c

### pendiente
- Implementar AST, parser, VM y evaluator para destructuring

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
