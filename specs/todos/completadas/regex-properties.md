# RegExp properties and methods

## status

**completada** — implementada (compat: 84 PASS / 1 FAIL / 1 SKIP)

`tests/compat/regex-properties.lou` produce salida byte-idéntica a Node.

## Problema

La infraestructura de `RegExpValue` ya existía (constructor, motor, `test`,
`exec`, `toString`), pero los valores `.regexp` no estaban conectados a:

- `MemberAccess`: `re.source`, `re.flags`, `re.global`, … devolvían `undefined`.
- Asignación: `re.lastIndex = 3` era un no-op (el VM se tragaba el error).
- `MethodCall`: `re.test(...)` y `re.exec(...)` devolvían `undefined`.
- `flags`: `flagsString` devolvía un slice de un buffer de stack, así que
  `re.flags` imprimía basura.

## Implementación

### `src/evaluator.zig`

- `MemberAccess` con `.regexp` → `regexpMod.getProperty`.
- `BinaryExpression .Assign` sobre `MemberAccess` de un `.regexp` →
  `regexpMod.setProperty` (sólo `lastIndex` es escribible).
- `MethodCall` para receptores `.regexp` (identificador o expresión) →
  helper `callRegExpMethod`, que antepone el receptor a los argumentos y
  despacha contra el builtin object `RegExp`.

### `src/vm.zig`

- `get_prop`, `set_prop` y `method_call` (con y sin argumentos) ganan prongs
  para `.regexp`, usando el mismo `getProperty`/`setProperty` y los métodos
  de `REGEXP_OBJECT` (`test`, `exec`, `toString`, `@@match`, …).

### `src/builtins/regex/regexp.zig`

- `flagsString` devuelve `regexp.flags` (buffer propio) en lugar de un
  `[8]u8` local que quedaba colgando.

## Limitaciones conocidas

- `String.prototype.replace/split` con un regex literal como primer
  argumento todavía no usa el motor: tratan el valor como string. Es un gap
  separado.
