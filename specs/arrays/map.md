# Array.prototype.map()

**Status: IMPLEMENTED**

## Description

The `map()` method of Array instances creates a new array populated with the results of calling a provided function on every element in the calling array.

## Usage

```js
const array1 = [1, 4, 9, 16];

const map1 = array1.map((x) => x * 2);

console.log(map1);
// Expected output: Array [2, 8, 18, 32]
```

## Syntax

```
map(callbackFn)
map(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array, taking three arguments: `element`, `index` (optional), and `array` (optional).
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

A new array with each element being the result of calling `callbackFn`.

## Relevant files

- `src/builtins/array/map.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
