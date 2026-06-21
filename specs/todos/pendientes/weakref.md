# WeakRef

## status
pendiente

## Problema
El objeto `WeakRef` no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `WeakRef` permite mantener referencias débiles a objetos que pueden ser recolectados por el GC.

## Baseline (qué existe ya)
- ObjectValue ya existe (`src/types/runtime.zig`)
- WeakRef NO existe
- GC: NO hay GC automático en Zig — esto es un problema fundamental

## Quick verify (estado actual)
```bash
echo 'const r = new WeakRef({}); console.log(r);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "WeakRef is not defined"
```

## Patrones a seguir
- `src/builtins/number/number.zig` — patrón de constructor builtin
- `src/builtins/builtinObjects.zig` — agregar WEAKREF_OBJECT
- `src/builtins/weakmap/` (cuando se cree) — patrón WeakMap

## Gotchas
- LIMITACIÓN MAYOR: Zig no tiene GC automático — WeakRef "real" no es posible
- IMPLEMENTACIÓN PRAGMÁTICA: WeakRef que siempre retorna el target (no se libera)
- Documentar claramente que el comportamiento GC no es real en Lou
- Solo acepta objetos como target — validar con `value != .js_object`
- `deref()` retorna el target o undefined
- Si agregás `WeakRefObject` a runtime, actualizar `freeValue` en `src/environment.zig:15-25`
- Tests deben verificar API funcional, no GC behavior (porque no hay GC)
- Cross-check con `weakmap.md` y `weakset.md` — patrón similar

## Código que falla
```js
let obj = { data: 42 };
const ref = new WeakRef(obj);
console.log(ref.deref()); // { data: 42 }
obj = null;
// Después de GC: ref.deref() podría retornar undefined
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/weakref.zig`:
- Constructor `new WeakRef(target)` — target debe ser un objeto
- `deref()` — retorna el objeto si todavía existe, undefined si fue recolectado

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
- src/types/runtime.zig — Value union
- src/builtins/builtins.zig — registro de constructores

### JS Examples Complejos
```js
// Básico
let target = { name: "Alice" };
const ref = new WeakRef(target);
console.log(ref.deref()); // { name: "Alice" }

// Después de deref, el objeto puede ser recolectado
target = null;
// ref.deref() puede retornar undefined después de GC

// Cache pattern
const cache = new Map();
function getCached(key, factory) {
    const ref = cache.get(key);
    if (ref) {
        const cached = ref.deref();
        if (cached !== undefined) return cached;
    }
    const value = factory(key);
    cache.set(key, new WeakRef(value));
    return value;
}

// target debe ser objeto
// new WeakRef(42);    // TypeError
// new WeakRef("str"); // TypeError
```

### Verificacion
- `new WeakRef(obj)` crea una referencia débil
- `ref.deref()` retorna el objeto si existe
- `ref.deref()` retorna undefined si fue recolectado
- Solo acepta objetos como target

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/weakref.js 2>&1 | od -c
node js/tests/weakref.js 2>&1 | od -c

### pendiente
- Implementar WeakRef como builtin
- Integrar con el garbage collector de Zig

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
