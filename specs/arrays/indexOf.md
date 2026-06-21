# Array.prototype.indexOf()

**Status: IMPLEMENTED**

## Description

The `indexOf()` method of Array instances returns the first index at which a given element can be found in the array, or `-1` if it is not present.

## Usage

```js
const beasts = ["ant", "bison", "camel", "duck", "bison"];

console.log(beasts.indexOf("bison"));
// Expected output: 1

console.log(beasts.indexOf("bison", 2));
// Expected output: 4

console.log(beasts.indexOf("giraffe"));
// Expected output: -1
```

## Syntax

```
indexOf(searchElement)
indexOf(searchElement, fromIndex)
```

### Parameters

- `searchElement` — Element to search for.
- `fromIndex` (Optional) — The position in the array at which to begin searching. Default is `0`.

### Return value

The lowest index at which the element is found, or `-1` if not found.

## Relevant files

- `src/builtins/array/indexOf.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
