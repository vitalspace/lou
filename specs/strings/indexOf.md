# String.prototype.indexOf()

**Status: IMPLEMENTED (limited — byte-level search)**

## Description

The `indexOf()` method of String instances searches this string and returns the index of the first occurrence of the specified substring. If the substring is not found, it returns -1.

## Usage

```js
const paragraph = "The quick brown fox jumps over the lazy dog. If the dog barked, was it really lazy?";

const searchTerm = "dog";
const indexOfFirst = paragraph.indexOf(searchTerm);

console.log(`The index of the first "${searchTerm}" from the beginning is ${indexOfFirst}`);
// Expected output: "The index of the first "dog" from the beginning is 40"

console.log(
  `The index of the second "${searchTerm}" is ${paragraph.indexOf(searchTerm, indexOfFirst + 1)}`,
);
// Expected output: "The index of the second "dog" is 52"
```

## Syntax

```
indexOf(searchString)
indexOf(searchString, position)
```

### Parameters

- `searchString` — Substring to search for.
- `position` — The method starts searching at `position`. Defaults to 0.

### Return value

The index of the first occurrence of the value `searchString` at a position greater than or equal to `position`, or `-1` if not found.

## Behavior

- Returns the index of the first occurrence found.
- Returns `-1` if the substring is not found.
- If `searchString` is an empty string, returns `position` (or 0 if not specified).
- Case-sensitive search.

## Additional Examples

```js
// Not found returns -1
"hello".indexOf("x");
// Expected output: -1

// Empty searchString returns position
"hello".indexOf("", 2);
// Expected output: 2

"hello".indexOf("", 99);
// Expected output: 5

// position parameter starts search later
"hello world".indexOf("o", 5);
// Expected output: 7

// Case-sensitive comparison
"Hello".indexOf("hello");
// Expected output: -1

// position beyond string length
"hello".indexOf("h", 10);
// Expected output: -1
```

## Relevant files

- `src/builtins/string/indexOf.zig`


## Tests

> Tests need to be implemented for this method.
