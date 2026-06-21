# Array.prototype.length

**Status: IMPLEMENTED**

## Description

The `length` property of Array instances returns the number of elements in an array. This is a property, not a method.

## Usage

```js
const array1 = [1, 2, 3, 4];
console.log(array1.length);
// Expected output: 4

const array2 = [];
console.log(array2.length);
// Expected output: 0
```

## Behavior

- If the array is empty, returns 0.
- If the argument is not an array, returns 0.
- If more than one argument is passed, returns 0.
- If no arguments are passed, returns 0.

## Relevant files

- `src/builtins/array/length.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
