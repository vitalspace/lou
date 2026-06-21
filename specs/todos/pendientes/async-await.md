# Async/Await y Promise

## status
pendiente

## Problema
No existe soporte para `async`/`await`, la palabra clave `async` en funciones, ni el objeto `Promise`.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `async`/`await` y `Promise` son fundamentales para programación asíncrona en JS moderno. Actualmente no hay soporte asíncrono.

## Baseline (qué existe ya)
- Generator YA implementado: `GeneratorDeclaration` AST (`src/ast.zig:52`), `YieldExpression` (`src/ast.zig:53`), `GeneratorObject` (`src/types/runtime.zig:12`)
- Microtask-like: NO hay event loop
- Lexer NO tiene keywords `Async`/`Await`
- NO existe `Promise` constructor
- `setTimeout` y similares NO están implementados (verificar si existe alguna forma de timer)

## Quick verify (estado actual)
```bash
echo 'async function f() { return 1; } f().then(console.log);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (async no es keyword)
```

## Patrones a seguir
- `src/ast.zig:52-53` — `GeneratorDeclaration`, `YieldExpression` como referencia para async generators
- `src/types/runtime.zig:12` — `GeneratorObject`
- `src/evaluator.zig:2915` — `evaluateGeneratorNext` como referencia
- `src/builtins/builtinObjects.zig` — para registrar Promise
- `src/environment.zig:45-50` — generators list (puede reusarse para promises)

## Gotchas
- Feature MAYOR: requiere event loop con microtask queue
- Promise states: pending, fulfilled, rejected
- `await expr` envuelve expr en promise y suspende hasta resolución
- `async function` retorna Promise que se resuelve con el return value (o rechaza con throw)
- Microtasks: `.then()` callbacks deben ejecutarse ANTES del próximo macrotask
- Implementación mínima viable (sin event loop completo): ejecutar todo secuencialmente y resolver promises inmediatamente
- Cross-check con `async-generators.md` — async generators requieren Promise + generators
- Cross-check con `promise-withresolvers.md` — método estático de Promise
- Si añades AST nodes (`AsyncFunctionDeclaration`, `AwaitExpression`), actualizar freeAst, printAst, evaluator switch
- Si agregás Value variant `Promise`, agregar a environment cleanup (`env.promises`)
- `try/catch` dentro de async function debe rechazar la promise, no throw

## Código que falla
```js
async function fetchData() {
    const result = await someAsyncOperation();
    return result;
}

const p = new Promise((resolve, reject) => {
    resolve(42);
});
p.then(val => console.log(val));
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keyword: `Async`, `Await`

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `AsyncFunctionDeclaration` — `async function name() {}`
- `AsyncArrowFunction` — `async () => {}`
- `AwaitExpression` — `await expr`
- `PromiseExpression` — `new Promise(...)`

### 3. Builtin (src/builtins/)
Crear `src/builtins/promise.zig`:
- `Promise` constructor con `resolve`/`reject`
- `Promise.prototype.then(onFulfilled, onRejected)`
- `Promise.prototype.catch(onRejected)`
- `Promise.prototype.finally(onFinally)`
- `Promise.all(iterable)`
- `Promise.allSettled(iterable)`
- `Promise.race(iterable)`
- `Promise.any(iterable)`
- `Promise.resolve(value)`
- `Promise.reject(reason)`

### 4. VM (src/vm.zig)
- Opcode `await_` — suspender ejecución hasta que la promise se resuelva
- Microtask queue para procesar `.then()` callbacks
- Soporte para async/await en el loop de eventos

### 5. Evaluator (src/evaluator.zig)
- `evaluateAsyncFunction()` — crear función que retorna Promise
- `evaluateAwait()` — pausar ejecución y reanudar al resolverse

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
- src/builtins/builtins.zig — registro de constructores
- src/builtins/builtinObjects.zig — objetos builtin
- src/vm.zig — loop de ejecución
- src/types/runtime.zig — Value union

### JS Examples Complejos
```js
// Promise básica
const p = new Promise((resolve, reject) => {
    setTimeout(() => resolve("done"), 100);
});
p.then(console.log);

// Async/Await
async function getUser(id) {
    const user = await fetchUser(id);
    return user;
}

// Promise.all
const results = await Promise.all([
    fetch("/api/a"),
    fetch("/api/b"),
    fetch("/api/c"),
]);

// Promise.race
const fastest = await Promise.race([
    fetch("/api/fast"),
    fetch("/api/slow"),
]);

// Error handling
async function safeOperation() {
    try {
        const result = await riskyOperation();
        return result;
    } catch (e) {
        return "fallback";
    }
}

// Promise chaining
fetchUser(1)
    .then(user => fetchPosts(user.id))
    .then(posts => console.log(posts))
    .catch(err => console.error(err))
    .finally(() => console.log("done"));

// Promise.allSettled
const outcomes = await Promise.allSettled([
    Promise.resolve(1),
    Promise.reject("error"),
    Promise.resolve(3),
]);
// [{status:"fulfilled",value:1}, {status:"rejected",reason:"error"}, ...]
```

### Verificacion
- `new Promise((resolve, reject) => {...})` crea una promise
- `.then()` se ejecuta al resolverse
- `.catch()` captura rechazos
- `async function` retorna automáticamente una Promise
- `await` pausa hasta resolución
- `Promise.all()` espera todas
- `Promise.race()` retorna la primera

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/async-await.js 2>&1 | od -c
node js/tests/async-await.js 2>&1 | od -c

### pendiente
- Implementar Promise como builtin
- Implementar async/await en lexer, AST, parser, VM
- Implementar microtask queue

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
