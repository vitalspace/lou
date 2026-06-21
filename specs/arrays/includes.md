# Array.prototype.includes()

**Status: IMPLEMENTED**

## Description

The `includes()` method of Array instances determines whether an array includes a certain value among its entries, returning `true` or `false` as appropriate.

## Usage

```js
const array1 = [1, 2, 3];

console.log(array1.includes(2));
// Expected output: true

const pets = ["cat", "dog", "bat"];

console.log(pets.includes("cat"));
// Expected output: true

console.log(pets.includes("at"));
// Expected output: false
```

## Syntax

```
includes(searchElement)
includes(searchElement, fromIndex)
```

### Parameters

- `searchElement` — The value to search for.
- `fromIndex` (Optional) — The position in the array at which to begin searching. Default is `0`.

### Return value

`true` if `searchElement` is found within the array; otherwise, `false`.

## Relevant files

- `src/builtins/array/includes.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
