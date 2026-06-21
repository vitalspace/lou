# Array.prototype.shift()

**Status: IMPLEMENTED**

## Description

The `shift()` method of Array instances removes the first element from an array and returns that removed element. This method changes the length of the array.

## Usage

```js
const array1 = [1, 2, 3];

const firstElement = array1.shift();

console.log(array1);
// Expected output: Array [2, 3]

console.log(firstElement);
// Expected output: 1
```

## Syntax

```
shift()
```

### Return value

The removed element from the array. `undefined` if the array is empty.

## Relevant files

- `src/builtins/array/shift.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
