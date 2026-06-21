# Array.prototype.concat()

**Status: IMPLEMENTED**

## Description

The `concat()` method of Array instances is used to merge two or more arrays. This method does not change the existing arrays, but instead returns a new array.

## Usage

```js
const array1 = ["a", "b", "c"];
const array2 = ["d", "e", "f"];
const array3 = array1.concat(array2);

console.log(array3);
// Expected output: Array ["a", "b", "c", "d", "e", "f"]
```

## Syntax

```
concat()
concat(value1)
concat(value1, value2)
concat(value1, value2, /* …, */ valueN)
```

### Parameters

- `value1, …, valueN` (Optional) — Arrays and/or values to concatenate into a new array.

### Return value

A new Array instance.

## Relevant files

- `src/builtins/array/concat.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
