# Array.prototype.sort()

**Status: IMPLEMENTED**

## Description

The `sort()` method of Array instances sorts the elements of an array in place and returns the sorted array.

## Usage

```js
const months = ["March", "Jan", "Nov", "Jan"];

months.sort();
console.log(months);
// Expected output: Array ["Jan", "Jan", "March", "Nov"]

const numbers = [1, 30, 4, 21, 100000];

numbers.sort();
console.log(numbers);
// Expected output: Array [1, 100000, 21, 30, 4]
```

## Syntax

```
sort()
sort(compareFn)
```

### Parameters

- `compareFn` (Optional) — A function that defines the sort order. If omitted, elements are converted to strings and sorted by Unicode values.

### Return value

The sorted array.

## Relevant files

- `src/builtins/array/sort.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
