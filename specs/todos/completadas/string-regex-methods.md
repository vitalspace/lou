# String methods with regex patterns

## status

**completada** — implementada (compat: 88 PASS / 0 FAIL / 0 SKIP)

`tests/compat/regex-string-methods.lou` produce salida byte-idéntica a Node.

## Problema

`String.prototype.replace` y `split` sólo aceptaban un patrón string. Si el
primer argumento era un `.regexp`, caían en las ramas `else`:

```js
"a1b2".replace(/[0-9]/g, "x") // devolvía "a1b2"
"a,b".split(/,/)               // devolvía ["a,b"]
```

## Implementación

### `src/builtins/string/replace.zig`

- Si el patrón es `.regexp`, delega en `RegExpReplace` (`@@replace`) con
  `[regexp, string, replacement]`.
- Sin tercer argumento el reemplazo es el string `"undefined"` (spec JS).

### `src/builtins/string/split.zig`

- Si el separador es `.regexp`, delega en `RegExpSplit` (`@@split`)
  propagando el `limit` opcional.

### `src/builtins/regex/regexp.zig`

- `RegExpSplit` reescrito: separadores al inicio y consecutivos generan
  segmentos vacíos, un patrón sin match devuelve el string una sola vez,
  `limit` se respeta en todos los caminos y los matches de longitud cero
  avanzan para no colgarse.
- `"".split(/re/)` devuelve `[]` (como Node).

## Verificación

- Fixture nuevo con `replace` global/no global, `$1`, flag `i`, y `split`
  con límites, separadores consecutivos y sin match.
- Tests unitarios en `replace.zig` y `evaluator.zig`.
