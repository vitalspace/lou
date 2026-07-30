# structuredClone

## status
pendiente

## Problema
La función global `structuredClone()` no está implementada.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `structuredClone` crea deep copies de objetos usando el structured clone algorithm.

## Baseline (qué existe ya)
- `src/builtins/builtins.zig` — registro de funciones globales
- `ObjectValue`, `ArrayObject`, `Map`, `Set`, `Date` YA implementados
- `structuredClone` NO existe
- Tipos clonables: primitives, arrays, objects, Map, Set, Date, RegExp
- Tipos NO clonables: functions, symbols

## Quick verify (estado actual)
```bash
echo 'const o = {a:1}; const c = structuredClone(o); console.log(c.a);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "structuredClone is not defined"
```

## Patrones a seguir
- `src/builtins/builtins.zig` — agregar `structuredClone` al registro
- `src/builtins/json/` — patrón de builtin function
- `src/types/runtime.zig` — `Value` union para switch sobre tipo
- `src/builtins/map/`, `src/builtins/set/` — patterns para Map/Set cloning

## Gotchas
- IMPLEMENTACIÓN MÍNIMA: clonar objects, arrays, primitives; lanzar error para otros tipos
- Cycle detection: trackear `HashMap(originalValue, clonedValue)` para resolver ciclos
- Recursive: cada propiedad clonada recursivamente
- Funciones: NO se pueden clonar → `DataCloneError`
- Symbols: NO se pueden clonar → `DataCloneError`
- Strings resultantes deben allocarse con `env.allocator` y tracked en `env.owned_strings`
- Si Map/Set están implementados, agregar lógica para clonarlos también
- Date: clonar timestamp
- IMPLEMENTACIÓN PASO A PASO:
  1. Primitives: retornar tal cual (ya son inmutables)
  2. Arrays: clonar elemento por elemento
  3. Objects: clonar propiedad por propiedad
  4. Map: nuevo Map con entries clonadas
  5. Set: nuevo Set con valores clonados
- Para cada tipo nuevo que se clone, agregar caso al switch
- Cross-check con `typed-arrays.md` — ArrayBuffer cloning es complejo

## Código que falla
```js
const original = { a: 1, b: { c: 2 } };
const clone = structuredClone(original);
clone.b.c = 99;
console.log(original.b.c); // 2 (no afectado)
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Registrar `structuredClone` como función global:
- `structuredClone(value, options?)` — deep clone de value
- Soportar: objetos, arrays, Map, Set, Date, RegExp, ArrayBuffer, TypedArrays, Blob, File
- `options.transfer` — transferir ownership de ArrayBuffers
- Lanzar `DataCloneError` para valores no clonables (funciones, symbols)

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
- src/builtins/builtins.zig — registro de funciones globales
- src/types/runtime.zig — Value union

### JS Examples Complejos
```js
// Básico
const obj = { a: 1, b: [2, 3], c: { d: 4 } };
const clone = structuredClone(obj);
clone.c.d = 99;
console.log(obj.c.d); // 4 (no afectado)

// Nested
const deep = { x: { y: { z: 1 } } };
const deepClone = structuredClone(deep);
deepClone.x.y.z = 2;
console.log(deep.x.y.z); // 1

// Date
const date = new Date("2024-01-15");
const dateClone = structuredClone(date);
console.log(dateClone.getTime() === date.getTime()); // true

// Map
const map = new Map([["a", 1], ["b", 2]]);
const mapClone = structuredClone(map);
mapClone.set("c", 3);
console.log(map.size); // 2

// Set
const set = new Set([1, 2, 3]);
const setClone = structuredClone(set);
setClone.add(4);
console.log(set.size); // 3

// ArrayBuffer
const buf = new ArrayBuffer(8);
const view = new Float64Array(buf);
view[0] = 3.14;
const bufClone = structuredClone(buf);
const viewClone = new Float64Array(bufClone);
console.log(viewClone[0]); // 3.14

// Circular references
const circular = {};
circular.self = circular;
const circularClone = structuredClone(circular);
console.log(circularClone.self === circularClone); // true
console.log(circularClone.self !== circular);       // true

// Error handling
try {
    structuredClone(() => {}); // funciones no son clonables
} catch (e) {
    console.log(e instanceof DOMException); // DataCloneError
}
```

### Verificacion
- Crea deep copy de objetos y arrays
- Maneja objetos anidados correctamente
- Clona Map, Set, Date, RegExp, ArrayBuffer
- Maneja referencias circulares
- Lanza error para valores no clonables (funciones)
- `options.transfer` transfiere ArrayBuffers

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/structured-clone.js 2>&1 | od -c
node js/tests/structured-clone.js 2>&1 | od -c

### pendiente
- Registrar structuredClone como función global
- Implementar structured clone algorithm

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

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/structured-clone.lou + tests/compat/structured-clone.js to enable automatic PASS/FAIL tracking.

