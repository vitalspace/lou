# Operador in

## status
pendiente

## Problema
El operador `in` no está implementado. No se puede verificar si una propiedad existe en un objeto.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. El lexer tiene el token `In` pero solo se usa para `for...in`. El operador `in` como expresión no está soportado.

## Baseline (qué existe ya)
- Lexer tiene token `In` (src/lexer.zig:75) — usado solo por `for...in` en parser
- `src/parser.zig:881` — actual uso en `ForInLoop`
- NO existe `InExpression` en AST
- `ObjectValue` (`src/types/runtime.zig`) tiene HashMap de propiedades

## Quick verify (estado actual)
```bash
echo 'const o = {a:1}; console.log("a" in o);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (`in` no es válido como operador binario)
```

## Patrones a seguir
- `src/ast.zig:39-40` — `ForOfLoop`, `ForInLoop` como referencia de AST nodes para loops
- `src/ast.zig:101-105` — `BinaryExpression` como referencia para operadores binarios
- `src/parser.zig:881` — actual parsing de `In` en `ForInLoop`
- `src/parser.zig:770-830` — `parseAssignment` para agregar rama de `In` como expresión
- `src/evaluator.zig:380` — switch sobre `BinaryExpression.operator`; agregar caso `In` (o crear `InExpression` separado)
- `src/types/runtime.zig` — `ObjectValue.properties.contains()` para check de existencia

## Gotchas
- Precedencia: `in` debe tener precedencia de Relational (entre `==` y `&&`) — NO menor que assignment (`x = "a" in obj` debe funcionar)
- Right-associative con respecto a `for...in` — en `parseStatement`, antes de `In` keyword verificar contexto
- Cross-check con `for...in` — la sintaxis `for (var x in obj)` debe seguir funcionando; `in` como expresión solo aparece en expression context
- `"toString" in obj` debe retornar `true` (heredado de prototipo) — recorrer cadena `__proto__`
- Para arrays, `0 in [1,2,3]` es `true` pero `"length" in arr` también (length es propiedad enumerable)
- Cross-check con `delete-operator.md` — `"x" in obj` debe reflejar deletions

## Código que falla
```js
const obj = { a: 1, b: 2 };
console.log("a" in obj);  // true
console.log("c" in obj);  // false
```

## Implementacion sugerida

### 1. AST (src/ast.zig)
Agregar `NodeType`:
- `InExpression` — `"prop" in obj`

### 2. Parser (src/parser.zig)
- En `parseExpression()`, después de parsear una expresión, detectar `in` seguido de otra expresión
- Crear `InExpression` con `left` (propiedad) y `right` (objeto)
- Precedencia similar a `instanceof`

### 3. VM (src/vm.zig)
- Opcode `in_` — verificar si la propiedad existe en el objeto
- Buscar en propiedades propas y en la cadena de prototipos

### 4. Evaluator (src/evaluator.zig)
- `evaluateInExpression()` — buscar propiedad en el objeto
- Para `js_object`: verificar en el HashMap de propiedades
- Para `array`: verificar si el índice es válido
- Para `BuiltinObject`: verificar propiedades del builtin

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
- src/lexer.zig — token `In`
- src/parser.zig — parseExpression()
- src/types/runtime.zig — ObjectValue, ArrayObject
- src/vm.zig — Op enum

### JS Examples Complejos
```js
// Básico
const obj = { a: 1, b: 2, c: 3 };
console.log("a" in obj);  // true
console.log("z" in obj);  // false

// Con arrays (índices)
const arr = [10, 20, 30];
console.log(0 in arr);    // true
console.log(5 in arr);    // false

// Herencia prototipal
console.log("toString" in obj); // true (heredado)

// Con variables
const key = "b";
console.log(key in obj);  // true

// En condicional
if ("name" in user) {
    console.log(user.name);
}

// Negación
if (!("secret" in obj)) {
    console.log("no secret");
}
```

### Verificacion
- `"prop" in obj` retorna `true` si la propiedad existe
- Retorna `false` si no existe
- Funciona con arrays (índices)
- Propiedades heredadas (prototipo) retornan `true`
- Funciona con variables como clave

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/in-operator.js 2>&1 | od -c
node js/tests/in-operator.js 2>&1 | od -c

### pendiente
- Implementar AST node, parser, VM opcode y evaluator para `in`

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
