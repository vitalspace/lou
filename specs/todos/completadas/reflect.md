# Reflect

## status

**completada** — `Reflect` registrado como `BuiltinObjectImpl` con 13 métodos: `get`, `set`, `has`, `deleteProperty`, `ownKeys`, `apply`, `construct`, `defineProperty`, `getOwnPropertyDescriptor`, `getPrototypeOf`, `setPrototypeOf`, `isExtensible`, `preventExtensions`. Los targets no-objeto lanzan el `TypeError` de ECMAScript (`Reflect.<m> called on non-object`). `apply`/`construct` delegan en `callFunctionValue`; `get` recorre la cadena de prototipos e invoca getters. Limitaciones documentadas: sin traps de Proxy (Reflect es la operación base), flags de descriptor por defecto `true` (no se persisten), claves símbolo no soportadas y arrays soportados en get/set/has/delete/ownKeys. Fixture `tests/compat/reflect.lou` PASS y 3 unit tests. Baseline 95 PASS / 0 FAIL / 0 SKIP, 2026-11-27.
## Problema
El objeto `Reflect` no está implementado. No hay acceso a las operaciones fundamentales del lenguaje como funciones.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `Reflect` proporciona métodos para interceptar y realizar operaciones que corresponden a los traps de Proxy.

## Baseline (qué existe ya)
- Property access functions ya existen en evaluator y VM
- ObjectValue tiene HashMap de propiedades (`src/types/runtime.zig`)
- Reflect NO existe
- Múltiples features relacionadas pendientes: `proxy.md`, `in-operator.md`, `delete-operator.md`, `prototype-chain.md`

## Quick verify (estado actual)
```bash
echo 'console.log(Reflect.get({a:1}, "a"));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Reflect is not defined"
```

## Patrones a seguir
- `src/builtins/builtinObjects.zig` — agregar REFLECT_OBJECT
- `src/builtins/math/math.zig` — patrón de BuiltinObject con methods
- `src/evaluator.zig:2213-2239` — `MemberAccess` (para `Reflect.get`)
- `src/evaluator.zig` — buscar `FunctionCall` (para `Reflect.apply`)
- `src/evaluator.zig` — buscar `NewExpression` (para `Reflect.construct`)

## Gotchas
- 13 métodos estáticos que mapean a traps de Proxy
- IMPLEMENTACIÓN MÍNIMA viable: get, set, has, deleteProperty
- Cada método Reflect.X(target, ...) hace la operación base (sin trap)
- Cross-check con `proxy.md` — `Reflect.X` es lo que el trap handler llama por default
- Cross-check con `in-operator.md` — `Reflect.has(obj, "x")` es lo mismo que `"x" in obj`
- Cross-check con `delete-operator.md` — `Reflect.deleteProperty(obj, "x")` es lo mismo que `delete obj.x`
- Retornan booleanos para éxito/fallo (vs tirar error)
- `Reflect.construct(target, args)`: llamar a target como constructor
- `Reflect.apply(target, this, args)`: llamar a target como función
- Misma lógica que el spec de Proxy, pero sin traps — se puede compartir código internamente

## Código que falla
```js
const obj = { a: 1 };
console.log(Reflect.get(obj, "a"));     // 1
Reflect.set(obj, "b", 2);
console.log(obj.b);                      // 2
console.log(Reflect.has(obj, "a"));      // true
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/reflect.zig`:
- `Reflect.get(target, property, receiver?)`
- `Reflect.set(target, property, value, receiver?)`
- `Reflect.has(target, property)`
- `Reflect.deleteProperty(target, property)`
- `Reflect.construct(target, args, newTarget?)`
- `Reflect.apply(target, thisArgument, argumentsList)`
- `Reflect.defineProperty(target, property, descriptor)`
- `Reflect.getOwnPropertyDescriptor(target, property)`
- `Reflect.getPrototypeOf(target)`
- `Reflect.setPrototypeOf(target, prototype)`
- `Reflect.isExtensible(target)`
- `Reflect.preventExtensions(target)`
- `Reflect.ownKeys(target)`

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
- src/builtins/builtinObjects.zig — registro de objetos
- src/vm.zig — operaciones fundamentales (get_prop, set_prop, etc.)

### JS Examples Complejos
```js
// get/set
const obj = { x: 1 };
console.log(Reflect.get(obj, "x"));       // 1
Reflect.set(obj, "y", 2);
console.log(obj.y);                        // 2

// has
console.log(Reflect.has(obj, "x"));        // true
console.log(Reflect.has(obj, "z"));        // false

// deleteProperty
Reflect.deleteProperty(obj, "x");
console.log(Reflect.has(obj, "x"));        // false

// construct
function Person(name) { this.name = name; }
const p = Reflect.construct(Person, ["Alice"]);
console.log(p.name); // "Alice"

// apply
function sum(a, b) { return a + b; }
console.log(Reflect.apply(sum, null, [1, 2])); // 3

// ownKeys
const obj2 = { a: 1, [Symbol()]: 2 };
console.log(Reflect.ownKeys(obj2)); // ["a", Symbol()]

// getPrototypeOf
console.log(Reflect.getPrototypeOf([]) === Array.prototype); // true

// defineProperty
const obj3 = {};
Reflect.defineProperty(obj3, "x", {
    value: 42,
    writable: false,
    enumerable: true,
});
console.log(obj3.x); // 42

// isExtensible
console.log(Reflect.isExtensible({}));        // true
console.log(Reflect.isExtensible(Object.freeze({}))); // false

// Uso con Proxy
const handler = {
    get(target, prop, receiver) {
        console.log("intercepted:", prop);
        return Reflect.get(target, prop, receiver);
    }
};
const proxy = new Proxy({ a: 1 }, handler);
console.log(proxy.a); // "intercepted: a" → 1
```

### Verificacion
- Cada método Reflect corresponde a una operación del lenguaje
- `Reflect.get`/`set` funcionan como acceso a propiedades
- `Reflect.has` equivale al operador `in`
- `Reflect.construct` equivale a `new`
- `Reflect.apply` equivale a llamada de función
- Métodos son útiles como passthrough en traps de Proxy

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/reflect.js 2>&1 | od -c
node js/tests/reflect.js 2>&1 | od -c
