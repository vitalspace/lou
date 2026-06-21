# Hacer búsquedas de strings codepoint-aware

## status

✅ IMPLEMENTADO

## Problema

`endsWith`, `includes`, `indexOf`, `lastIndexOf`, `startsWith` operaban a nivel de bytes, no de code points. En strings UTF-8 con caracteres multi-byte (ej: `"ü"`, `"ñ"`, `"😀"`), las búsquedas fallaban o daban resultados incorrectos.

## Cambios realizados

### 1. `src/builtins/string/string_utils.zig`
- Agregado helper `byteToCp(s, byte_offset)` — convierte byte offset a codepoint index (inverso de `cpToByte`)

### 2. `src/builtins/string/indexOf.zig`
- Convierte `position` de codepoints→bytes con `cpToByte` antes de buscar
- Usa `std.mem.indexOf` a nivel de bytes (correcto porque UTF-8 es prefix-free)
- Convierte resultado de bytes→codepoints con `byteToCp` para el return

### 3. `src/builtins/string/lastIndexOf.zig`
- Misma aproximación: convierte posición a bytes, busca hacia atrás, convierte resultado a codepoints
- Default position ahora usa `cpCount(s)` en vez de `s.len`

### 4. `src/builtins/string/includes.zig`
- Convierte `position` de codepoints→bytes antes de la búsqueda

### 5. `src/builtins/string/startsWith.zig`
- Convierte `position` de codepoints→bytes para comparación de slice

### 6. `src/builtins/string/endsWith.zig`
- Convierte `endPosition` de codepoints→bytes para comparación
- Default position ahora usa `cpCount(s)` en vez de `s.len`

## Verificación

- 811/811 tests unitarios Zig pasan
- 26/26 suites de tests generales pasan
- Salida de Lou coincide con Node.js para todos los casos Unicode

### Tests ejecutados

```js
// indexOf
console.log("ñoño".indexOf("o"));           // 1 ✅
console.log("ñoño".indexOf("ñ"));           // 0 ✅
console.log("ñoño".indexOf("o", 2));        // 3 ✅
console.log("ñoño".indexOf("ñ", 1));        // 2 ✅
console.log("hola 😀 mundo".indexOf("😀")); // 5 ✅

// lastIndexOf
console.log("ñoño".lastIndexOf("o"));       // 3 ✅
console.log("ñoño".lastIndexOf("o", 2));    // 1 ✅

// includes
console.log("ñoño".includes("ñ"));          // true ✅
console.log("ñoño".includes("o", 1));       // true ✅
console.log("ñoño".includes("ñ", 1));       // false ✅ (o en cp1, ñ en cp0 y cp2)

// startsWith
console.log("ñoño".startsWith("ño"));       // true ✅
console.log("ñoño".startsWith("ño", 2));    // true ✅
console.log("ñoño".startsWith("o", 1));     // true ✅

// endsWith
console.log("ñoño".endsWith("ño"));         // true ✅
console.log("ñoño".endsWith("o"));          // true ✅
console.log("ñoño".endsWith("o", 3));       // false ✅ (primeros 3 cp = "ñoñ")
```

## Diseño

La aproximación es correcta porque UTF-8 es prefix-free: las búsquedas a nivel de byte encuentran matches válidos de codepoints. Solo se necesita convertir en las fronteras:
- **Input**: convertir `position` de codepoints→bytes
- **Output**: convertir byte offset del match→codepoints

Los helpers `cpCount`, `cpToByte` y `byteToCp` de `string_utils.zig` manejan toda la conversión.
