# Async Generators y for-await-of

## status
pendiente

## Problema
Los generadores asíncronos (`async function*`) y `for await...of` no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los generadores asíncronos permiten iterar sobre datos asíncronos de forma lazy.

## Baseline (qué existe ya)
- `GeneratorDeclaration` AST YA existe (`src/ast.zig:52`)
- `YieldExpression` YA existe (`src/ast.zig:53`)
- `GeneratorObject` YA existe (`src/types/runtime.zig:12`)
- Evaluator maneja generators (`src/evaluator.zig:2915+` — `evaluateGeneratorNext`)
- Faltan: `async` keyword (no existe), `Promise` (no existe), `Symbol.asyncIterator`
- DEPENDE de: `async-await.md` (Promise) y `iterator-protocol.md` (Symbol.asyncIterator)

## Quick verify (estado actual)
```bash
echo 'async function* g() { yield 1; }' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (async no es keyword, function* sin async también falla)
```

## Patrones a seguir
- `src/ast.zig:52` — `GeneratorDeclaration` como template (agregar `async: bool` flag)
- `src/types/runtime.zig:12` — `GeneratorObject` (agregar `is_async: bool`)
- `src/evaluator.zig:2915+` — generator evaluation
- `src/builtins/symbol.zig` — agregar `WellKnownSymbol.asyncIterator`
- `async-await.md` spec — necesario primero

## Gotchas
- DEPENDE de `async-await.md` — implementar Promise primero
- `async function*` = generator + Promise wrapper
- `.next()` retorna Promise<{value, done}> — vs generator normal que retorna {value, done}
- `for await...of`: llamar `.next()` y await el resultado
- Yield dentro de async generator produce un valor asíncrono
- Cross-check con `for-of` y `for-in-order.md` — similar iteration mechanism
- Symbol.asyncIterator: mismo pattern que Symbol.iterator pero async
- `yield*` dentro de async generator delega a otro iterable (sync o async)
- Si agregás AST fields, actualizar todos los lugares de freeAst, printAst, evaluator

## Código que falla
```js
async function* asyncRange(start, end) {
    for (let i = start; i <= end; i++) {
        await new Promise(resolve => setTimeout(resolve, 100));
        yield i;
    }
}

for await (const n of asyncRange(1, 5)) {
    console.log(n); // 1, 2, 3, 4, 5 (con delay)
}
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
`async` y `function*` ya existen. Necesitan combinarse.

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `AsyncGeneratorDeclaration` — `async function* name() {}`
- `ForAwaitOfLoop` — `for await (const x of iter) {}`

### 3. Builtin (src/builtins/)
- `AsyncGenerator` — objeto con `.next()`, `.return()`, `.throw()`
- `AsyncGenerator.prototype.next()` retorna `Promise<{ value, done }>`
- `AsyncIterator` protocol con `Symbol.asyncIterator`

### 4. VM (src/vm.zig)
- Opcode `for_await_of` — iterar async iterable
- Async generator: pausar/resumir con await

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
- src/ast.zig — GeneratorDeclaration, ForOfLoop
- src/vm.zig — get_iterator, iterator_next
- src/builtins/ — generators existentes

### JS Examples Complejos
```js
// Async generator básico
async function* fetchData() {
    const pages = ["/api/page1", "/api/page2", "/api/page3"];
    for (const url of pages) {
        const response = await fetch(url);
        yield await response.json();
    }
}

// for await...of
for await (const data of fetchData()) {
    console.log(data);
}

// Async generator con return
async function* range(start, end) {
    for (let i = start; i <= end; i++) {
        yield i;
    }
    return "done";
}

// Async generator con throw
async function* risky() {
    try {
        yield await dangerousOperation();
    } catch (e) {
        yield "fallback";
    }
}

// Async iteration manual
const gen = range(1, 3);
console.log(await gen.next()); // { value: 1, done: false }
console.log(await gen.next()); // { value: 2, done: false }
console.log(await gen.next()); // { value: 3, done: false }
console.log(await gen.next()); // { value: "done", done: true }

// Async iterable object
const asyncIterable = {
    [Symbol.asyncIterator]() {
        let i = 0;
        return {
            async next() {
                if (i < 3) return { value: i++, done: false };
                return { done: true };
            }
        };
    }
};
for await (const x of asyncIterable) {
    console.log(x); // 0, 1, 2
}

// Composición de async generators
async function* concat(...iterables) {
    for await (const iterable of iterables) {
        yield* iterable;
    }
}
```

### Verificacion
- `async function*` crea un generador asíncrono
- `yield` dentro de async generator funciona
- `await` dentro de async generator funciona
- `for await...of` itera sobre async iterables
- `.next()` retorna Promise de `{ value, done }`
- `Symbol.asyncIterator` funciona

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/async-generators.js 2>&1 | od -c
node js/tests/async-generators.js 2>&1 | od -c

### pendiente
- Implementar AsyncGenerator, AsyncIterator, for-await-of
- Requiere async/await y generators implementados

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
