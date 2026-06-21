# Array.prototype.every()

**Status: IMPLEMENTED**

## Description

The `every()` method of Array instances returns false if it finds an element in the array that does not satisfy the provided testing function. Otherwise, it returns true.

## Usage

```js
const isBelowThreshold = (currentValue) => currentValue < 40;

const array1 = [1, 30, 39, 29, 10, 13];

console.log(array1.every(isBelowThreshold));
// Expected output: true
```

## Syntax

```
every(callbackFn)
every(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to indicate the element passes the test, and a falsy value otherwise.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

`true` unless `callbackFn` returns a falsy value for an array element, in which case `false` is immediately returned.

## Relevant files

- `src/builtins/array/every.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
