# Array.prototype.entries()

**Status: IMPLEMENTED**

## Description

The `entries()` method of Array instances returns a new array iterator object that contains the key/value pairs for each index in the array.

## Usage

```js
const array = ["a", "b", "c"];

const iterator = array.entries();

console.log(iterator.next().value);
// Expected output: Array [0, "a"]

console.log(iterator.next().value);
// Expected output: Array [1, "b"]
```

## Syntax

```
entries()
```

### Parameters

None.

### Return value

A new iterable iterator object.

## Relevant files

- `src/builtins/array/entries.zig`
- `src/builtins/array/array.zig`
- `src/builtins/builtins.zig`
- `src/evaluator.zig`
