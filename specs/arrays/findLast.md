# Array.prototype.findLast()

**Status: IMPLEMENTED**

## Description

The `findLast()` method of Array instances returns the last element in the array that satisfies the provided testing function. If no element satisfies the function, `undefined` is returned.

## Usage

```js
const array1 = [5, 12, 50, 130, 44];

const found = array1.findLast((element) => element > 45);

console.log(found);
// Expected output: 130
```

## Syntax

```
findLast(callbackFn)
findLast(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to indicate a matching element has been found.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

The last element that satisfies the testing function. Otherwise, `undefined`.

## Relevant files

- `src/builtins/array/findLast.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
