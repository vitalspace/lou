# Array.prototype.lastIndexOf()

**Status: IMPLEMENTED**

## Description

The `lastIndexOf()` method of Array instances returns the last index at which a given element can be found in the array, or `-1` if it is not present.

## Usage

```js
const animals = ["Dodo", "Tiger", "Penguin", "Dodo"];

console.log(animals.lastIndexOf("Dodo"));
// Expected output: 3

console.log(animals.lastIndexOf("Dodo", 2));
// Expected output: 0
```

## Syntax

```
lastIndexOf(searchElement)
lastIndexOf(searchElement, fromIndex)
```

### Parameters

- `searchElement` — Element to search for.
- `fromIndex` (Optional) — The position in the array at which to start searching backwards. Default is `array.length - 1`.

### Return value

The last index at which the element is found, or `-1` if not found.

## Relevant files

- `src/builtins/array/lastIndexOf.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
