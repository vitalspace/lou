# Array.prototype.flat()

**Status: IMPLEMENTED**

## Description

The `flat()` method of Array instances returns a new array with the sub-array elements concatenated into it recursively up to the specified depth.

## Usage

```js
const arr1 = [1, 2, [3, 4]];

console.log(arr1.flat());
// Expected output: Array [1, 2, 3, 4]

const arr2 = [1, 2, [3, 4, [5, 6]]];

console.log(arr2.flat());
// Expected output: Array [1, 2, 3, 4, [5, 6]]

console.log(arr2.flat(2));
// Expected output: Array [1, 2, 3, 4, 5, 6]
```

## Syntax

```
flat()
flat(depth)
```

### Parameters

- `depth` (Optional) — The depth level specifying how deep a nested array structure should be flattened. Default is `1`.

### Return value

A new array with the elements flattened.

## Relevant files

- `src/builtins/array/flat.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
