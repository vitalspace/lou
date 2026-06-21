# Array.prototype.filter()

**Status: IMPLEMENTED**

## Description

The `filter()` method of Array instances creates a shallow copy of a portion of a given array, filtered down to just the elements from the given array that pass the test implemented by the provided function.

## Usage

```js
const words = ["spray", "elite", "exuberant", "destruction", "present"];

const result = words.filter((word) => word.length > 6);

console.log(result);
// Expected output: Array ["exuberant", "destruction", "present"]
```

## Syntax

```
filter(callbackFn)
filter(callbackFn, thisArg)
```

### Parameters

- `callbackFn` — A function to execute for each element in the array. It should return a truthy value to keep the element in the resulting array, and a falsy value otherwise.
- `thisArg` (Optional) — A value to use as `this` when executing `callbackFn`.

### Return value

A shallow copy of the given array containing just the elements that pass the test. If no elements pass the test, an empty array is returned.

## Relevant files

- `src/builtins/array/filter.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
