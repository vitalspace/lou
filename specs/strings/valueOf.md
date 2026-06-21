# String.prototype.valueOf()

**Status: IMPLEMENTED**

## Description

The `valueOf()` method of String instances returns the primitive value of this string.

## Usage

```js
const x = new String("Hello world");

console.log(x.valueOf());
// Expected output: "Hello world"
```

## Syntax

```
valueOf()
```

### Parameters

None.

### Return value

A string representing the primitive value of the specified String object.

## Behavior

- Returns the primitive value of the String object.
- Called internally by JavaScript to convert a String object to a primitive.

## Relevant files

- `src/builtins/string/valueOf.zig`


## Tests

> Tests need to be implemented for this method.
