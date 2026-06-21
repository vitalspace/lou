# Array methods with BigInt (sort, indexOf, includes)

## status
implementado

## Problema
Varios métodos de Array no funcionan correctamente con BigInt:
- `arr.sort()` no ordena BigInts (los deja en orden original)
- `arr.indexOf(2n)` no encuentra BigInts en arrays de BigInts
- `arr.includes(2n)` no detecta BigInts

## Contexto
En JS, los métodos de Array deben manejar BigInt correctamente al compararlos como elementos. `indexOf` usa `SameValueZero` (que considera `1n === 1` como falso pero `1n === 1n` como verdadero). `sort` usa comparación numérica/string.

`find` / `findIndex` / `findLast` / `findLastIndex` ya funcionan con BigInt porque la igualdad se delega al callback del usuario (que usa `===`, manejado por el evaluator).

## Código que falla
```js
const arr = [5n, 1n, 3n, 2n, 4n];
arr.sort();
console.log(arr);    // Esperado: [1n, 2n, 3n, 4n, 5n], Actual: [5n, 1n, 3n, 2n, 4n]

const arr2 = [1n, 2n, 3n];
console.log(arr2.indexOf(2n));   // Esperado: 1, Actual: -1
console.log(arr2.includes(2n));  // Esperado: true, Actual: false
console.log(arr2.indexOf(2));    // Esperado: -1 (tipos diferentes)
```

## Implementacion

### 1. Array sort / toSorted (src/builtins/array/sort.zig, toSorted.zig)
El sort actual convierte todos los elementos a string y compara lexicográficamente (igual que Node.js). El helper `valToString` no tenía caso para `.big_int`, así que devolvía `""` y todos los BigInts comparaban igual — quedándose en el orden original.

Fix: añadir `.big_int => |b| b.value.toString(allocator, 10, .lower)` en `valToString`. Esto serializa el BigInt a sus dígitos decimales sin el sufijo `n` (igual que `String(42n) === "42"`), produciendo la cadena correcta para `std.mem.order`.

### 2. Array indexOf / lastIndexOf / includes (src/builtins/array/*.zig)
Los helpers `valEq` no tenían caso para `.big_int`, así que cualquier comparación entre BigInt y BigInt caía al `else => false`.

Fix: añadir en `valEq`:
```zig
.big_int => |lb| switch (r) {
    .big_int => |rb| lb.compare(rb) == .eq,
    else => false,
},
```
Esto implementa `SameValueZero` para BigInt (comparación numérica, distintos tipos ⇒ `false`).

## Tests

Compat test `tests/compat/bigint-array-methods.{js,lou}`. Cubre:
- `arr.sort()` con BigInts positivos, negativos, cero y grandes (>i64)
- `arr.toSorted()` con BigInts
- `arr.indexOf(2n)` distingue BigInt vs Number
- `arr.lastIndexOf(2n)` con fromIndex
- `arr.includes(2n)` distingue tipo
- BigInts grandes (> i64) — `indexOf`/`lastIndexOf`/`includes` con `2n**100n`
- `find`/`findIndex`/`findLast`/`findLastIndex` con BigInt via `===`
- `arr.sort(callback)` con callback que usa `<`/`>` (BigInt-aware)

Unit tests añadidos en cada archivo:
- `sort.zig`: 3 tests (positivos, negativos+zero, grandes >i64)
- `toSorted.zig`: 1 test (positivos)
- `indexOf.zig`: 4 tests (encuentra BigInt, distingue tipo, no encontrado, zero)
- `lastIndexOf.zig`: 2 tests (encuentra BigInt, no encontrado)
- `includes.zig`: 3 tests (encuentra BigInt, no presente, distingue tipo)

Todos los unit tests pasan (`zig build test`: 897/897). Compat test pasa idéntico al de Node.js.

## Archivos de referencia
- src/builtins/array/sort.zig — `valToString`
- src/builtins/array/toSorted.zig — `valToString`
- src/builtins/array/indexOf.zig — `valEq`
- src/builtins/array/lastIndexOf.zig — `valEq`
- src/builtins/array/includes.zig — `valEq`
- tests/compat/bigint-array-methods.js, .lou

### JS Examples Complejos (validados contra Node.js)
```js
const arr = [5n, 1n, 3n, 2n, 4n];
arr.sort();
console.log(arr);              // [1n, 2n, 3n, 4n, 5n]

const arr2 = [1n, 2n, 3n, 2n];
console.log(arr2.indexOf(2n));     // 1
console.log(arr2.lastIndexOf(2n)); // 3
console.log(arr2.includes(2n));    // true
console.log(arr2.indexOf(2));      // -1 (Number, tipo distinto)

const arr3 = [1, 2, 1n, 2n];
console.log(arr3.indexOf(1));      // 0
console.log(arr3.indexOf(1n));     // 2

// BigInts grandes (> i64)
const huge = 2n ** 100n;
const arr4 = [huge, 1n];
console.log(arr4.indexOf(huge));   // 0
console.log(arr4.includes(huge));  // true

// Negativos y cero
const arr5 = [-5n, 100n, -1n, 0n];
arr5.sort();
console.log(arr5);                 // [-1n, -5n, 0n, 100n] (lexicográfico como Node.js)

// find / findIndex via callback ===
const arr6 = [10n, 20n, 30n];
console.log(arr6.find(x => x === 20n));       // 20n
console.log(arr6.findIndex(x => x === 20n));  // 1
```

### Verificacion
```bash
zig build test                                # 897/897 pasan
./zig-out/bin/lou run tests/compat/bigint-array-methods.lou
node tests/compat/bigint-array-methods.js
bash tests/compat/run.sh
```

Diff esperado: ninguna línea difiere entre `lou` y `node` para el test de compat. `isolate.lou` falla pre-existente, no relacionado.

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/bigint-array-methods.lou 2>&1 | od -c
node tests/compat/bigint-array-methods.js 2>&1 | od -c
```

### pendiente
- [x] Hacer que `sort` ordene BigInts correctamente
- [x] Hacer que `indexOf`/`lastIndexOf`/`includes` reconozcan BigInt
- [x] Verificar que `find`/`findIndex`/`findLast`/`findLastIndex` funcionan con BigInt vía callback
- [x] Tests de compatibilidad
- [x] Tests unitarios

## Edge cases encontrados durante implementación

### 1. Sort con BigInts negativos produce orden lexicográfico (NO numérico)
**Síntoma**: `[-5n, 100n, -1n, 0n].sort()` retorna `[-1n, -5n, 0n, 100n]` (no `[-5n, -1n, 0n, 100n]`).
**Causa**: `Array.prototype.sort` en JS convierte todo a string y compara lexicográficamente. Como `"−1"` < `"−5"` (porque `'1'` < `'5'` en ASCII), ese es el orden que produce.
**Verificación**: Node.js produce el mismo orden.
**Decisión**: aceptar este comportamiento (consistente con Node.js, sin promoción a spec separado).

### 2. `find`/`findIndex`/`findLast`/`findLastIndex` ya funcionan sin cambios
**Síntoma**: El spec original listaba estos métodos como faltantes.
**Verificación**: probados con `arr.find(x => x === 2n)` y similares — ya retornan el resultado correcto porque delegan al callback del usuario, que usa `===` (manejado por el evaluator).
**Decisión**: sin cambios en código. Documentado inline en el spec.

### 3. Unit tests con `toString` requieren `defer allocator.free`
**Síntoma**: las primeras versiones de los tests provocaban memory leaks reportados por `zig build test` (DebugAllocator).
**Causa**: `BigIntValue.value.toString(allocator, 10, .lower)` devuelve una cadena recién alocada que el caller debe liberar.
**Fix**: envolver cada llamada en un bloque con `defer allocator.free(s)`.
**Aplicado en**: tests de `sort.zig` y `toSorted.zig`.
