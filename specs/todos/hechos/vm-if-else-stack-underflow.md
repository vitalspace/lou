# VM: stack underflow en if/else if/else

## status

✅ IMPLEMENTADO

## Problema

Al ejecutar cadenas `else if` con la VM (`use_vm = true`), se produce stack underflow:

```
STACK UNDERFLOW: ip=94
```

## Causa raíz

Bug de precedencia de operadores en el handler `jump` del bytecode VM en `src/vm.zig`:

```zig
// ANTES (bug): `+` tiene mayor precedencia que `|` en Zig
self.ip += 2 + (@as(usize,hi) << 8) | lo;
// Se evalúa como: (2 + (hi << 8)) | lo  ← INCORRECTO

// DESPUÉS (fix): paréntesis explícitos
self.ip += 2 + ((@as(usize,hi) << 8) | lo);
// Se evalúa como: 2 + ((hi << 8) | lo)  ← CORRECTO
```

Cuando `lo & 2 != 0`, la operación `| lo` corrompe el offset, haciendo que el salto sea 2 bytes corto. Esto causa que la ejecución caiga en instrucciones intermedias, corrompiendo el stack.

Los handlers `jump_if_false` y `loop` NO tenían este bug porque usan statements separados (`ip += 2; if (...) ip += offset;`).

## Fix

**Archivo:** `src/vm.zig` — línea del handler `.jump`

Añadir paréntesis para asegurar que `(hi << 8) | lo` se evalúa antes de `2 +`.

## Verificación

- [x] 3-level chained else-if funciona correctamente
- [x] 2-level chained else-if funciona correctamente
- [x] Simple if-else funciona correctamente
- [x] 811+ unit tests zig pasan
- [x] 29/29 general test suites pasan
- [x] Salida coincide con Node.js

### Test verificado

```js
var a = 1;
if (a == 0) { console.log("cero"); }
else if (a == 1) { console.log("uno"); }
else if (a == 2) { console.log("dos"); }
else { console.log("otro"); }
// Lou: "uno" ✅  Node.js: "uno" ✅
```
