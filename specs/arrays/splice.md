# Array.prototype.splice()

**Status: IMPLEMENTED**

## Description

The `splice()` method of Array instances changes the contents of an array by removing or replacing existing elements and/or adding new elements.

## Usage

```js
const months = ["Jan", "March", "April", "June"];

months.splice(1, 0, "Feb");
console.log(months);
// Expected output: Array ["Jan", "Feb", "March", "April", "June"]

months.splice(4, 1, "May");
console.log(months);
// Expected output: Array ["Jan", "Feb", "March", "April", "May"]
```

## Syntax

```
splice(start)
splice(start, deleteCount)
splice(start, deleteCount, item1)
splice(start, deleteCount, item1, item2)
splice(start, deleteCount, item1, item2, /* …, */ itemN)
```

### Parameters

- `start` — Index at which to start changing the array. If negative, `array.length + start` is used.
- `deleteCount` (Optional) — The number of elements to remove from `start`.
- `item1, item2, …` (Optional) — Elements to add to the array starting at `start`.

### Return value

An array containing the deleted elements.

## Relevant files

- `src/builtins/array/splice.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
