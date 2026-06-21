# Array.prototype.join()

**Status: IMPLEMENTED**

## Description

The `join()` method of Array instances concatenates all elements of an array into a string and returns this string.

## Usage

```js
const array1 = ["Fire", "Air", "Water"];

console.log(array1.join());
// Expected output: "Fire,Air,Water"

console.log(array1.join(", "));
// Expected output: "Fire, Air, Water"

console.log(array1.join(" + "));
// Expected output: "Fire + Air + Water"

console.log(array1.join(""));
// Expected output: "FireAirWater"
```

## Syntax

```
join()
join(separator)
```

### Parameters

- `separator` (Optional) — A string used to separate each element of the array. Default is `,`.

### Return value

A string with all array elements joined.

## Relevant files

- `src/builtins/array/join.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
