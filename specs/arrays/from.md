# Array.from()

**Status: IMPLEMENTED**

## Description

The static method `Array.from()` creates a new Array instance from an array-like or iterable object.

## Usage

```js
console.log(Array.from("foo"));
// Expected output: Array ["f", "o", "o"]

console.log(Array.from([1, 2, 3], (x) => x + x));
// Expected output: Array [2, 4, 6]
```

## Syntax

```
Array.from(arrayLike)
Array.from(arrayLike, mapFn)
Array.from(arrayLike, mapFn, thisArg)
```

### Parameters

- `arrayLike` — An array-like or iterable object to convert to an array.
- `mapFn` (Optional) — A map function to call on every element of the array.
- `thisArg` (Optional) — A value to use as `this` when executing `mapFn`.

### Return value

A new Array instance.

## Relevant files

- `src/builtins/array/from.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
