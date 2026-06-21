# String.prototype.split()

**Status: IMPLEMENTED (with RegExp support)**

## Description

The `split()` method of String instances takes a pattern and divides this string into an ordered list of substrings by searching for the pattern, puts these substrings into an array, and returns the array.

## Usage

```js
const str = "The quick brown fox jumps over the lazy dog.";

const words = str.split(" ");
console.log(words[3]);
// Expected output: "fox"

const chars = str.split("");
console.log(chars[8]);
// Expected output: "k"

const strCopy = str.split();
console.log(strCopy);
// Expected output: Array ["The quick brown fox jumps over the lazy dog."]

const csv = "a,b,c".split(new RegExp(","));
console.log(csv);
// Expected output: Array ["a", "b", "c"]
```

## Syntax

```
split()
split(separator)
split(separator, limit)
```

### Parameters

- `separator` — The pattern describing where each split should occur. Can be a string or a RegExp.
- `limit` — A non-negative integer specifying a limit on the number of substrings to be included in the array.

### Return value

An Array of strings, split at each point where the separator occurs in the given string.

## Behavior

- If `separator` is omitted, the array contains one element consisting of the entire string.
- If `separator` is an empty string, the string is split between each character.
- If `separator` is found at the beginning or end of the string, it still produces an empty string element.

## RegExp Support

Partial RegExp pattern support:
- Literal characters: `^abc$` anchors, `\\` escapes
- Character classes: `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Flags: `g`, `i`

## Relevant files

- `src/builtins/string/split.zig`


## Tests

- `js/test-regexp-strings.js`
