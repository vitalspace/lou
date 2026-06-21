# String.prototype.toString()

**Status: IMPLEMENTED**

## Description

The `toString()` method of String instances returns the value of this string.

## Usage

```js
const x = new String("Hello world");

console.log(x.toString());
// Expected output: "Hello world"
```

## Syntax

```
toString()
```

### Parameters

None.

### Return value

A string representing the specified string value.

## Behavior

- Returns the primitive value of the String object.
- For string primitives, this returns the string itself.

## Relevant files

- `src/builtins/string/toString.zig`


## Tests

> Tests need to be implemented for this method.
