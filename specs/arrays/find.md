# Array.prototype.find()

**Status: IMPLEMENTED**

## Description

The `find()` method of Array instances returns the first element in the provided array that satisfies the provided testing function. If no values satisfy the testing function, `undefined` is returned.

## Usage

```js
const array = [5, 12, 8, 130, 44];

const found = array.find((element) => element > 10);

console.log(found);
// Expected output: 12
```

## Syntax

```
find(callbackFn)
find(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to indicate a matching element has been found, and a falsy value otherwise.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

The first element in the array that satisfies the provided testing function. Otherwise, `undefined` is returned.

## Relevant files

- `src/builtins/array/find.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
