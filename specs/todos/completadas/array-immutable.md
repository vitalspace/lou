# Array Immutable Methods (toReversed, toSorted, toSpliced)

## status
implementado

## Problema
Los métodos inmutables de Array (`toReversed`, `toSorted`, `toSpliced`) de ES2023 no están implementados.

## Contexto
Lou es un intérprete JavaScript escrito en Zig. ES2023 agregó versiones inmutables de `reverse`, `sort`, `splice` que retornan un nuevo array.

## Código que falla
```js
const arr = [3, 1, 2];
const sorted = arr.toSorted();
console.log(sorted); // [1, 2, 3]
console.log(arr);    // [3, 1, 2] (no modificado)
```

## Implementacion sugerida

### 1. Builtin (src/builtins/array/)
Agregar métodos a `ARRAY_OBJECT`:
- `toReversed()` — retorna copia invertida
- `toSorted(compareFn?)` — retorna copia ordenada
- `toSpliced(start, deleteCount, ...items)` — retorna copia con splice

## Archivos de referencia
- src/builtins/array/ — implementación actual de reverse, sort, splice

### JS Examples Complejos
```js
// toReversed
const arr = [1, 2, 3, 4, 5];
const reversed = arr.toReversed();
console.log(reversed); // [5, 4, 3, 2, 1]
console.log(arr);      // [1, 2, 3, 4, 5] (original intacto)

// toSorted
const nums = [3, 1, 4, 1, 5, 9];
const sorted = nums.toSorted();
console.log(sorted); // [1, 1, 3, 4, 5, 9]
console.log(nums);   // [3, 1, 4, 1, 5, 9] (original intacto)

// toSorted con comparator
const strings = ["banana", "apple", "cherry"];
const alphaSorted = strings.toSorted((a, b) => a.localeCompare(b));
console.log(alphaSorted); // ["apple", "banana", "cherry"]

// toSpliced
const items = ["a", "b", "c", "d", "e"];
const spliced = items.toSpliced(1, 2, "x", "y");
console.log(spliced); // ["a", "x", "y", "d", "e"]
console.log(items);   // ["a", "b", "c", "d", "e"] (original intacto)

// toSpliced solo eliminación
const removed = items.toSpliced(2, 1);
console.log(removed); // ["a", "b", "d", "e"]

// toSpliced solo inserción
const inserted = items.toSpliced(2, 0, "NEW");
console.log(inserted); // ["a", "b", "NEW", "c", "d", "e"]

// Encadenamiento immutabe
const data = [5, 3, 1, 4, 2];
const result = data
    .toSorted()
    .toReversed()
    .map(x => x * 2);
console.log(result); // [10, 8, 6, 4, 2]
console.log(data);   // [5, 3, 1, 4, 2] (original intacto)
```

### Verificacion
- `toReversed()` retorna nuevo array invertido, no modifica original
- `toSorted()` retorna nuevo array ordenado, no modifica original
- `toSpliced()` retorna nuevo array con splice, no modifica original
- Aceptan los mismos argumentos que sus contrapartes mutables
- Se pueden encadenar con otros métodos de Array

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/array-immutable.js 2>&1 | od -c
node js/tests/array-immutable.js 2>&1 | od -c

### pendiente
- Implementar toReversed, toSorted, toSpliced en src/builtins/array/
