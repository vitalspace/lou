# String.prototype.includes()

**Status: IMPLEMENTED (limited — byte-level search)**

## Description

The `includes()` method of String instances performs a case-sensitive search to determine whether one string may be found within this string, returning `true` or `false` as appropriate.

## Usage

```js
const sentence = "The quick brown fox jumps over the lazy dog.";

const word = "fox";

console.log(`The word "${word}" ${sentence.includes(word) ? "is" : "is not"} in the sentence`);
// Expected output: "The word "fox" is in the sentence"
```

## Syntax

```
includes(searchString)
includes(searchString, position)
```

### Parameters

- `searchString` — A string to be searched for within this string. Cannot be a regex.
- `position` — The position within the string at which to begin searching for `searchString`. Defaults to 0.

### Return value

`true` if the search string is found anywhere within the given string, including when `searchString` is an empty string; otherwise `false`.

## Behavior

- Case-sensitive search.
- If `searchString` is an empty string, returns `true`.
- If `position` is negative, it is treated as 0.
- If `searchString` is a regex, throws a `TypeError`.

## Additional Examples

```js
// position parameter starts search later
"hello world".includes("world", 6);
// Expected output: true

"hello world".includes("world", 7);
// Expected output: false

// Empty searchString always returns true
"hello".includes("");
// Expected output: true

// Case-sensitive comparison
"Hello World".includes("world");
// Expected output: false

// Not found returns false
"hello".includes("x");
// Expected output: false

// Regex as searchString throws TypeError
try {
  "hello".includes(/o/);
} catch (e) {
  console.log(e instanceof TypeError);
  // Expected output: true
}
```

## Relevant files

- `src/builtins/string/includes.zig`


## Tests

> Tests need to be implemented for this method.
