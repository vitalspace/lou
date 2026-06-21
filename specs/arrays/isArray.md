# Array.isArray()

**Status: IMPLEMENTED**

## Description

The static method `Array.isArray()` determines whether the passed value is an Array.

## Usage

```js
console.log(Array.isArray([1, 3]));
// Expected output: true

console.log(Array.isArray({ length: 3 }));
// Expected output: false

console.log(Array.isArray([]);
// Expected output: true
```

## Syntax

```
Array.isArray(value)
```

### Parameters

- `value` — The value to be checked.

### Return value

`true` if `value` is an Array; otherwise, `false`.

## Relevant files

- `src/builtins/array/isArray.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
