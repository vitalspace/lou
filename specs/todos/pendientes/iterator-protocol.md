# Iterator Protocol

## status
pendiente

## Problema
El protocolo de iteración formal (Symbol.iterator, métodos de Iterator) no está completamente implementado. Los generadores usan iterators pero no hay soporte general.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. El protocolo de iteración es la base de `for...of`, spread, destructuring, y más.

## Baseline (qué existe ya)
- `Symbol.iterator` YA está implementado (`src/builtins/symbol.zig`)
- `ForOfLoop` existe en AST (`src/ast.zig:39`)
- Evaluator maneja `ForOfLoop` y array iteration (`src/evaluator.zig`)
- `ArrayIterator` existe en runtime (`src/types/runtime.zig:8`)
- `Value.iterator` variant existe
- Faltan: `Iterator` como objeto builtin con helper methods, `Iterator.from()`

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
const obj = {
    [Symbol.iterator]() {
        let i = 0;
        return { next() { return i < 3 ? {value: i++, done: false} : {done: true}; }};
    }
};
for (const x of obj) console.log(x);
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error o comportamiento incorrecto
```

## Patrones a seguir
- `src/builtins/symbol.zig` — WellKnownSymbol con `iterator`
- `src/types/runtime.zig` — `Value.iterator`, `ArrayIterator`
- `src/ast.zig:39` — `ForOfLoop`
- `src/evaluator.zig` — buscar `ForOfLoop =>`
- `src/builtins/array/` — cómo Array implementa iteration
- `src/builtins/math/math.zig` — patrón de BuiltinObject

## Gotchas
- ES2025 Iterator helpers son NUEVOS — la mayoría de runtimes no los tienen aún
- Lazy evaluation: `map()`/`filter()` deben retornar Iterator, no Array
- `Iterator.from(obj)` acepta cualquier iterable (incluso array)
- Helper methods chainables: `.map().filter().take().toArray()`
- `next()` retorna `{value, done}` — `done: true` cuando no hay más valores
- Cross-check con `for-of`: el loop llama `iter.next()` hasta `done: true`
- Builtin objects deben tener `Symbol.iterator` en su prototype
- Symbols (`@@iterator`, `@@asyncIterator`) — usar `WellKnownSymbol.iterator`
- Si agregás `Iterator` como BuiltinObject, registrar en `builtinObjects.zig`

## Código que falla
```js
const iterable = {
    [Symbol.iterator]() {
        let i = 0;
        return {
            next() {
                return i < 3
                    ? { value: i++, done: false }
                    : { done: true };
            }
        };
    }
};
for (const x of iterable) console.log(x);
```

## Implementacion sugerida

### 1. Builtins
- Crear `Iterator` como objeto con métodos de prototipo
- `Iterator.prototype.map()`, `.filter()`, `.take()`, `.drop()`, `.flatMap()`, `.reduce()`, `.toArray()`, `.forEach()`, `.some()`, `.every()`, `.find()`
- `Iterator.from(iterable)` — crear iterator desde iterable

### 2. Protocolo
- Asegurar que `Symbol.iterator` funciona en todos los builtins (Array, String, Map, Set)
- Objetos con `[Symbol.iterator]()` deben funcionar con `for...of`, spread, destructuring

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
- src/builtins/symbol.zig — Symbol.iterator ya implementado
- src/vm.zig — get_iterator, iterator_next opcodes
- src/evaluator.zig — ForOfLoop

### JS Examples Complejos
```js
// Custom iterable
const range = {
    from: 1,
    to: 5,
    [Symbol.iterator]() {
        let current = this.from;
        const last = this.to;
        return {
            next() {
                return current <= last
                    ? { value: current++, done: false }
                    : { done: true };
            }
        };
    }
};
console.log([...range]); // [1, 2, 3, 4, 5]

// Iterator helper methods (ES2025)
function* naturals() {
    let n = 0;
    while (true) yield n++;
}
const evens = naturals()
    .filter(n => n % 2 === 0)
    .take(5);
console.log([...evens]); // [0, 2, 4, 6, 8]

// Iterator.from
const iter = Iterator.from([1, 2, 3]);
console.log(iter.toArray()); // [1, 2, 3]

// Lazy evaluation
const result = Iterator.from([1, 2, 3, 4, 5])
    .map(x => x * x)
    .filter(x => x > 10)
    .toArray();
console.log(result); // [16, 25]

// String iterable
for (const char of "hello") {
    console.log(char); // h, e, l, l, o
}

// Map iterable
const map = new Map([["a", 1], ["b", 2]]);
for (const [key, val] of map) {
    console.log(key, val);
}
```

### Verificacion
- Objetos con `Symbol.iterator` funcionan con `for...of`
- Spread operator funciona con iterables
- Destructuring funciona con iterables
- `Iterator.prototype` tiene métodos helper
- `Iterator.from()` crea iterators desde iterables

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/iterator.js 2>&1 | od -c
node js/tests/iterator.js 2>&1 | od -c

### pendiente
- Implementar Iterator como builtin con métodos helper
- Asegurar protocolo de iteración en todos los builtins

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
