# Array.prototype.with()

**Status: IMPLEMENTED**

## Description

The `with()` method of Array instances returns a new array with the element at the given index replaced with the given value.

## Usage

```js
const array1 = [1, 2, 3, 4, 5];

console.log(array1.with(2, 6));
// Expected output: Array [1, 2, 6, 4, 5]

console.log(array1);
// Expected output: Array [1, 2, 3, 4, 5]
```

## Syntax

```
with(index, value)
```

### Parameters

- `index` — The index of the array at which to replace the value. If negative, `array.length + index` is used.
- `value` — The new value to put at the given index.

### Return value

A new array with the element at the given index replaced.

## Relevant files

- `src/builtins/array/with.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
