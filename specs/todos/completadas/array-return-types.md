# ~~push/unshift retornan float en vez de entero~~ (RESUELTO)

**Resuelto en:** `src/builtins/array/push.zig`, `src/builtins/array/unshift.zig`

## Cambio

`push` y `unshift` ahora retornan `Value.integer` en vez de `Value.float`. Coincide con el comportamiento de Node.js (retorna entero) y con `Array.prototype.length` que ya usaba `.integer`.

## Verificación

- `const a = []; a.push(1)` — `a.length` es `1` como entero
- Tests existentes en `push.zig` y `unshift.zig` validan el tipo de retorno
