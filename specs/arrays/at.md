# Array.prototype.at()

**Status: IMPLEMENTED**

## Description

The `at()` method of Array instances takes an integer value and returns the element at that index, supporting both positive and negative integers. Negative integers count back from the last element of the array.

## Usage

```js
const array = [5, 12, 8, 130, 44];

let index = 2;
console.log(`An index of ${index} returns ${array.at(index)}`);
// Expected output: "An index of 2 returns 8"

index = -2;
console.log(`An index of ${index} returns ${array.at(index)}`);
// Expected output: "An index of -2 returns 130"
```

## Syntax

```
at(index)
```

### Parameters

- `index` — Zero-based index of the array element to be located. Can be negative to count back from the end.

### Return value

The element at the specified index. Returns `undefined` if the index is out of bounds.

## Relevant files

- `src/builtins/array/at.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
