# Prototype chain

## status

NOT IMPLEMENTED

## Problema

Los objetos en Lou son flat key-value stores sin prototype chain. `({}).toString` no existe, `({}).hasOwnProperty` no existe. ECMAScript requiere que todos los objetos hereden de `Object.prototype`.

## Contexto

ECMAScript 10.1 Ordinary Object Internal Methods: la operación `[[Get]]` debe seguir la cadena de prototipos si la propiedad no se encuentra en el objeto directo.

## Baseline (qué existe ya)
- `ObjectValue` existe (`src/types/runtime.zig`) — HashMap de propiedades
- NO tiene campo `prototype` o `__proto__`
- Lookup de propiedades en VM (`src/vm.zig:1148-1188`) y evaluator (`src/evaluator.zig:2213-2239`)
- Ambos paths hacen lookup directo en `properties` — no siguen cadena
- Builtin objects (`Math`, `Array`, etc.) tienen sus métodos propios pero no exponen Object.prototype

## Quick verify (estado actual)
```bash
echo 'console.log({}.toString);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: undefined; esperado: función toString
```

## Patrones a seguir
- `src/types/runtime.zig` — agregar campo `prototype: ?*ObjectValue = null` a `ObjectValue`
- `src/vm.zig:1148-1188` — `get_prop` (modificar para walk chain)
- `src/evaluator.zig:2213-2239` — `MemberAccess` (modificar para walk chain)
- `src/builtins/object/` — dónde agregar `Object.prototype`
- `src/builtins/array/` — patrón para Array.prototype
- ECMAScript 10.1 — OrdinaryGet

## Gotchas
- Si agregás campo `prototype` a `ObjectValue`, actualizar init/deinit y todos los lugares que allocan
- Crear Object.prototype como singleton en initBuiltinObjects
- Object.prototype debe tener: `toString`, `valueOf`, `hasOwnProperty`, `isPrototypeOf`, `propertyIsEnumerable`, `constructor`
- Object literal `{}` debe setear `prototype = Object.prototype`
- `new Array()` debe setear `prototype = Array.prototype`
- Cycle detection: si el chain tiene ciclo (no debería pero defensivo), retornar null
- Cross-check con `instanceof-operator.md` — usa el chain
- Cross-check con `in-operator.md` — debe recorrer el chain también
- `obj.toString()` vs `obj.toString` — ambos deben funcionar (method call necesita `isCallable`)
- Builtins deben tener prototype asignado para que `arr instanceof Array` funcione

## Código que falla

```js
var obj = {};
console.log(obj.toString());          // Debería: "[object Object]", Actual: error
console.log(obj.hasOwnProperty("x")); // Debería: false, Actual: error
console.log(obj.constructor);         // Debería: Object, Actual: undefined
```

## Implementacion sugerida

1. Agregar campo `__proto__` o `prototype` al `ObjectValue`
2. En `get_prop` (VM) y `MemberAccess` (evaluator), si la propiedad no existe en el objeto, buscar en el prototype chain
3. Implementar `Object.prototype` con métodos básicos: `toString`, `valueOf`, `hasOwnProperty`, `isPrototypeOf`
4. Para arrays: `Array.prototype` hereda de `Object.prototype`
5. Para funciones: `Function.prototype` con `call`, `apply`, `bind`

```zig
// In ObjectValue:
prototype: ?*ObjectValue = null,

// In get_prop:
fn getProp(obj: *ObjectValue, prop: []const u8) ?Value {
    if (obj.properties.get(prop)) |v| return v;
    if (obj.prototype) |proto| return getProp(proto, prop);
    return null;
}
```

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

- `src/types/runtime.zig` — `ObjectValue` definition
- `src/vm.zig:1148-1188` — `get_prop`
- `src/evaluator.zig:2213-2239` — MemberAccess
- ECMAScript 10.1 Ordinary Object Internal Methods

### JS Examples Complejos

```js
// Prototype chain
var animal = { eats: true };
var rabbit = Object.create(animal);
console.log(rabbit.eats); // true

// Object.prototype methods
var obj = {};
console.log(obj.toString()); // "[object Object]"
console.log(obj.hasOwnProperty("x")); // false

// Constructor
console.log(obj.constructor === Object); // true

// Array prototype
var arr = [1, 2, 3];
console.log(arr.toString()); // "1,2,3"
console.log(arr instanceof Array); // true
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-prototype-chain.js
node js/test-prototype-chain.js
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- [ ] *(Pendiente: detallar los pasos concretos de implementación derivados de las secciones anteriores.)*

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

- Compat test match: `bigint-prototype.lou` (FUZZY — prototype)
- Test status: `PASS`

- Disposition: test PASSES — but stays in pendientes/ because match is FUZZY on tokens; verify spec scope matches the test (manual confirmation required before move).

