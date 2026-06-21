# Array.prototype.unshift()

**Status: IMPLEMENTED**

## Description

The `unshift()` method of Array instances adds one or more elements to the beginning of an array and returns the new length of the array.

## Usage

```js
const array1 = [1, 2, 3];

console.log(array1.unshift(4, 5));
// Expected output: 5

console.log(array1);
// Expected output: Array [4, 5, 1, 2, 3]
```

## Syntax

```
unshift(element1)
unshift(element1, element2)
unshift(element1, element2, /* …, */ elementN)
```

### Parameters

- `element1, …, elementN` — The elements to add to the front of the array.

### Return value

The new length of the array.

## Relevant files

- `src/builtins/array/unshift.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
