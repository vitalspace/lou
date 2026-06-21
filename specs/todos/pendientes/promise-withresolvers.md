# Promise.withResolvers

## status
pendiente

## Problema
`Promise.withResolvers()` (ES2024) no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `Promise.withResolvers()` es una forma más limpia de crear promesas con acceso externo a resolve/reject.

## Baseline (qué existe ya)
- Promise NO existe todavía — DEPENDE completamente de `async-await.md`
- Una vez Promise exista, este spec es muy simple: agregar método estático
- ES2024 feature

## Quick verify (estado actual)
```bash
echo 'const {promise, resolve} = Promise.withResolvers();' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Promise is not defined"
```

## Patrones a seguir
- `src/builtins/promise.zig` (cuando exista) — agregar `WithResolvers` a métodos estáticos
- `src/builtins/math/math.zig` — patrón de métodos estáticos en BuiltinObject
- `src/builtins/json/json.zig` — patrón alternativo

## Gotchas
- NO implementar este spec hasta que `async-await.md` esté completo
- Implementación: crear 3 cosas y retornar:
  1. Promise (pending)
  2. resolve function (captura la promise y la marca fulfilled)
  3. reject function (captura la promise y la marca rejected)
- Los resolve/reject son clousures que mutan la promise state
- Cross-check con `async-await.md` — el Promise state machine debe soportar transiciones externas
- ES2024 — verificar que target version es compatible
- Es solo UNA función adicional, no requiere grandes cambios
- Edge case: `withResolvers()` llamado múltiples veces debe retornar promises independientes

## Código que falla
```js
const { promise, resolve, reject } = Promise.withResolvers();
setTimeout(() => resolve("done"), 1000);
const result = await promise;
```

## Implementacion sugerida

### 1. Builtin (src/builtins/promise/)
Agregar método estático a Promise:
- `Promise.withResolvers()` — retorna `{ promise, resolve, reject }`

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
- src/builtins/promise.zig (cuando se implemente Promise)

### JS Examples Complejos
```js
// Básico
const { promise, resolve, reject } = Promise.withResolvers();
resolve(42);
console.log(await promise); // 42

// Con timeout
const { promise: p, resolve: r } = Promise.withResolvers();
setTimeout(() => r("hello"), 1000);
console.log(await p); // "hello" (después de 1s)

// Con error
const { promise: p2, reject: rej } = Promise.withResolvers();
rej(new Error("fail"));
try {
    await p2;
} catch (e) {
    console.log(e.message); // "fail"
}

// Event emitter pattern
function createEventStream() {
    const { promise, resolve, reject } = Promise.withResolvers();
    return {
        emit: resolve,
        error: reject,
        [Symbol.asyncIterator]() { /* ... */ }
    };
}

// Queue pattern
function createQueue() {
    const items = [];
    const waiting = [];
    return {
        push(item) {
            if (waiting.length > 0) {
                const { resolve } = waiting.shift();
                resolve(item);
            } else {
                items.push(item);
            }
        },
        async pop() {
            if (items.length > 0) return items.shift();
            const { promise, resolve } = Promise.withResolvers();
            waiting.push({ promise, resolve });
            return promise;
        }
    };
}
```

### Verificacion
- `Promise.withResolvers()` retorna `{ promise, resolve, reject }`
- `resolve(value)` resuelve la promise
- `reject(reason)` rechaza la promise
- `promise` es una Promise válida

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/withresolvers.js 2>&1 | od -c
node js/tests/withresolvers.js 2>&1 | od -c

### pendiente
- Implementar Promise.withResolvers (requiere Promise implementado)

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
