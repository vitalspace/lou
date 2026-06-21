# Array.prototype.copyWithin()

**Status: IMPLEMENTED**

## Description

The `copyWithin()` method of Array instances shallow copies part of this array to another location in the same array and returns this array without modifying its length.

## Usage

```js
const array = ["a", "b", "c", "d", "e"];

// Copy to index 0 the element at index 3
console.log(array.copyWithin(0, 3, 4));
// Expected output: Array ["d", "b", "c", "d", "e"]

// Copy to index 1 all elements from index 3 to the end
console.log(array.copyWithin(1, 3));
// Expected output: Array ["d", "d", "e", "d", "e"]
```

## Syntax

```
copyWithin(target, start)
copyWithin(target, start, end)
```

### Parameters

- `target` — Zero-based index at which to copy the sequence to.
- `start` — Zero-based index at which to start copying elements from.
- `end` (Optional) — Zero-based index at which to end copying elements from (not included).

### Return value

The modified array.

## Relevant files

- `src/builtins/array/copyWithin.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
