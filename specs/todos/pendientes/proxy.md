# Proxy

## status
pendiente

## Problema
El objeto `Proxy` no está implementado. No se puede interceptar operaciones en objetos.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `Proxy` es una herramienta de metaprogramación que permite interceptar operaciones fundamentales en objetos.

## Baseline (qué existe ya)
- `NewExpression` YA existe (`src/ast.zig:56`) — `new Proxy(...)` se parsea
- ObjectValue (`src/types/runtime.zig`) — base para proxy target
- MemberAccess y MethodCall (`src/evaluator.zig`) — operaciones a interceptar
- Proxy NO existe como builtin
- Cambio invasivo: TODAS las operaciones de propiedad deben chequear si es proxy

## Quick verify (estado actual)
```bash
echo 'console.log(new Proxy({}, {}));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Proxy is not defined"
```

## Patrones a seguir
- `src/builtins/number/number.zig` — patrón de constructor builtin
- `src/builtins/builtinObjects.zig` — registrar PROXY_OBJECT
- `src/types/runtime.zig` — agregar `Value.proxy` variant con `{ target, handler }`
- `src/evaluator.zig:2213-2239` — `MemberAccess` (interceptar get)
- `src/vm.zig:1148-1188` — `get_prop` (interceptar get)

## Gotchas
- Feature INVASIVA: TODA operación de propiedad debe chequear proxy
- 13 traps posibles: get, set, has, deleteProperty, apply, construct, getPrototypeOf, setPrototypeOf, isExtensible, preventExtensions, ownKeys, defineProperty, getOwnPropertyDescriptor
- IMPLEMENTACIÓN MÍNIMA viable: solo get, set, has traps
- Si no hay trap, pasar-through al target directamente
- Si agregás variant `Value.proxy`, actualizar `freeValue` (`src/environment.zig:15-25`) y todos los switches
- Trap handlers son funciones JS — invocarlas requiere `evaluator.zig` recursion (cuidado con stack overflow)
- `apply` trap: cuando el proxy ES una función y se llama
- `construct` trap: cuando se hace `new Proxy(...)`
- Cross-check con `reflect.md` — `Reflect.get(target, prop)` es la versión sin traps del proxy get
- Invariantes: traps deben retornar valores válidos (e.g., set debe retornar boolean)
- Cambiar TODOS los accesos a propiedad en evaluator Y VM — cambio doble

## Código que falla
```js
const handler = {
    get(target, prop) {
        return prop in target ? target[prop] : "default";
    }
};
const proxy = new Proxy({}, handler);
proxy.name = "Alice";
console.log(proxy.name);    // "Alice"
console.log(proxy.unknown); // "default"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/proxy.zig`:
- Constructor `new Proxy(target, handler)`
- Traps: `get`, `set`, `has`, `deleteProperty`, `apply`, `construct`, `getPrototypeOf`, `setPrototypeOf`, `isExtensible`, `preventExtensions`, `ownKeys`, `defineProperty`, `getOwnPropertyDescriptor`

### 2. VM
- Las operaciones en el proxy deben invocar los traps del handler
- Si no hay trap, pasar-through al target

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
- src/types/runtime.zig — Value union, ObjectValue
- src/vm.zig — get_prop, set_prop (interceptar)

### JS Examples Complejos
```js
// Básico - get/set trap
const handler = {
    get(target, prop) {
        console.log(`Getting ${prop}`);
        return target[prop];
    },
    set(target, prop, value) {
        console.log(`Setting ${prop} = ${value}`);
        target[prop] = value;
        return true;
    }
};
const proxy = new Proxy({}, handler);
proxy.x = 10;    // "Setting x = 10"
console.log(proxy.x); // "Getting x" → 10

// has trap
const handler2 = {
    has(target, prop) {
        return prop.startsWith("_") ? false : prop in target;
    }
};
const obj = new Proxy({ _secret: 42, name: "Alice" }, handler2);
console.log("_secret" in obj); // false
console.log("name" in obj);    // true

// deleteProperty trap
const handler3 = {
    deleteProperty(target, prop) {
        if (prop === "protected") return false;
        delete target[prop];
        return true;
    }
};

// apply trap (funciones)
const sum = new Proxy(function(a, b) { return a + b; }, {
    apply(target, thisArg, args) {
        console.log("Called with", args);
        return target.apply(thisArg, args);
    }
});
console.log(sum(1, 2)); // "Called with [1,2]" → 3

// construct trap (clases)
const handler4 = {
    construct(target, args) {
        console.log("Creating instance with", args);
        return new target(...args);
    }
};

// Validación de propiedades
const schema = { name: "string", age: "number" };
const validated = new Proxy({}, {
    set(target, prop, value) {
        if (prop in schema && typeof value !== schema[prop]) {
            throw new TypeError(`Expected ${schema[prop]} for ${prop}`);
        }
        target[prop] = value;
        return true;
    }
});
validated.name = "Alice"; // ok
// validated.age = "old"; // TypeError
```

### Verificacion
- `new Proxy(target, handler)` intercepta operaciones
- Traps se ejecutan cuando la operación ocurre
- Sin trap, operación pasa al target directamente
- `has`, `get`, `set`, `deleteProperty` funcionan
- `apply` intercepta llamadas a función
- `construct` intercepta `new`

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/proxy.js 2>&1 | od -c
node js/tests/proxy.js 2>&1 | od -c

### pendiente
- Implementar Proxy como builtin con traps
- Modificar VM para interceptar operaciones en proxys

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
