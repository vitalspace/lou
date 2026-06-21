# String.prototype.toWellFormed()

**Status: IMPLEMENTED**

## Description

The `toWellFormed()` method of String instances returns a string where all lone surrogates of this string are replaced with the Unicode replacement character U+FFFD.

## Usage

```js
const str1 = "hello\uD800";
console.log(str1.toWellFormed());
// Expected output: "hello\uFFFD"

const str2 = "hello";
console.log(str2.toWellFormed());
// Expected output: "hello"
```

## Syntax

```
toWellFormed()
```

### Parameters

None.

### Return value

A new string that is a copy of this string, with all lone surrogates replaced with the Unicode replacement character. If the string is already well-formed, the same string is returned.

## Behavior

- Replaces lone surrogates with U+FFFD.
- Returns the same string reference if no changes are needed.

## Relevant files

- `src/builtins/string/toWellFormed.zig`


## Tests

> Tests need to be implemented for this method.
