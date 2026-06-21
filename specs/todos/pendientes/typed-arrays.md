# Typed Arrays y ArrayBuffer

## status
pendiente

## Problema
Los Typed Arrays (`Int8Array`, `Uint8Array`, `Float64Array`, etc.) y `ArrayBuffer` no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los Typed Arrays son esenciales para manipulación de datos binarios, WebGL, WebAssembly, y operaciones de alto rendimiento.

## Baseline (qué existe ya)
- `Array` YA implementado (`src/builtins/array/`) — template para métodos
- `NewExpression` YA existe (`src/ast.zig:56`)
- `ArrayObject` YA existe (`src/types/runtime.zig:7`)
- ArrayBuffer NO existe
- Typed Arrays NO existen
- Falta estructura para binary data (no hay `Value.bytes` variant)

## Quick verify (estado actual)
```bash
echo 'const b = new ArrayBuffer(8); console.log(b);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "ArrayBuffer is not defined"
```

## Patrones a seguir
- `src/builtins/array/` — Array implementation, métodos como map/filter
- `src/builtins/builtinObjects.zig` — registrar ARRAYBUFFER_OBJECT y typed arrays
- `src/types/runtime.zig:7` — `ArrayObject` como template para `TypedArrayObject`
- `src/builtins/number/number.zig` — patrón de constructor

## Gotchas
- Feature GRANDE: 11 typed arrays + ArrayBuffer + DataView + ~30 métodos cada uno
- IMPLEMENTACIÓN MÍNIMA viable: ArrayBuffer + 2 typed arrays (Uint8Array, Float64Array)
- Binary data: agregar `Value.typed_array` y `Value.array_buffer` variants, o reusar ArrayObject con metadata
- `set/get` con índices chequean bounds — retornar undefined si fuera de rango
- `set(array, offset)` copia datos
- `subarray(begin, end)` retorna nueva vista (mismo buffer, offset diferente)
- `BYTES_PER_ELEMENT`: Uint8=1, Int16=2, Int32=4, Float32=4, Float64=8, BigInt64=8
- Cross-check con `prototype-chain.md` — Typed Arrays tienen su propio prototype
- Cross-check con `array.md` — métodos compartidos (map, filter, etc.) deben funcionar igual
- Si agregás campos a runtime, actualizar `freeValue` (`src/environment.zig:15-25`)
- Endianness: little-endian por default en JS (matching most CPUs)

## Código que falla
```js
const buffer = new ArrayBuffer(8);
const view = new Int32Array(buffer);
view[0] = 42;
console.log(view[0]); // 42
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Crear `src/builtins/typedarray.zig`:
- `ArrayBuffer(byteLength)` — bloque de memoria
- `SharedArrayBuffer(byteLength)` — bloque compartido
- `DataView(buffer, byteOffset?, length?)` — vista flexible
- Typed Arrays: `Int8Array`, `Uint8Array`, `Uint8ClampedArray`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array`, `BigInt64Array`, `BigUint64Array`

### 2. Métodos
Herencia de Array-like: `length`, `[]`, `set()`, `subarray()`, `slice()`, `fill()`, `forEach()`, `map()`, `filter()`, `reduce()`, `find()`, `findIndex()`, `includes()`, `indexOf()`, `join()`, `reverse()`, `sort()`, `some()`, `every()`, `copyWithin()`, `entries()`, `keys()`, `values()`

Estáticos: `TypedArray.from()`, `TypedArray.of()`, `TypedArray.BYTES_PER_ELEMENT`

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
- src/builtins/array/ — implementación de Array (referencia para métodos)
- src/builtins/builtins.zig — registro de constructores
- src/types/runtime.zig — Value union

### JS Examples Complejos
```js
// ArrayBuffer
const buffer = new ArrayBuffer(16);
console.log(buffer.byteLength); // 16

// Typed Array directo
const arr = new Uint8Array([1, 2, 3, 4]);
console.log(arr.length); // 4
console.log(arr[0]);     // 1

// DataView (flexible)
const view = new DataView(buffer);
view.setInt32(0, 42);
view.setFloat64(4, 3.14);
console.log(view.getInt32(0));    // 42
console.log(view.getFloat64(4));  // 3.14

// Typed Array sobre ArrayBuffer
const buf = new ArrayBuffer(8);
const floats = new Float64Array(buf);
floats[0] = Math.PI;
const bytes = new Uint8Array(buf);
console.log(bytes.length); // 8

// Métodos de Array
const f32 = new Float32Array([1.1, 2.2, 3.3]);
console.log(f32.map(x => x * 2));
console.log(f32.filter(x => x > 2));
console.log(f32.reduce((a, b) => a + b, 0));

// set() - copiar datos
const dest = new Uint8Array(8);
dest.set([1, 2, 3], 2); // copiar en offset 2
console.log(dest); // [0, 0, 1, 2, 3, 0, 0, 0]

// subarray()
const sub = f32.subarray(1, 3);
console.log(sub); // [2.2, 3.3]

// BYTES_PER_ELEMENT
console.log(Int32Array.BYTES_PER_ELEMENT); // 4
console.log(Float64Array.BYTES_PER_ELEMENT); // 8
```

### Verificacion
- `new ArrayBuffer(n)` crea buffer de n bytes
- Typed Arrays acceden datos en su formato correcto
- Múltiples vistas sobre el mismo buffer comparten datos
- Métodos de Array funcionan en Typed Arrays
- `set()` copia datos con offset
- `subarray()` crea vista parcial

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/typed-arrays.js 2>&1 | od -c
node js/tests/typed-arrays.js 2>&1 | od -c

### pendiente
- Implementar ArrayBuffer, DataView, y todos los Typed Arrays

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
