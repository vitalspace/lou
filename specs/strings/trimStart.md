# String.prototype.trimStart()

**Status: IMPLEMENTED**

## Description

The `trimStart()` method of String instances removes whitespace from the beginning of this string and returns a new string, without modifying the original string. `trimLeft()` is an alias of this method.

## Usage

```js
const greeting = "   Hello world!   ";

console.log(greeting);
// Expected output: "   Hello world!   "

console.log(greeting.trimStart());
// Expected output: "Hello world!   "
```

## Syntax

```
trimStart()
```

### Parameters

None.

### Return value

A new string representing the calling string stripped of whitespace from its beginning (left end).

## Behavior

- Removes whitespace from the beginning of the string only.
- Does not modify the original string (strings are immutable).

## Relevant files

- `src/builtins/string/trimStart.zig`


## Tests

> Tests need to be implemented for this method.
