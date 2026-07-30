# String.prototype.padStart / padEnd

## status
completado

## Problema
`tests/compat/string-pad.lou` verifica que `String.prototype.padStart()` y `String.prototype.padEnd()` funcionan correctamente, incluyendo soporte Unicode-aware para caracteres multi-byte.

## Contexto
El test comprueba:

**Sin argumentos:**
- `"hi".padEnd()` → `"hi"` (sin cambios)
- `"hi".padStart()` → `"hi"` (sin cambios)

**Padding básico ASCII:**
- `"hi".padEnd(5)` → `"hi   "`
- `"hi".padEnd(5, ".")` → `"hi..."`
- `"hi".padStart(5)` → `"   hi"`
- `"hi".padStart(5, "0")` → `"000hi"`

**Coerción de targetLength:**
- Boolean y float se coercen a entero

**Soporte Unicode:**
- Caracteres multi-byte como `"é"` o `"🔥"` cuentan como 1 code point
- El pad string también se maneja code-point-aware

**Edge cases:**
- `targetLength` NaN o -Infinity → retorna el string original

## Verificación
```bash
./zig-out/bin/lou run tests/compat/string-pad.lou
diff <(./zig-out/bin/lou run tests/compat/string-pad.lou 2>&1) \
     <(node tests/compat/string-pad.js 2>&1)
```

## Estado del test
- Compat test match: `string-pad.lou`
- Test status: **PASS**

## pendiente
- (ninguno — test de regresión, padStart/padEnd ya implementados)
