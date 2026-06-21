# BigInt as array index

## status
implementado

## Problema
`arr[1n]` no funciona para arrays en Lou, solo para `js_object`. En Node.js, `arr[1n]` retorna el mismo valor que `arr[1]` (BigInt se convierte a índice numérico).

## Contexto
BigInt puede usarse como índice de array. Internamente, `1n` se convierte a número `1` para acceder al elemento. BigInts que no caben en `i64`, son negativos, o quedan fuera del rango del array devuelven `undefined` (mismo comportamiento que Node.js).

## Código que falla
```js
const arr = [10, 20, 30];
console.log(arr[1n]);   // Esperado: 20, Actual: error InvalidIndex
arr[1n] = 100;          // Asignación también falla
console.log(arr[1]);    // Esperado: 100
```

## Implementacion

### 1. VM (src/vm.zig)
Actualizado el opcode `index_get` para manejar `.big_int` en el caso `arr == .array`. Se añadió el helper `bigIntIndex(b)` que convierte un `*BigIntValue` a `?usize`:

```zig
fn bigIntIndex(b: *ast.BigIntValue) ?usize {
    if (b.value.toConst().toInt(i64)) |i| {
        if (i >= 0) return @intCast(i);
        return null;
    } else |_| return null;
}
```

En `index_get`, la rama `arr == .array` ahora distingue BigInt de integer/float:
- BigInt fuera de rango, negativo, o índice fuera del array → push `void` (undefined), como en Node.js.
- Integer/float mantienen el comportamiento previo (`error.IndexOutOfBounds`).

### 2. set_index (src/vm.zig)
`set_index` solo manejaba `js_object`. Se añadió una rama `obj == .array` que acepta integer / float / big_int como índice (los dos primeros no-negativos, el último pasando por `bigIntIndex`). Índices inválidos (negativos, BigInt fuera de i64, etc.) se ignoran y dejan `void` en la pila.

Bonus: como `set_index` ahora soporta arrays, `arr[1] = 99` (que antes fallaba silenciosamente) también funciona.

## Tests

`tests/compat/bigint-array-index.js` y `tests/compat/bigint-array-index.lou` — pasan idénticos al ejecutar `./zig-out/bin/lou run` y `node`.

Cubre:
- `arr[0n]`, `arr[1n]`, `arr[3n]` (lectura con índice BigInt)
- `arr[1n] = 200` y verificación con índice numérico (`arr[1]`)
- `arr2[0n] = 100n` (asignación de BigInt a posición BigInt)
- Round-trip: `arr[1n] === arr[1]` antes y después de `arr[1n] = 200`
- `arr[2n ** 100n]` → `undefined` (BigInt fuera de i64)
- `arr[-1n]` → `undefined` (BigInt negativo)
- `arr[100n]` → `undefined` (BigInt en rango pero fuera del array)
- `b[5n] = 99` extiende el array con `holes` y `b.length === 6`

## Archivos de referencia
- src/vm.zig:1524 — `index_get` op
- src/vm.zig:1684 — `set_index` op (nueva rama para arrays)
- src/vm.zig:2173 — helper `bigIntIndex`

### JS Examples Complejos (validados contra Node.js)
```js
const arr = [10, 20, 30];
console.log(arr[1n]);      // 20
arr[1n] = 200;
console.log(arr[1]);       // 200
console.log(arr[1n]);      // 200

// BigInt large
const huge = 2n ** 100n;
console.log(arr[huge]);    // undefined (out of bounds)
```

### pendiente
- [x] Implementar BigInt como índice de array en `index_get`
- [x] Implementar BigInt como índice de array en `set_index`
- [x] Test de compatibilidad
