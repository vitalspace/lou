# 03 — String.prototype Methods con RegExp

## Visión general

Los métodos de `String.prototype` que interactúan con RegExp existen como
builtins independientes registrados en `src/builtins/string/string.zig`.

Cada método tiene dos caminos:
1. **String pattern**: Búsqueda literal (ya funciona)
2. **RegExp pattern**: Búsqueda con motor regex

## String.prototype.match

**Archivo**: `src/builtins/string/match.zig`
**Funcion**: `Match(args, env)`

### Comportamiento actual

| Escenario | Soporte |
|-----------|---------|
| `"str".match("literal")` | ✅ Búsqueda literal |
| `"str".match(/regex/)` | ✅ match sin /g (retorna array con index, input, groups) |
| `"str".match(/regex/g)` | ✅ match global con /g |
| Capturas en match sin /g | ✅ Grupos capturados como elementos del array |
| Named captures en match | ✅ groups object |
| `indices` con /d flag | ✅ Parcial (en match result) |

### Limitaciones

1. **No usa `Symbol.match`**: En JS, `match` primero invoca
   `regexp[Symbol.match](str)` si existe. Lou lo ignora.

2. **match con string vacío**: Devuelve `[""]` con index=0. En JS,
   `"".match("")` también devuelve `[""]`.

3. **match con undefined/null**: En JS, `match(undefined)` busca
   "undefined" literal. En Lou, devuelve null.

## String.prototype.matchAll

**Archivo**: `src/builtins/string/matchAll.zig`
**Funcion**: `MatchAll(args, env)`

### Comportamiento actual

| Escenario | Soporte |
|-----------|---------|
| `"str".matchAll("literal")` | ✅ Retorna iterator con match arrays |
| `"str".matchAll(/regex/)` | ✅ Retorna iterator |
| Capturas en matchAll | ⚠️ No se incluyen en los match arrays |
| Named groups | ⚠️ No se incluyen |

### Limitaciones

1. **matchAll requiere /g**: En JS, `matchAll` lanza TypeError si el regexp
   no tiene flag `g`. Lou no valida esto.

2. **Capturas y named groups**: Los arrays individuales de cada match en el
   iterador no incluyen los grupos capturados ni named captures.

## String.prototype.replace

**Archivo**: `src/builtins/string/replace.zig`
**Funcion**: `Replace(args, env)`

### Comportamiento actual

| Escenario | Soporte |
|-----------|---------|
| `"str".replace("literal", "repl")` | ✅ Primer match reemplazado |
| `"str".replace(/regex/, "repl")` | ✅ Sin /g: primer match |
| `"str".replace(/regex/g, "repl")` | ✅ Con /g: todos los matches |
| `$&` en replacement | ✅ El match completo |
| `$`` en replacement | ✅ Texto antes del match |
| `$'` en replacement | ✅ Texto después del match |
| `$1`..`$9` en replacement | ✅ Capturas numeradas |
| `$$` en replacement | ✅ $ literal |
| Replacement con function callback | ❌ NO implementado |

### Limitaciones

1. **No acepta callback como replacement**: En JS:
   ```js
   "hello".replace(/l/g, (match, offset, str) => match.toUpperCase())
   // → "heLLo"
   ```
   Lou solo acepta strings.

2. **No usa `Symbol.replace`**: En JS, el método primero chequea
   `regexp[Symbol.replace]`. Lou lo ignora.

3. **$` y $'**: Funcionan pero pueden tener bugs con cadenas multi-byte.

4. **Capturas no participantes**: En Lou se incluyen como cadenas vacías.
   En JS, se tratan como `undefined`.

## String.prototype.replaceAll

**Archivo**: `src/builtins/string/replaceAll.zig`
**Funcion**: `ReplaceAll(args, env)`

### Comportamiento actual

| Escenario | Soporte |
|-----------|---------|
| `"str".replaceAll("lit", "repl")` | ✅ Reemplaza todas ocurrencias |
| `"str".replaceAll(/regex/g, "repl")` | ✅ Requiere /g |

### Limitaciones

1. **No valida que regexp tenga /g**: En JS, `replaceAll` con regexp sin /g
   lanza TypeError. Lou no valida.

2. **No usa Symbol.replace**: Igual que Replace.

## String.prototype.search

**Archivo**: `src/builtins/string/search.zig`
**Funcion**: `Search(args, env)`

### Comportamiento actual

| Escenario | Soporte |
|-----------|---------|
| `"str".search("lit")` | ✅ Retorna índice o -1 |
| `"str".search(/regex/)` | ✅ Retorna índice o -1 |

### Limitaciones

1. **No usa `Symbol.search`**: En JS, invoca `regexp[Symbol.search](str)`.

2. **search con undefined/null**: En JS busca "undefined"/"null". Lou
   no convierte no-string a string correctamente.

## String.prototype.split

**Archivo**: `src/builtins/string/split.zig`
**Funcion**: `Split(args, env)`

### Comportamiento actual

| Escenario | Soporte |
|-----------|---------|
| `"str".split("sep")` | ✅ Split por literal |
| `"str".split("")` | ✅ Split por carácter |
| `"str".split(/regex/)` | ✅ Split por regex |
| `"str".split("sep", limit)` | ✅ Límite |
| `"str".split()` | ✅ Array con la cadena completa |
| Capturas en split con regexp | ❌ NO implementado |

### Limitaciones

1. **Capturas en split**: En JS, cuando split usa un regexp con grupos de
   captura, las capturas se incluyen en el array resultado:
   ```js
   "ab".split(/(b)/)  // → ["a", "b", ""]
   ```
   Lou no incluye las capturas.

2. **No usa `Symbol.split`**: En JS, invoca `regexp[Symbol.split](str, limit)`.

## Implementación en evaluator.zig

### Métodos de string en el evaluador

Los métodos de string se registran como builtins separados (no como
miembros de un prototipo). El evaluador busca el método en el builtin
object asociado, similar a cómo se manejan Array methods.

### String.prototype con Symbol

En JS moderno, los métodos de string que aceptan regexp deben seguir este
protocolo:

```
1. Si el argumento es un RegExp y tiene Symbol.match/replace/etc,
   invocar ese método en lugar de usar la lógica interna
2. Symbol.match → RegExp.prototype[@@match]
3. Symbol.replace → RegExp.prototype[@@replace]
4. Symbol.search → RegExp.prototype[@@search]
5. Symbol.split → RegExp.prototype[@@split]
```

Lou actualmente no implementa este protocolo y llama directamente a las
funciones auxiliares de `RegexpBuiltin`.
