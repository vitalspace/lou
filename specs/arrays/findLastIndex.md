# Array.prototype.findLastIndex()

**Status: IMPLEMENTED**

## Description

The `findLastIndex()` method of Array instances returns the index of the last element in the array that satisfies the provided testing function. If no element satisfies the function, `-1` is returned.

## Usage

```js
const array1 = [5, 12, 50, 130, 44];

const isLargeNumber = (element) => element > 45;

console.log(array1.findLastIndex(isLargeNumber));
// Expected output: 3
```

## Syntax

```
findLastIndex(callbackFn)
findLastIndex(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to indicate a matching element.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

The index of the last element that passes the test. If no element is found, `-1`.

## Relevant files

- `src/builtins/array/findLastIndex.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
