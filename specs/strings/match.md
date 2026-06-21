# String.prototype.match()

**Status: IMPLEMENTED (RegExp support added)**

## Description

The `match()` method of String instances retrieves the result of matching this string against a regular expression.

## Usage

```js
const paragraph = "The quick brown fox jumps over the lazy dog. It barked.";

const regex = /[A-Z]/g;
const found = paragraph.match(regex);

console.log(found);
// Expected output: Array ["T", "I"]
```

## Syntax

```
match(regexp)
```

### Parameters

- `regexp` — A regular expression object, or any object that has a `Symbol.match` method. If `regexp` is a non-RegExp object, it is implicitly converted to a RegExp by using `new RegExp(regexp)`.

### Return value

An Array whose contents depend on the presence or absence of the global (`g`) flag, or `null` if no matches are found.

## Behavior

- If the `g` flag is used, all results matching the complete regular expression will be returned, but capturing groups are not included.
- If the `g` flag is not used, only the first complete match and its related capturing groups are returned.

## RegExp Support

Partial RegExp pattern support:
- Literal characters: `^abc$` anchors, `\\` escapes
- Character classes: `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Flags: `g`, `i`

## Relevant files

- `src/builtins/string/match.zig`


## Tests

- `js/test-regexp-strings.js`
