# Operador instanceof

## status
pendiente

## Problema
El operador `instanceof` no está implementado. No se puede verificar si un objeto es instancia de un constructor/clase.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `instanceof` es esencial para verificación de tipos en tiempo de ejecución.

## Baseline (qué existe ya)
- Lexer NO tiene keyword `instanceof` (src/lexer.zig — buscar `Instanceof`)
- AST NO tiene `InstanceOfExpression`
- `ObjectValue` (`src/types/runtime.zig`) — verificar si tiene campo `__proto__` para cadena prototipal
- `classes.md` spec cubre `class` pero ese spec tampoco está implementado

## Quick verify (estado actual)
```bash
echo 'console.log([] instanceof Array);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (instanceof no es keyword)
```

## Patrones a seguir
- `src/lexer.zig:74-95` — keywords; agregar `Instanceof` siguiendo el patrón
- `src/lexer.zig:442-460` — `getKeywordType` para mapear literal a TokenType
- `src/ast.zig:101-105` — `BinaryExpression` como referencia para operadores
- `src/evaluator.zig:380-450` — switch sobre BinaryExpression operator
- `src/types/runtime.zig` — `ObjectValue` para estructura interna con `__proto__`

## Gotchas
- `instanceof` requiere que `Constructor` tenga `.prototype` accesible — verificar si `class` y `function` constructor exponen `.prototype`
- Cross-check con `classes.md` — `class Foo {}; new Foo() instanceof Foo` debe funcionar
- Primitivos (`42 instanceof Number`) deben retornar `false` (no auto-boxing)
- Para Symbol.hasInstance: `obj instanceof type` puede llamar `type[Symbol.hasInstance](obj)` si está definido — feature avanzada, puede omitirse
- Precedencia similar a `in` (Relational, no menor que asignación)
- Right side puede ser cualquier expresión que tenga `.prototype` — usualmente identificador, pero no limitar
- Para arrays built-in, `Array.prototype` debe estar en la cadena de prototipos — implementar `__proto__` linkage

## Código que falla
```js
function Dog(name) { this.name = name; }
const d = new Dog("Rex");
console.log(d instanceof Dog); // true
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keyword: `InstanceOf`

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `InstanceOfExpression` — `obj Constructor`

### 3. Parser (src/parser.zig)
- En `parseExpression()`, parsear `expr instanceof Constructor`
- Precedencia similar a comparaciones (`<`, `>`, `==`)

### 4. VM (src/vm.zig)
- Opcode `instanceof_` — verificar cadena de prototipos
- Buscar `Constructor.prototype` en la cadena `__proto__` del objeto

### 5. Evaluator (src/evaluator.zig)
- `evaluateInstanceOfExpression()` — recorrer cadena prototipal
- Verificar si `Constructor.prototype` está en la cadena de prototipos del objeto

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
- src/vm.zig — Op enum
- src/types/runtime.zig — Value union
- src/evaluator.zig — evaluate()

### JS Examples Complejos
```js
// Básico
function Animal() {}
function Dog() {}
Dog.prototype = Object.create(Animal.prototype);
const d = new Dog();
console.log(d instanceof Dog);    // true
console.log(d instanceof Animal); // true

// Con arrays
console.log([] instanceof Array);  // true
console.log([] instanceof Object); // true

// Con funciones
function fn() {}
console.log(fn instanceof Function); // true

// Primitivos retornan false
console.log(42 instanceof Number);   // false
console.log("hi" instanceof String); // false

// En condicional
if (value instanceof Error) {
    console.log(value.message);
}

// Negación
if (!(data instanceof Array)) {
    throw new TypeError("Expected array");
}
```

### Verificacion
- `obj instanceof Constructor` verifica la cadena de prototipos
- Funciona con herencia multi-nivel
- Primitivos retornan `false`
- `null` y `undefined` retornan `false`
- Funciona con constructores built-in (Array, Function, etc.)

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/instanceof.js 2>&1 | od -c
node js/tests/instanceof.js 2>&1 | od -c

### pendiente
- Implementar keyword, AST, parser, VM opcode y evaluator para instanceof

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
