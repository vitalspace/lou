# String.prototype.toLowerCase()

**Status: IMPLEMENTED (limited — ASCII-only, no Unicode case mapping)**

## Description

The `toLowerCase()` method of String instances returns this string converted to lower case.

## Usage

```js
const sentence = "The quick brown fox jumps over the lazy dog.";

console.log(sentence.toLowerCase());
// Expected output: "the quick brown fox jumps over the lazy dog."
```

## Syntax

```
toLowerCase()
```

### Parameters

None.

### Return value

A new string representing the calling string converted to lower case.

## Behavior

- Converts all characters to their lowercase equivalents.
- Does not modify the original string (strings are immutable).

## Relevant files

- `src/builtins/string/toLowerCase.zig`


## Tests

> Tests need to be implemented for this method.
