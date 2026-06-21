# RegExp en métodos de String

**Prioridad: completada**

## Estado

✅ IMPLEMENTADO - Todos los métodos aceptan RegExp:
- `match(RegExp)` - busca coincidencias usando expresiones regulares
- `matchAll(RegExp)` - iterador sobre todas las coincidencias  
- `replace(RegExp, replacement)` - reemplaza usando RegExp (global o primera coincidencia)
- `replaceAll(RegExp, replacement)` - reemplaza todas las coincidencias usando RegExp
- `search(RegExp)` - busca posición de coincidencia usando RegExp
- `split(RegExp)` - divide string usando RegExp como separador

## Características soportadas

- Búsqueda literal simple
- Comodín `.` (cualquier carácter)
- Escape de caracteres `\\`
- Cuantificadores `*`, `+`, `?` (solo con caracteres literales, no con clases)
- Banderas: `g` (global), `i` (ignore case)

## Limitaciones

- Clases de caracteres `[a-z]` funcionan pero no combinan con cuantificadores (`[0-9]+` no funciona)
- No soporta: `^`, `$` anchos, grupos de captura, lookahead/lookbehind
- Los regex son interpretados como patrones simples (no hay motor RegExp completo)

## Verificación

```bash
zig build run -- run js/test-regexp-strings.js
node js/test-regexp-strings.js  # para comparar
```
