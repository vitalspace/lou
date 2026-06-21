# String.prototype.endsWith()

**Status: IMPLEMENTED (limited — byte-level, not codepoint-aware)**

## Description

The `endsWith()` method of String instances determines whether a string ends with the characters of this string, returning `true` or `false` as appropriate.

## Usage

```js
const str = "To be, or not to be, that is the question.";

console.log(str.endsWith("question."));
// Expected output: true

console.log(str.endsWith("to be"));
// Expected output: false

console.log(str.endsWith("to be", 19));
// Expected output: true
```

## Syntax

```
endsWith(searchString)
endsWith(searchString, endPosition)
```

### Parameters

- `searchString` — The characters to be searched for at the end of this string. Cannot be a regex.
- `endPosition` — The end position at which `searchString` is expected to be found (the index of `searchString`'s last character plus 1). Defaults to `str.length`.

### Return value

`true` if the given characters are found at the end of the string, including when `searchString` is an empty string; otherwise `false`.

## Behavior

- Case-sensitive comparison.
- If `searchString` is an empty string, returns `true`.
- If `endPosition` is less than or equal to 0, returns `false`.
- If `searchString` is a regex, throws a `TypeError`.

## Additional Examples

```js
// Empty searchString always returns true
"hello".endsWith("");
// Expected output: true

// endPosition of 0 returns false
"hello".endsWith("hello", 0);
// Expected output: false

// endPosition limits the search scope
"hello world".endsWith("world", 5);
// Expected output: false

// Case-sensitive comparison
"Hello".endsWith("hello");
// Expected output: false

// Regex as searchString throws TypeError
try {
  "hello".endsWith(/o/);
} catch (e) {
  console.log(e instanceof TypeError);
  // Expected output: true
}
```

## Relevant files

- `src/builtins/string/endsWith.zig`


## Tests

> Tests need to be implemented for this method.
