# Object Static Methods (completos)

## status
pendiente

## Problema
Faltan varios métodos estáticos de `Object`: `fromEntries`, `is`, `groupBy`, `getOwnPropertyDescriptors`, `getOwnPropertySymbols`, `preventExtensions`, `seal`, `freeze`, `isExtensible`, `isSealed`, `isFrozen`.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Ya tiene `assign`, `create`, `entries`, `hasOwn`, `keys`, `values`.

## Baseline (qué existe ya)
- `OBJECT_OBJECT` YA está registrado (`src/builtins/builtinObjects.zig:8`)
- Métodos existentes: `assign`, `create`, `entries`, `hasOwn`, `keys`, `values`
- `ObjectValue` tiene HashMap de propiedades (`src/types/runtime.zig`)
- Faltan 11 métodos: fromEntries, is, groupBy, descriptors, symbols, preventExtensions, seal, freeze, isExtensible, isSealed, isFrozen

## Quick verify (estado actual)
```bash
echo 'console.log(Object.is(NaN, NaN));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: false (Object.is no existe, usa === que retorna false para NaN)
echo 'console.log(Object.fromEntries([["a",1]]));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error (Object.fromEntries no existe)
```

## Patrones a seguir
- `src/builtins/object/object.zig` — registro de OBJECT_OBJECT
- `src/builtins/object/` — métodos individuales (patrón de un archivo por método)
- `src/builtins/math/abs.zig` — ejemplo de builtin method individual
- `src/builtins/map/` — Map.groupBy (relacionado, ver `map-groupby.md`)

## Gotchas
- Crear un archivo `.zig` por método siguiendo convención
- `Object.is` vs `===`: `Object.is(NaN, NaN) === true`, `Object.is(+0, -0) === false`
- `Object.fromEntries(iterable)`: aceptar Map, Array de pairs, u otro iterable
- Freeze/seal/preventExtensions: agregar campos booleanos a ObjectValue (o un enum de estado)
- Si agregás campos a ObjectValue, actualizar TODOS los lugares que allocan (init, deinit)
- `getOwnPropertyDescriptors`: retornar objeto con `{value, writable, enumerable, configurable}` por cada prop
- `getOwnPropertySymbols`: filtrar propiedades que son símbolos (SymbolValue)
- Cross-check con `prototype-chain.md` — `isFrozen/Sealed` deben chequear también el prototype
- Subclases: `Array.isArray` ya está (en array/), `Object.is` no

## Código que falla
```js
console.log(Object.is(NaN, NaN));     // true
console.log(Object.is(+0, -0));       // false

const entries = [["a", 1], ["b", 2]];
console.log(Object.fromEntries(entries)); // { a: 1, b: 2 }
```

## Implementacion sugerida

### 1. Builtin (src/builtins/object/)
Agregar métodos estáticos a `OBJECT_OBJECT`:

- `Object.fromEntries(iterable)` — crear objeto desde pares [key, value]
- `Object.is(value1, value2)` — comparación estricta (SameValue)
- `Object.groupBy(items, callbackFn)` — agrupar elementos (ES2024)
- `Object.getOwnPropertyDescriptors(obj)` — obtener todos los descriptores
- `Object.getOwnPropertySymbols(obj)` — obtener símbolos
- `Object.preventExtensions(obj)` — prevenir nuevas propiedades
- `Object.seal(obj)` — sellar objeto (no add/delete, modificar existentes)
- `Object.freeze(obj)` — congelar objeto (solo lectura)
- `Object.isExtensible(obj)` — verificar si es extensible
- `Object.isSealed(obj)` — verificar si está sellado
- `Object.isFrozen(obj)` — verificar si está congelado

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
- src/builtins/object/ — implementación actual
- src/types/runtime.zig — ObjectValue

### JS Examples Complejos
```js
// Object.fromEntries
const map = new Map([["a", 1], ["b", 2]]);
console.log(Object.fromEntries(map)); // { a: 1, b: 2 }
console.log(Object.fromEntries([["x", 10], ["y", 20]])); // { x: 10, y: 20 }

// Object.is
console.log(Object.is(42, 42));       // true
console.log(Object.is(NaN, NaN));     // true (diferente de ===)
console.log(Object.is(+0, -0));       // false (diferente de ===)
console.log(Object.is("a", "a"));     // true
console.log(Object.is({}, {}));       // false

// Object.groupBy
const items = [
    { name: "apple", type: "fruit" },
    { name: "carrot", type: "vegetable" },
    { name: "banana", type: "fruit" },
];
const grouped = Object.groupBy(items, item => item.type);
console.log(grouped.fruit.length); // 2

// Object.freeze
const frozen = Object.freeze({ x: 1, y: 2 });
frozen.z = 3; // silent fail en sloppy, TypeError en strict
console.log(Object.isFrozen(frozen)); // true
console.log(frozen.x); // 1

// Object.seal
const sealed = Object.seal({ a: 1 });
sealed.a = 2;       // ok (modificar existente)
// sealed.b = 3;    // no puede agregar
// delete sealed.a; // no puede eliminar
console.log(Object.isSealed(sealed)); // true

// Object.preventExtensions
const obj = { x: 1 };
Object.preventExtensions(obj);
// obj.y = 2; // no puede agregar
console.log(Object.isExtensible(obj)); // false

// Object.getOwnPropertyDescriptors
const desc = Object.getOwnPropertyDescriptor({ x: 1 }, "x");
console.log(desc.value);       // 1
console.log(desc.writable);    // true
console.log(desc.enumerable);  // true

// Object.getOwnPropertySymbols
const sym = Symbol("test");
const obj2 = { [sym]: 42, a: 1 };
console.log(Object.getOwnPropertySymbols(obj2).length); // 1
```

### Verificacion
- `Object.fromEntries` crea objeto desde iterable de pares
- `Object.is` usa SameValue (NaN === NaN, +0 !== -0)
- `Object.groupBy` agrupa elementos por callback
- `Object.freeze` hace objeto inmutable
- `Object.seal` previene add/delete pero permite modificar
- `Object.preventExtensions` previene nuevas propiedades
- Métodos de verificación (isFrozen, isSealed, isExtensible) retornan boolean

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/object-methods.js 2>&1 | od -c
node js/tests/object-methods.js 2>&1 | od -c

### pendiente
- Implementar todos los Object static methods faltantes

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

- Compat test match: `date-object.lou` (FUZZY — object)
- Test status: `FAIL`

- Diff excerpt:

```
1,19c1,21
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
< undefined
```

- Disposition: stays in pendientes/ — fuzzy-matched test currently FAILS, see diff excerpt below.

