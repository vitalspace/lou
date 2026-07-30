# WeakMap

## status
pendiente

## Problema
El objeto `WeakMap` no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `WeakMap` es un Map donde las claves son objetos y se liberan automáticamente cuando no hay otras referencias.

## Baseline (qué existe ya)
- `Map` YA implementado (`src/builtins/map/`)
- `NewExpression` YA existe (`src/ast.zig:56`)
- `MAP_OBJECT` registrado en `src/builtins/builtinObjects.zig`
- WeakMap NO existe — pero Map provee la mayoría del código necesario
- GC de Zig: NO hay GC real — Zig usa allocadores explícitos

## Quick verify (estado actual)
```bash
echo 'const w = new WeakMap(); console.log(w);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "WeakMap is not defined"
```

## Patrones a seguir
- `src/builtins/map/` — Map implementation completa
- `src/builtins/map/map.zig` — BuiltinObject con métodos
- `src/builtins/builtinObjects.zig` — agregar WEAKMAP_OBJECT
- `src/builtins/number/number.zig` — patrón de constructor builtin

## Gotchas
- En Zig NO hay GC automático — WeakMap es difícil de implementar "verdaderamente"
- IMPLEMENTACIÓN MÍNIMA viable: WeakMap que se comporta como Map (sin weak refs reales)
- Documentar limitación: keys no se liberan automáticamente en Lou
- Solo acepta objetos como claves (no primitives) — validar con `value != .js_object and value != .array`
- `set/get/has/delete` retornan `this` para chaining (excepto `has`/`delete` que retornan bool)
- Constructor acepta iterable de pares `[key, value]`
- Si agregás `WeakMapObject` a runtime, actualizar `freeValue` en `src/environment.zig:15-25`
- Cross-check con `weakset.md` y `weakref.md` — patrón similar
- Para tests, evitar confiar en GC behavior — verificar API funcional solamente

## Código que falla
```js
const wm = new WeakMap();
const key = {};
wm.set(key, "value");
console.log(wm.get(key)); // "value"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/weakmap.zig`:
- Constructor `new WeakMap(iterable?)`
- `set(key, value)` — solo acepta objetos como clave
- `get(key)` — obtener valor
- `has(key)` — verificar existencia
- `delete(key)` — eliminar entrada

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
- src/builtins/map/map.zig — implementación de Map (referencia)
- src/builtins/builtins.zig — registro de constructores
- src/types/runtime.zig — Value union

### JS Examples Complejos
```js
// Básico
const wm = new WeakMap();
const obj1 = { name: "Alice" };
const obj2 = { name: "Bob" };

wm.set(obj1, 1);
wm.set(obj2, 2);

console.log(wm.get(obj1)); // 1
console.log(wm.get(obj2)); // 2
console.log(wm.has(obj1)); // true
console.log(wm.has({}));   // false

// Con constructor
const wm2 = new WeakMap([
    [{}, "a"],
    [{}, "b"],
]);

// Private data pattern
const privates = new WeakMap();
class User {
    constructor(name) {
        privates.set(this, { name });
    }
    getName() {
        return privates.get(this).name;
    }
}

// delete
const wm3 = new WeakMap();
const k = {};
wm3.set(k, "data");
console.log(wm3.has(k));   // true
wm3.delete(k);
console.log(wm3.has(k));   // false

// Solo objetos como claves
// wm.set(42, "value"); // TypeError
// wm.set("key", "value"); // TypeError
```

### Verificacion
- `new WeakMap()` crea un WeakMap vacío
- `set(key, value)` acepta solo objetos como claves
- `get(key)` retorna el valor asociado
- `has(key)` retorna boolean
- `delete(key)` elimina la entrada
- Claves se recolectan cuando no hay otras referencias (GC)

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/weakmap.js 2>&1 | od -c
node js/tests/weakmap.js 2>&1 | od -c

### pendiente
- Implementar WeakMap como builtin

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

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/weakmap.lou + tests/compat/weakmap.js to enable automatic PASS/FAIL tracking.

