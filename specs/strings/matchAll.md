# String.prototype.matchAll()

**Status: IMPLEMENTED (with RegExp support)**

## Description

The `matchAll()` method of String instances returns an iterator of all results matching this string against a regular expression, including capturing groups.

## Usage

```js
const str = "test1test2";
const regexp = new RegExp("test", "g");

const array = [...str.matchAll(regexp)];
console.log(array[0]);
// Expected output: Array ["test"]

console.log(array[1]);
// Expected output: Array ["test"]
```

## Syntax

```
matchAll(regexp)
```

### Parameters

- `regexp` — A regular expression object. If a non-RegExp object is passed, it is implicitly converted to a RegExp by using `new RegExp(regexp)`.

### Return value

An iterator of all matched results, including capturing groups.

## Behavior

- Returns an iterator that yields each match as an array.
- Works with RegExp objects.

## RegExp Support

Partial RegExp pattern support:
- Literal characters: `^abc$` anchors, `\\` escapes
- Character classes: `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Flags: `g`, `i`

## Relevant files

- `src/builtins/string/matchAll.zig`


## Tests

- `js/test-regexp-strings.js`
