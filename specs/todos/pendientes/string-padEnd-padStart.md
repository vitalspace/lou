# String.prototype.padEnd() y padStart()

## status

❌ PENDIENTE

## Problema

Lou no soporta los métodos `String.prototype.padEnd()` ni `padStart()`.

## Contexto

**Prioridad: baja**

Ambas funciones requieren crear nuevos archivos builtin siguiendo el patrón existente de `src/builtins/string/`.

## Baseline (qué existe ya)
- `String` YA implementado (`src/builtins/string/`)
- STRING_OBJECT registrado (`src/builtins/builtinObjects.zig`)
- Patrón: un archivo `.zig` por método (`src/builtins/math/abs.zig` como template)
- Faltan: padEnd, padStart

## Quick verify (estado actual)
```bash
echo 'console.log("hi".padEnd(5));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "padEnd is not a function"
```

## Patrones a seguir
- `src/builtins/string/` — métodos existentes como template
- `src/builtins/math/abs.zig` — patrón de builtin method
- `src/builtins/string/string.zig` — registro de STRING_METHODS
- ECMAScript 22.1.3.16, 22.1.3.17 — padEnd, padStart

## Gotchas
- Spec TRIVIAL: 2 métodos simétricos
- `padEnd(targetLength, padString = " ")`: si str.length >= targetLength, retorna str; sino rellena al final
- `padString` se trunca si es más largo que el padding necesario (NO se duplica más de una vez)
- Para `targetLength <= str.length`: retorna str sin cambios
- Si `padString` está vacío o no se especifica: usa `" "` (espacio)
- Si targetLength es 0 o negativo: retorna str sin cambios
- Coerción: targetLength se convierte a entero truncado (no redondea)
- Strings resultantes deben allocarse con `env.allocator` y tracked en `env.owned_strings`
- Compat test: `tests/compat/string-pad.js` y `.lou` con varios casos

## Código que falla

```js
var s = "Token";

console.log(s.padEnd(7, " "));
```

Error: padEnd is not a function

## Implementacion sugerida

### Firmas ECMAScript

```ts
str.padEnd(targetLength: number, padString?: string): string
str.padStart(targetLength: number, padString?: string): string
```

### Comportamiento

- `padEnd(targetLength)`: Si `str.length >= targetLength`, retorna `str`. Si no, rellena al final hasta alcanzar `targetLength` con espacios (o `padString`).
- `padStart(targetLength)`: Igual pero rellena al inicio.

### Pasos de implementación

1. Crear `src/builtins/string/padEnd.zig`
2. Crear `src/builtins/string/padStart.zig`
3. Modificar `src/builtins/string/string.zig` para registrar los métodos
4. Agregar tests en `js/test-string-pad.js`

## Tests

Añadir un test de compatibilidad en `tests/compat/`. El runner (`tests/compat/run.sh`) compara el output de Lou contra el de Node y solo marca PASS si ambos exit code y stdout normalizado son idénticos.

### Convención de archivos

- `tests/compat/<nombre>.js` — referencia canónica. Debe ejecutarse con `node` y producir el output esperado.
- `tests/compat/<nombre>.lou` — el mismo programa escrito para Lou. Debe producir output idéntico a la versión `.js`.
- Si el spec cubre sintaxis **específica de Lou** (no existente en JS, e.g. `function f() expr` como expression body, `..` range, `match`), omitir el `.js` y dejar solo el `.lou` — el runner marcará SKIP automáticamente.

### Verificación local

```bash
# 1. Lou produce el output esperado
./zig-out/bin/lou run tests/compat/<nombre>.lou

# 2. Node produce el output esperado (si hay .js)
node tests/compat/<nombre>.js

# 3. Diff (debe ser vacío)
diff <(./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1) \
     <(node tests/compat/<nombre>.js 2>&1)

# 4. Correr toda la suite
bash tests/compat/run.sh
```

### Tests unitarios (parser/lexer/evaluator)

Además del compat test, añadir tests unitarios en el archivo `.zig` correspondiente (`src/parser.zig`, `src/lexer.zig`, `src/evaluator.zig`, etc.) que verifiquen la estructura del AST o el comportamiento del lexer/evaluator para casos individuales. Los unit tests son útiles para casos donde el compat test sería demasiado grande o donde queremos verificar la forma exacta del AST.

## Archivos de referencia

- `specs/strings/` — specs de strings existentes
- `src/builtins/string/` — builtins de string existentes como patrón
- ECMAScript spec: `String.prototype.padEnd` y `padStart`

### JS Examples

```js
"Token".padEnd(7)      // "Token  "
"Token".padEnd(10, ".") // "Token...."
"Token".padEnd(4)       // "Token"
"x".padStart(3, "0")    // "00x"
"123".padStart(6, "0")  // "000123"
"abc".padStart(3)       // "abc"
"abc".padStart(3, "x")  // "abc"
```

### Vereficacion

```js
console.log("Token".padEnd(7));
console.log("Token".padEnd(10, "."));
console.log("Token".padEnd(4));
console.log("x".padStart(3, "0"));
console.log("123".padStart(6, "0"));
console.log("abc".padStart(3));
console.log("abc".padStart(3, "x"));
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente

- [ ] Crear `src/builtins/string/padEnd.zig`
- [ ] Crear `src/builtins/string/padStart.zig`
- [ ] Modificar `src/builtins/string/string.zig` para registrar métodos
- [ ] Agregar tests en `js/test-string-pad.js`
- [ ] Verificación con `od -c` vs Node.js

## Edge cases encontrados durante implementación

Listar aquí los bugs, comportamientos inesperados o requisitos descubiertos
mientras se implementaba este spec. Cada edge case debe ser promovido a su
propio spec (usando esta misma plantilla) si requiere cambios de diseño
propios, o documentado inline si es un fix puntual.

Ejemplos de edge cases típicos:
- Comportamiento cuando se mezcla el tipo con primitivos incompatibles
  (TypeError vs coerción silenciosa).
- Formato de impresión / `toString` — sufijo, base, mayúsculas.
- Comparación loose vs strict.
- Conversión a otros tipos (string concat, Number, BigInt).
- División por cero, exponente negativo, overflow.
- Capturabilidad del error por `try/catch` JS (no abortar el proceso).

Plantilla para promover un edge case a spec:
1. Crear `specs/todos/pendientes/<spec>-edge-<caso>.md` siguiendo esta plantilla.
2. Enlazar desde este spec principal con un enlace relativo.
3. Verificar que el test correspondiente cubre el caso.
