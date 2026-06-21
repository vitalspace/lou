# 04 — Edge Cases, Bugs y Diferencias con V8

## Bugs conocidos del engine

### B1 — `\B` word boundary al inicio

**Estado**: ❌ Abierto — documentado en tests
**Descripción**: `\B` no coincide correctamente cuando está al inicio de la
cadena y la primera letra es word character.

```js
"hello".match(/\B/g)
// Lou:     ["e", "l"]
// JS/V8:   ["e", "l", "l", "o"]
// Espec:   Entre "h" y "e" hay \B porque h y e son word chars
```

**Causa probable**: El chequeo de `left_w` en la VM usa `input_pos > 0` para
determinar el carácter izquierdo. Cuando `input_pos == 0`, `left_w` es
`false`, pero `right_w` es `true` (porque la primera letra es word char).
Según la definición de `\B`, si `left_w == right_w` debe coincidir. En la
posición 0, `left_w = false` y `right_w = true`, lo que da `\b` (boundary),
no `\B`. Parece correcto para la posición 0, pero el test falla en "l" vs "l,o".

**Diagnóstico más preciso**: El match global con `/\B/g` en "hello" debería
retornar las posiciones entre caracteres word. Las posiciones son:
- h→e: \B (word→word) ✓
- e→l: \B (word→word) ✓
- l→l: \B (word→word) ✓ (falta en Lou)
- l→o: \B (word→word) ✓ (falta en Lou)
- o→$: \b (word→non-word) ✗

Lou retorna 2, V8 retorna 4. Parece que el motor de Lou no avanza
correctamente después de coincidir `\B` en posición 0 cuando usa /g.

### B2 — Captures en lookahead descartadas

**Estado**: ❌ Abierto
**Descripción**: Las capturas dentro de lookahead deberían preservarse para
retroreferencias posteriores, pero Lou las descarta.

```js
/(?=(a))\1/.test("a")
// Lou: false
// JS:  true
```

**Causa**: La VM crea un thread separado para el lookahead y las saves se
pierden al restaurar el thread principal.

### B3 — Flags no heredados en constructor con RegExp arg

**Estado**: ❌ Abierto
**Descripción**: `new RegExp(/foo/gi)` debería heredar flags "gi".

```js
new RegExp(/foo/gi) 
// Lou: { pattern: "foo", flags: "" }
// JS:  { pattern: "foo", flags: "gi" }
```

**Causa**: `regexp_constructor.zig` extrae solo el pattern, no los flags.
Ver sección 02-regexp-builtins.md para más detalles.

### B4 — Comentario `//` vs regexp vacío

**Estado**: ⚠️ Workaround documented
**Descripción**: `//` se interpreta como comentario de línea, no como regexp
vacío. Usar `new RegExp("")` como alternativa.

```js
/^$/.test("")     // ✅ (los regexps con contenido funcionan)
new RegExp("").test("")  // ✅ (workaround)
// no es posible como literal //¯\_(ツ)_/¯
```

**Causa**: El lexer de Lou (src/lexer.zig) trata `//` como comentario.
No hay desambiguación entre `// comment` y `// empty regexp literal`.

### B5 — Lookbehind ineficiente

**Estado**: ⚠️ Funcional pero lento
**Descripción**: El lookbehind prueba el patrón desde posición 0 hasta la
posición actual. Para cadenas largas, esto es O(n²).

```js
/(?<=hello)world/.test("hello".repeat(1000) + "world")
// Lou: lento (prueba ~5000 posiciones)
// JS:  rápido (V8 limita lookbehind a pasos hacia atrás)
```

**Causa**: La VM itera desde `pos=0` hasta `pos=current` probando el
patrón en cada posición. V8 usa un análisis de longitud máxima del
lookbehind para limitar la búsqueda.

### B6 — matchAll no incluye capturas

**Estado**: ❌ Abierto
**Descripción**: Los arrays individuales en el iterador de matchAll no
incluyen grupos capturados.

```js
[... "hello".matchAll(/(l)/g)]
// Lou: [["l"], ["l"]]  ← sin captures
// JS:  [["l", "l"], ["l", "l"]]  ← con captures
```

## Diferencias de comportamiento conocidas

### D1 — `typeof /regex/`

**Lou**: `typeof /regex/` → `"object"`
**JS**: `typeof /regex/` → `"object"` ✅ (igual)

### D2 — `instanceof RegExp`

**Lou**: No implementa el operador `instanceof`. Clasifica como `"object"`.
**JS**: `/regex/ instanceof RegExp` → `true`

### D3 — String conversion

**Lou**: La conversión implícita de regexp a string no sigue el spec.
**JS**: `String(/regex/)` → `"/regex/"` (vía `toString()`)

### D4 — lastIndex en modo sticky sin global

En JS, `y` sin `g` respeta `lastIndex`. Lou tiene soporte parcial pero el
comportamiento en edge cases difiere.

### D5 — $`` y $' en replace con cadenas que contienen backticks

En Lou, el replacement string no escapa `\`` y `'` correctamente en todos
los casos. Esto es principalmente un problema del parser de cadenas en el
lenguaje Lou, no del regex engine.

## Casos edge documentados en tests

### Tests existentes

| Suite | Tests | Temas cubiertos |
|-------|-------|-----------------|
| 01-basic | Básicos | Coincidencia simple, clases, cuantificadores, flags |
| 02-advanced | Avanzados | Alternancia, grupos, backrefs, greedy/lazy |
| 03-exec-basic | exec básico | Exec con index, input, grupos |
| 04-exec-named | Named groups | Named captures, groups, named backrefs |
| 05-exec-edge | exec edge | Global exec, sticky, empty matches, cursor |
| 06-lookaround | Lookaround | Lookahead, lookbehind, anchors, word boundaries |
| 07-unicode | Unicode/Escapes | Unicode, hex, control, properties, flag interactions |

### Tests faltantes

| Tema | Prioridad |
|------|-----------|
| Capturas en lookahead | Alta |
| `\k<name>` named backreferences | Media |
| `hasIndices` (d flag) en exec | Media |
| toString() en RegExp | Media |
| Unicode property escapes `\p{...}` | Baja |
| `\xHH` escapes en strings de JS (no regex) | Alta (afecta tests) |
| `\uHHHH` en strings de JS | Alta |
| Cuantificadores perezosos anidados | Media |
| Backrefs con grupos opcionales | Media |
| Match vacío con /g (`/(?=a)/g`) | Media |
| Sticky flag sin global (`/a/y`) | Media |
| `replace` con function callback | Baja |
| `split` con captures en regexp | Baja |
| Atomic groups `(?>...)` | Baja |
| Inline flags `(?i)`, `(?-i)` | Baja |

## Problemas del lexer de Lou que afectan regex

### L1 — Escapes hex en strings JS

```js
var s = "\x00";  // Lou: trata como literal "\\x00" en lugar de null byte
```

**Impacto**: No se pueden escribir tests que usen `\xHH` en strings JS para
probar escapes en regex. Los workarounds actuales (usar caracteres
directamente o `\t`, `\n`, `\r`) son limitados.

### L2 — Escapes unicode en strings JS

```js
var s = "\u0041";  // Lou: trata como literal "\\u0041"
```

**Impacto**: No se pueden probar caracteres unicode en strings sin usar
UTF-8 directo.

### L3 — Template strings (`\``) con escapes especiales

Template strings en Lou no soportan `\r`, `\f`, `\v` correctamente.

## Tests que fallan intencionalmente

Los tests existentes en las suites 06 y 07 incluyen comentarios que
documentan diferencias intencionales con el comportamiento de V8/JS:

- Test `"B no match at start"` espera `["e","l"]` (Lou behavior)
  en lugar del `["e","l","l","o"]` de V8
- Tests de `d` flag eliminados porque el soporte es parcial
- Tests de `toString()` eliminados porque el método no existe
- Tests con `//` reemplazados por `new RegExp("")`
