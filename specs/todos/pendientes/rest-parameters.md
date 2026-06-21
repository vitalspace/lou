# Rest Parameters (...args)

## status
pendiente

## Problema
Los rest parameters (`...args`) en definiciones de funciones no están implementados. No se puede capturar un número variable de argumentos como array.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. ES2015 reemplazó el objeto `arguments` con rest parameters más limpios.

## Baseline (qué existe ya)
- Lexer YA tiene `.DotDotDot` token (`src/lexer.zig:108`) — usado en spread `...`
- `SpreadExpression` YA existe en AST (`src/ast.zig:54`)
- `FunctionDeclaration` YA existe (`src/ast.zig:45`)
- `ArrayLiteral` YA existe (`src/ast.zig:83`) para crear arrays
- Parser YA maneja spread en call args (probablemente)
- FALTA: `...name` como parámetro formal de función

## Quick verify (estado actual)
```bash
echo 'function f(...args) { return args.length; } console.log(f(1,2,3));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error o comportamiento incorrecto
```

## Patrones a seguir
- `src/lexer.zig:108` — `.DotDotDot` token
- `src/ast.zig:45-47` — `FunctionDeclaration`, `ArrowFunction` structs
- `src/parser.zig:1189` — `parseFunctionDeclaration` (línea aprox)
- `src/parser.zig` — buscar `parseFunctionParameters` o similar
- `src/ast.zig:54` — `SpreadExpression` (template de "..")
- `src/evaluator.zig` — buscar `FunctionCall` o call dispatch
- ECMAScript 14.1.4 — Function definitions

## Gotchas
- Solo el ÚLTIMO parámetro puede ser rest — SyntaxError si va en el medio
- `...args` es siempre un Array (nunca null/undefined)
- Array vacío si no hay argumentos extra
- `length` del array = args.length - normalParams.length
- Agregar campo `rest_param: ?[]const u8` a `FunctionDeclaration`/`ArrowFunction` structs
- Si agregás campo, actualizar freeAst, printAst, evaluator switch
- Al llamar función: si hay rest_param, crear ArrayObject con args restantes
- Cross-check con `default-parameters-compat.md` — pueden combinarse
- Cross-check con `arrow-rest-params.md` — spec similar que ya se implementó
- Arrow function `(...args) => args` — mismo parser path
- `arguments` legacy object — NO necesario implementar

## Código que falla
```js
function sum(...numbers) {
    return numbers.reduce((a, b) => a + b, 0);
}
console.log(sum(1, 2, 3, 4)); // 10
```

## Implementacion sugerida

### 1. Parser (src/parser.zig)
- En `parseFunctionParameters()`, detectar `...nombre` como último parámetro
- Almacenar el nombre del rest parameter en la definición de función

### 2. AST (src/ast.zig)
- Modificar `FunctionDeclaration`/`ArrowFunction` para indicar si tiene rest parameter

### 3. VM (src/vm.zig)
- En la llamada a función, recoger argumentos restantes en un array
- Asignar el array al nombre del rest parameter

### 4. Evaluator (src/evaluator.zig)
- Al llamar función, si hay rest parameter, crear array con argumentos sobrantes

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
- src/parser.zig — parseFunctionParameters()
- src/ast.zig — FunctionDeclaration
- src/vm.zig — call opcode

### JS Examples Complejos
```js
// Básico
function logAll(...items) {
    items.forEach(item => console.log(item));
}
logAll(1, 2, 3);

// Con parámetros normales
function greet(greeting, ...names) {
    return names.map(n => greeting + " " + n);
}
console.log(greet("Hello", "Alice", "Bob"));

// Arrow function
const sum = (...nums) => nums.reduce((a, b) => a + b, 0);
console.log(sum(1, 2, 3)); // 6

// Rest como único parámetro
const identity = (...args) => args;
console.log(identity(1, 2, 3)); // [1, 2, 3]

// Sin argumentos
const empty = (...args) => args.length;
console.log(empty()); // 0

// Con destructuring (combinación avanzada)
function process([first, ...rest]) {
    console.log("first:", first);
    console.log("rest:", rest);
}
process([1, 2, 3, 4]);

// Rest en método de objeto
const obj = {
    method(a, b, ...rest) {
        return [a, b, rest];
    }
};
console.log(obj.method(1, 2, 3, 4, 5)); // [1, 2, [3,4,5]]
```

### Verificacion
- `...args` captura todos los argumentos como array
- Puede combinarse con parámetros normales
- Solo puede ser el último parámetro
- Array vacío si no hay argumentos extra
- Funciona en funciones, arrow functions, y métodos

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/rest-params.js 2>&1 | od -c
node js/tests/rest-params.js 2>&1 | od -c

### pendiente
- Implementar parsing de rest parameters
- Modificar evaluación de llamadas para crear array de restos

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
