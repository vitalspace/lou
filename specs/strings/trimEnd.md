# String.prototype.trimEnd()

**Status: IMPLEMENTED**

## Description

The `trimEnd()` method of String instances removes whitespace from the end of this string and returns a new string, without modifying the original string. `trimRight()` is an alias of this method.

## Usage

```js
const greeting = "   Hello world!   ";

console.log(greeting);
// Expected output: "   Hello world!   "

console.log(greeting.trimEnd());
// Expected output: "   Hello world!"
```

## Syntax

```
trimEnd()
```

### Parameters

None.

### Return value

A new string representing the calling string stripped of whitespace from its end (right end).

## Behavior

- Removes whitespace from the end of the string only.
- Does not modify the original string (strings are immutable).

## Relevant files

- `src/builtins/string/trimEnd.zig`


## Tests

> Tests need to be implemented for this method.
