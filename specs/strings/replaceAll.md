# String.prototype.replaceAll()

**Status: IMPLEMENTED (with RegExp support)**

## Description

The `replaceAll()` method of String instances returns a new string with all matches of a pattern replaced by a replacement.

## Usage

```js
const p = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";

console.log(p.replaceAll("dog", "monkey"));
// Expected output: "The quick brown fox jumps over the lazy monkey. If the monkey barked, was it really lazy?"

console.log(p.replaceAll(/dog/g, "monkey"));
// Expected output: "The quick brown fox jumps over the lazy monkey. If the monkey barked, was it really lazy?"
```

## Syntax

```
replaceAll(pattern, replacement)
```

### Parameters

- `pattern` — Can be a string or a RegExp with the global (`g`) flag.
- `replacement` — Can be a string or a function.

### Return value

A new string, with all matches of the pattern replaced by the specified replacement.

## Behavior

- If `pattern` is a string, replaces all occurrences.
- If `pattern` is a RegExp, it can have the `g` flag (recommended).
- The original string is not modified (strings are immutable).

## RegExp Support

Partial RegExp pattern support:
- Literal characters: `^abc$` anchors, `\\` escapes
- Character classes: `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Flags: `g`, `i`

## Relevant files

- `src/builtins/string/replaceAll.zig`


## Tests

- `js/test-regexp-strings.js`
