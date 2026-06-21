# Array.prototype.findIndex()

**Status: IMPLEMENTED**

## Description

The `findIndex()` method of Array instances returns the index of the first element in the array that satisfies the provided testing function. If no element satisfies the function, `-1` is returned.

## Usage

```js
const array1 = [5, 12, 8, 130, 44];

const isLargeNumber = (element) => element > 13;

console.log(array1.findIndex(isLargeNumber));
// Expected output: 3
```

## Syntax

```
findIndex(callbackFn)
findIndex(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to indicate the element passes the test, and a falsy value otherwise.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

The index of the first element that passes the test. If no element is found, `-1`.

## Relevant files

- `src/builtins/array/findIndex.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
