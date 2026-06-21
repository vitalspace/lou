# WeakSet

## status
pendiente

## Problema
El objeto `WeakSet` no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `WeakSet` es un Set donde los elementos son objetos y se liberan automáticamente.

## Baseline (qué existe ya)
- `Set` YA implementado (`src/builtins/set/`)
- `NewExpression` YA existe (`src/ast.zig:56`)
- `SET_OBJECT` registrado en `src/builtins/builtinObjects.zig`
- WeakSet NO existe — patrón similar a WeakMap pero con set semantics

## Quick verify (estado actual)
```bash
echo 'const w = new WeakSet(); console.log(w);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "WeakSet is not defined"
```

## Patrones a seguir
- `src/builtins/set/` — Set implementation (referencia)
- `src/builtins/weakmap/` (cuando se cree) — patrón WeakMap
- `src/builtins/builtinObjects.zig` — agregar WEAKSET_OBJECT
- `src/builtins/number/number.zig` — patrón de constructor builtin

## Gotchas
- Misma limitación que WeakMap: Zig NO tiene GC automático
- IMPLEMENTACIÓN MÍNIMA viable: WeakSet que se comporta como Set (sin weak refs reales)
- Solo acepta objetos como elementos — validar
- `add(value)` retorna `this` para chaining
- `has(value)` retorna boolean
- `delete(value)` retorna boolean (true si eliminó)
- Constructor acepta iterable
- Cross-check con `weakmap.md` y `weakref.md`
- Para tests: verificar API funcional, no GC behavior

## Código que falla
```js
const ws = new WeakSet();
const obj = {};
ws.add(obj);
console.log(ws.has(obj)); // true
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/weakset.zig`:
- Constructor `new WeakSet(iterable?)`
- `add(value)` — solo acepta objetos
- `has(value)` — verificar existencia
- `delete(value)` — eliminar entrada

### 2. Registro
Registrar como constructor en `builtins.zig`.

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
- src/builtins/set/ — implementación de Set (referencia)
- src/builtins/builtins.zig — registro de constructores

### JS Examples Complejos
```js
// Básico
const ws = new WeakSet();
const a = {};
const b = {};
ws.add(a);
ws.add(b);
console.log(ws.has(a)); // true
console.log(ws.has({})); // false

// Constructor con iterable
const ws2 = new WeakSet([{}, {}, {}]);

// delete
ws.delete(a);
console.log(ws.has(a)); // false

// Tracking visited objects
const visited = new WeakSet();
function process(obj) {
    if (visited.has(obj)) return;
    visited.add(obj);
    // process obj...
}

// Solo objetos
// ws.add(42);     // TypeError
// ws.add("str");  // TypeError
```

### Verificacion
- `new WeakSet()` crea un WeakSet vacío
- `add(value)` acepta solo objetos
- `has(value)` retorna boolean
- `delete(value)` elimina la entrada
- Elementos se recolectan cuando no hay otras referencias

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/weakset.js 2>&1 | od -c
node js/tests/weakset.js 2>&1 | od -c

### pendiente
- Implementar WeakSet como builtin

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
