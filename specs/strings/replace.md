# String.prototype.replace()

**Status: IMPLEMENTED (with RegExp support)**

## Description

The `replace()` method of String instances returns a new string with one, some, or all matches of a pattern replaced by a replacement. The pattern can be a string or a RegExp, and the replacement can be a string or a function called for each match.

## Usage

```js
const p = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";

console.log(p.replace("dog", "monkey"));
// Expected output: "The quick brown fox jumps over the lazy monkey. If the dog barked, was it really lazy?"

console.log(p.replace(/dog/g, "monkey"));
// Expected output: "The quick brown fox jumps over the lazy monkey. If the monkey barked, was it really lazy?"
```

## Syntax

```
replace(pattern, replacement)
```

### Parameters

- `pattern` — Can be a string or a RegExp.
- `replacement` — Can be a string or a function. The string can include special replacement patterns.

### Return value

A new string, with one, some, or all matches of the pattern replaced by the specified replacement.

## Behavior

- Only replaces the first match if `pattern` is a string.
- Use `replaceAll()` or a regex with the `g` flag to replace all occurrences.
- The original string is not modified (strings are immutable).

## RegExp Support

Partial RegExp pattern support:
- Literal characters: `^abc$` anchors, `\\` escapes
- Character classes: `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Flags: `g`, `i`

## Relevant files

- `src/builtins/string/replace.zig`


## Tests

- `js/test-regexp-strings.js`
