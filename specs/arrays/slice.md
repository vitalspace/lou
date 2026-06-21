# Array.prototype.slice()

**Status: IMPLEMENTED**

## Description

The `slice()` method of Array instances returns a shallow copy of a portion of an array into a new array object selected from `start` to `end` (end not included).

## Usage

```js
const animals = ["ant", "bison", "camel", "duck", "elephant"];

console.log(animals.slice(2));
// Expected output: Array ["camel", "duck", "elephant"]

console.log(animals.slice(2, 4));
// Expected output: Array ["camel", "duck"]

console.log(animals.slice(1, 5));
// Expected output: Array ["bison", "camel", "duck", "elephant"]
```

## Syntax

```
slice()
slice(start)
slice(start, end)
```

### Parameters

- `start` (Optional) — Zero-based index at which to begin extraction. If negative, `array.length + start` is used.
- `end` (Optional) — Zero-based index at which to end extraction (not included). If omitted, `array.length` is used.

### Return value

A new array containing the extracted elements.

## Relevant files

- `src/builtins/array/slice.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
