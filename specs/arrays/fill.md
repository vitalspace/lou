# Array.prototype.fill()

**Status: IMPLEMENTED**

## Description

The `fill()` method of Array instances changes all elements within a range of indices in an array to a static value. It returns the modified array.

## Usage

```js
const array = [1, 2, 3, 4];

// Fill with 0 from position 2 until position 4
console.log(array.fill(0, 2, 4));
// Expected output: Array [1, 2, 0, 0]

// Fill with 5 from position 1
console.log(array.fill(5, 1));
// Expected output: Array [1, 5, 5, 5]

console.log(array.fill(6));
// Expected output: Array [6, 6, 6, 6]
```

## Syntax

```
fill(value)
fill(value, start)
fill(value, start, end)
```

### Parameters

- `value` — Value to fill the array with.
- `start` (Optional) — Zero-based index at which to start filling.
- `end` (Optional) — Zero-based index at which to end filling (not included).

### Return value

The modified array, filled with value.

## Relevant files

- `src/builtins/array/fill.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
