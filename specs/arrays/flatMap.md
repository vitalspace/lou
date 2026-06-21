# Array.prototype.flatMap()

**Status: IMPLEMENTED**

## Description

The `flatMap()` method of Array instances is identical to `map()` followed by `flat(1)`, but more efficient by performing both steps in a single iteration.

## Usage

```js
const arr1 = [1, 2, 3, 4];

console.log(arr1.flatMap((x) => [x, x * 2]));
// Expected output: Array [1, 2, 2, 4, 3, 6, 4, 8]
```

## Syntax

```
flatMap(callbackFn)
flatMap(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return an array or a value to be included in the new array.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

A new array with the results of `callbackFn` flattened by one level.

## Relevant files

- `src/builtins/array/flatMap.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
