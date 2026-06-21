# String.prototype.trim()

**Status: IMPLEMENTED**

## Description

The `trim()` method of String instances removes whitespace from both ends of this string and returns a new string, without modifying the original string.

## Usage

```js
const greeting = "   Hello world!   ";

console.log(greeting);
// Expected output: "   Hello world!   "

console.log(greeting.trim());
// Expected output: "Hello world!"
```

## Syntax

```
trim()
```

### Parameters

None.

### Return value

A new string representing the calling string stripped of whitespace from both its beginning and end.

## Behavior

- Removes whitespace from the beginning and end of the string.
- Does not modify the original string (strings are immutable).
- Whitespace includes spaces, tabs, no-break spaces, and line terminators.

## Relevant files

- `src/builtins/string/trim.zig`


## Tests

> Tests need to be implemented for this method.
