# Array.prototype.some()

**Status: IMPLEMENTED**

## Description

The `some()` method of Array instances returns `true` if at least one element in the array satisfies the provided testing function. If no element satisfies the function, `false` is returned.

## Usage

```js
const array1 = [1, 2, 3, 4, 5];

const even = (element) => element % 2 === 0;

console.log(array1.some(even));
// Expected output: true
```

## Syntax

```
some(callbackFn)
some(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to indicate the element passes the test.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

`true` if the callbackFn returns a truthy value for at least one element. Otherwise, `false`.

## Relevant files

- `src/builtins/array/some.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
