# String.prototype.search()

**Status: IMPLEMENTED (with RegExp support)**

## Description

The `search()` method of String instances executes a search for a match between a regular expression and this string.

## Usage

```js
const paragraph = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";

const regex = new RegExp("nonexistent");
console.log(paragraph.search(regex));
// Expected output: -1

const regex2 = /[^\w\s]/g;
console.log(paragraph.search(regex2));
// Expected output: 4 (index of the first punctuation mark)
```

## Syntax

```
search(regexp)
```

### Parameters

- `regexp` — A regular expression object. If a non-RegExp object is passed, it is implicitly converted to a RegExp by using `new RegExp(regexp)`.

### Return value

The index of the first match between the regular expression and the given string, or `-1` if no match was found.

## Behavior

- Returns the index of the first match.
- Returns `-1` if no match is found.
- The `g` flag is ignored (it does not affect `search()`).

## RegExp Support

Partial RegExp pattern support:
- Literal characters: `^abc$` anchors, `\\` escapes
- Character classes: `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Flags: `g`, `i`

## Relevant files

- `src/builtins/string/search.zig`


## Tests

- `js/test-regexp-strings.js`
