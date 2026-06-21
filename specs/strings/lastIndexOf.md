# String.prototype.lastIndexOf()

**Status: IMPLEMENTED (limited — byte-level search)**

## Description

The `lastIndexOf()` method of String instances searches this string and returns the index of the last occurrence of the specified substring, searching backwards from `position`.

## Usage

```js
const paragraph = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";

const searchTerm = "dog";

console.log(
  `The index of the first "${searchTerm}" from the beginning is ${paragraph.indexOf(searchTerm)}`,
);
// Expected output: "The index of the first "dog" from the beginning is 40"

console.log(
  `The index of the first "${searchTerm}" from the end is ${paragraph.lastIndexOf(searchTerm)}`,
);
// Expected output: "The index of the first "dog" from the end is 52"
```

## Syntax

```
lastIndexOf(searchString)
lastIndexOf(searchString, position)
```

### Parameters

- `searchString` — Substring to search for.
- `position` — The method searches backward starting from `position`. Defaults to `+Infinity`.

### Return value

The index of the last occurrence of the value `searchString` at a position less than or equal to `position`, or `-1` if not found.

## Behavior

- Returns the index of the last occurrence found (searching backwards).
- Returns `-1` if the substring is not found.
- If `searchString` is an empty string, returns `Math.min(position, str.length)`.
- Case-sensitive search.
- If `position` is negative, it is treated as 0.

## Additional Examples

```js
// Not found returns -1
"hello".lastIndexOf("x");
// Expected output: -1

// Empty searchString returns clamped position
"hello".lastIndexOf("", 2);
// Expected output: 2

"hello".lastIndexOf("");
// Expected output: 5

// position limits search backwards
"hello world".lastIndexOf("o", 4);
// Expected output: 4

"hello world".lastIndexOf("o", 6);
// Expected output: 7

// Case-sensitive comparison
"Hello".lastIndexOf("hello");
// Expected output: -1

// Negative position treated as 0
"hello".lastIndexOf("h", -1);
// Expected output: 0
```

## Relevant files

- `src/builtins/string/lastIndexOf.zig`


## Tests

> Tests need to be implemented for this method.
