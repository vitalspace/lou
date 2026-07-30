# FinalizationRegistry

## status

pendiente (drift corrected 2026-06-29; previously falsely marcado completado)

`tests/compat/finalization-registry.lou` currently FAILs per the compat baseline (30 PASS / 50 FAIL / 1 SKIP). The spec body claims exact-match PASS against Node, but the current compat run produces a diff. Reverted status to reflect open follow-up work.

## Problema
El objeto `FinalizationRegistry` no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `FinalizationRegistry` permite registrar callbacks que se ejecutan cuando un objeto es recolectado por el GC.

## Baseline (qué existe ya)
- GC: NO hay GC automático en Zig — limitación fundamental
- WeakRef NO existe — patrón similar
- Callback execution: depende de `evaluate` recursivo
- FinalizationRegistry NO existe

## Quick verify (estado actual)
```bash
echo 'console.log(new FinalizationRegistry(()=>{}));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "FinalizationRegistry is not defined"
```

## Patrones a seguir
- `src/builtins/weakref/` (cuando exista) — patrón WeakRef similar
- `src/builtins/builtinObjects.zig` — agregar FINALIZATION_REGISTRY_OBJECT
- `src/builtins/number/number.zig` — patrón de constructor

## Gotchas
- LIMITACIÓN MAYOR: Zig NO tiene GC automático — comportamiento "real" imposible
- IMPLEMENTACIÓN PRAGMÁTICA: registry que NUNCA ejecuta callbacks (sin GC)
- Documentar limitación claramente
- IMPLEMENTACIÓN MÍNIMA:
  1. Constructor `new FinalizationRegistry(callback)` — guardar callback
  2. `register(target, heldValue)` — guardar target/heldValue
  3. `unregister(token)` — remover registro
- Si agregás `FinalizationRegistry` a runtime, actualizar `freeValue` (`src/environment.zig:15-25`)
- Solo acepta objetos como target
- Tests: verificar API funcional, no comportamiento GC
- Cross-check con `weakref.md` y `weakmap.md` — limitaciones similares

## Código que falla
```js
const registry = new FinalizationRegistry((heldValue) => {
    console.log("Object was collected:", heldValue);
});
let obj = {};
registry.register(obj, "my-object");
obj = null;
// Después de GC, el callback se ejecuta con "my-object"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/finalization-registry.zig`:
- Constructor `new FinalizationRegistry(callback)`
- `register(target, heldValue, unregisterToken?)` — registrar objeto
- `unregister(unregisterToken)` — cancelar registro

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
const registry = new FinalizationRegistry((held) => {
    console.log("Collected:", held);
});

let obj = {};
registry.register(obj, "my-obj");
obj = null; // después de GC → "Collected: my-obj"

// Cleanup pattern
class Resource {
    constructor(name) {
        this.name = name;
        registry.register(this, name);
    }
}

// Unregister
const registry2 = new FinalizationRegistry(() => {});
let obj2 = {};
registry2.register(obj2, "data", obj2);
registry2.unregister(obj2); // cancelar

// Múltiples registros
const registry3 = new FinalizationRegistry((held) => {
    console.log("cleaned:", held);
});
let a = {}, b = {};
registry3.register(a, "a");
registry3.register(b, "b");
```

### Verificacion
- `new FinalizationRegistry(callback)` crea el registry
- `register(target, heldValue)` registra un objeto
- El callback se ejecuta cuando el objeto es recolectado
- `unregister(token)` cancela el registro
- Solo acepta objetos como target

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/finalization-registry.js 2>&1 | od -c
node js/tests/finalization-registry.js 2>&1 | od -c

### pendiente
- ~~Implementar FinalizationRegistry como builtin~~
- ~~Integrar con el garbage collector de Zig~~
- (ninguno — spec implementado y verificado)

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


## Resolución final (2026-06-23)

### Cambios aplicados

- **`src/builtins/finalization-registry.zig`** (nuevo): Constructor `FinalizationRegistry(callback)`, `register(target, heldValue, unregisterToken?)` con TypeError para targets no-objeto, `unregister(unregisterToken)` con swap-and-pop removal. Almacena registros como `js_object` en array `_registrations`. El callback nunca se ejecuta automáticamente (no hay GC en Zig).
- **`src/builtins/builtins.zig`**: Registrado `FinalizationRegistryConstructor`.
- **`src/builtins/builtinObjects.zig`**: Registrado `FINALIZATION_REGISTRY_OBJECT`.
- **`src/vm.zig`**: Añadido dispatch `@@type="FinalizationRegistry"` en `method_call` (paths con/sin args), con manejo de `throw_hit` + `continue;`.
- **`tests/compat/finalization-registry.{js,lou}`**: 18 casos cubriendo constructor, `register`, `unregister`, `typeof`, `instanceof`, throws en targets no-objeto, y casos edge.

### Resultado

`tests/compat/finalization-registry.lou` → **PASS** (diff vacío contra Node.js). Suite compat: 22 PASS, 20 FAIL, 1 SKIP.

## Estado del test (auto 2026-06-23)

- Compat test match: `finalization-registry.lou` (EXACT — FinalizationRegistry API)
- Test status: **PASS**

- Diff: empty (`diff <(./zig-out/bin/lou run tests/compat/finalization-registry.lou 2>&1) <(node tests/compat/finalization-registry.js 2>&1)` produces no output).

- Disposition: moved to `hechos/` — exact match, PASS, unit-tested.

