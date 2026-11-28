# Typed Arrays y ArrayBuffer

## status
✅ COMPLETADO

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

## Quick verify (completado)
```bash
echo 'const b = new ArrayBuffer(8); console.log(b.byteLength);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: 8
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


## Implementación completada (2026-11-27)

### Arquitectura

Se reutiliza `ObjectValue` en lugar de añadir variantes nuevas a `Value`. Cada
buffer y cada vista guarda metadatos en claves internas `@@`:

- `@@type`: `ArrayBuffer`, `SharedArrayBuffer`, `TypedArray` o `DataView`.
- `@@buffer_bytes`: `[]u8` crudo del buffer, registrado en `env.owned_strings`.
- `@@typed_buffer`, `@@typed_offset`, `@@typed_length`, `@@typed_kind`.
- `@@view_buffer`, `@@view_offset`, `@@view_length`.

Los bytes se leen/escriben en little-endian para los Typed Arrays; `DataView`
acepta el flag `littleEndian` en cada get/set. Las vistas comparten el mismo
`ArrayBuffer`, por lo que `subarray`, varias vistas y `SharedArrayBuffer`
reflejan escrituras cruzadas.

### Constructores y métodos

- `ArrayBuffer`, `SharedArrayBuffer`, `DataView`.
- `Int8Array`, `Uint8Array`, `Uint8ClampedArray`, `Int16Array`, `Uint16Array`,
  `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array`,
  `BigInt64Array`, `BigUint64Array`.
- Constructores desde longitud, array, typed array, array-like y
  `(buffer, byteOffset, length)`.
- Estáticos `from`, `of`, `BYTES_PER_ELEMENT`, `ArrayBuffer.isView`.
- Métodos: `set`, `subarray`, `slice`, `fill`, `copyWithin`, `map`, `filter`,
  `reduce`, `reduceRight`, `forEach`, `find`, `findIndex`, `some`, `every`,
  `includes`, `indexOf`, `join`, `reverse`, `sort`, `at`, `keys`, `values`,
  `entries`, `toString` y `@@iterator`.
- DataView: 10 getters `getInt8`..`getBigUint64` y sus 10 setters, con
  endianness configurable.
- Integración con `typeof`, `instanceof`, `in`, `Object.keys`, `for...of`,
  spread, `Array.from`, `String(typedArray)` y el formateo de `console.log`.

### Limitaciones conocidas

- No hay `ArrayBuffer` redimensionable/growable, `transfer`, `detach` ni
  `resize`.
- No hay `Atomics` para `SharedArrayBuffer` (solo memoria compartida entre
  vistas).
- No hay subclases/especies ni cadena de prototipos real para Typed Arrays;
  `instanceof` se resuelve por nombre de constructor.
- `JSON.stringify`, descriptores de propiedades y `Reflect.ownKeys` no enumeran
  los índices de un Typed Array.
- `console.log` formatea Typed Arrays, pero `ArrayBuffer` y `DataView` todavía
  se muestran como `{}`.
- Los Typed Arrays BigInt aceptan el rango `u64`/`i64`; valores fuera de rango
  lanzan en lugar de envolver módulo 2^64.
- Los constructores pueden invocarse sin `new` (JavaScript estricto lanzaría
  TypeError en varios de ellos).

### Verificación

```bash
bash tests/compat/run.sh
zig test src/main.zig
diff <(./zig-out/bin/lou run tests/compat/typed-arrays.lou) \
     <(node tests/compat/typed-arrays.js)
```

Resultados:

- `tests/compat/typed-arrays.lou` idéntico a Node (`diff` vacío).
- `PASS=105 FAIL=0 SKIP=0`.
- `All 1136 tests passed.`

### Cobertura del fixture

- Constructores de los 11 Typed Arrays, `ArrayBuffer`, `SharedArrayBuffer` y
  `DataView`; `typeof`, `instanceof` y `ArrayBuffer.isView`.
- Lecturas/escrituras fuera de rango, wrap entero, `Uint8Clamped`, precisión
  `Float32` y BigInt con signo.
- Vistas compartidas, `slice` copia vs `subarray` comparte, `(buffer, offset,
  length)`, `set`, `fill`, `copyWithin`, `sort`, `reverse` y la familia
  `map`/`filter`/`reduce`/`forEach`/`find`/`some`/`every`.
- DataView big/little endian, `ArrayBuffer.slice`, `Object.keys`, `in`,
  spread, `for...of`, `entries`, `keys`, `values`, `Array.from` y
  `String(typedArray)`.

### Tests unitarios añadidos

- Conversión de enteros con wrap y `Uint8Clamped` con redondeo half-to-even.
- Redondeo a precisión simple de `Float32Array`.
- Buffer compartido entre vistas y `subarray`.
- `slice` copia vs `subarray` comparte.
- DataView big-endian y little-endian.
- `BigInt64Array` conserva valores negativos.

### Archivos tocados

- `src/builtins/typedarray.zig`
- `src/builtins/builtins.zig`
- `src/builtins/builtinObjects.zig`
- `src/builtins/array/from.zig`
- `src/builtins/object/keys.zig`
- `src/builtins/console/format.zig`
- `src/builtins/string/string.zig`
- `src/evaluator.zig`
- `src/vm.zig`
- `tests/compat/typed-arrays.js`
- `tests/compat/typed-arrays.lou`
- `README.md`

## Edge cases y seguimiento

- Promover a spec propio `ArrayBuffer` redimensionable/growable y
  `transfer`/`detach`.
- Promover a spec propio `Atomics` y sincronización real de
  `SharedArrayBuffer`.
- Promover a spec propio la enumeración completa (`JSON.stringify`,
  descriptores, `Reflect.ownKeys`) de Typed Arrays.
- Promover a spec propio el formateo de `ArrayBuffer`/`DataView` en
  `console.log`.

