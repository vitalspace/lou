# String.prototype.toUpperCase()

**Status: IMPLEMENTED (limited — ASCII-only, no Unicode case mapping)**

## Description

The `toUpperCase()` method of String instances returns this string converted to upper case.

## Usage

```js
const sentence = "The quick brown fox jumps over the lazy dog.";

console.log(sentence.toUpperCase());
// Expected output: "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG."
```

## Syntax

```
toUpperCase()
```

### Parameters

None.

### Return value

A new string representing the calling string converted to upper case.

## Behavior

- Converts all characters to their uppercase equivalents.
- Does not modify the original string (strings are immutable).

## Relevant files

- `src/builtins/string/toUpperCase.zig`


## Tests

> Tests need to be implemented for this method.
