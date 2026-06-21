# encodeURI / decodeURI / encodeURIComponent / decodeURIComponent

## status
pendiente

## Problema
Las funciones globales de codificación URI no están implementadas.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Estas funciones son necesarias para manipular URLs y query strings.

## Baseline (qué existe ya)
- `src/builtins/builtins.zig` — registro de funciones globales
- `src/builtins/properties.zig` — propiedades globales (NaN, Infinity, etc.)
- `src/builtins/string/` — manipulación de strings
- NO hay registro de encodeURI/decodeURI ni encodeURIComponent/decodeURIComponent
- Stdlib Zig: `std.Uri` puede ayudar para componentes

## Quick verify (estado actual)
```bash
echo 'console.log(encodeURIComponent("hello world"));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "encodeURIComponent is not defined"
```

## Patrones a seguir
- `src/builtins/builtins.zig` — agregar 4 nuevas funciones al registro
- `src/builtins/string/` — patrones de transformación de strings
- `src/builtins/math/abs.zig` — ejemplo de builtin function simple
- `std.fmt` para codificación manual de bytes

## Gotchas
- 4 funciones distintas pero relacionadas:
  - `encodeURI(str)` — codifica whitespace y chars no-URI-safe, MANTIENE `:/?#[]@!$&'()*+,;=`
  - `encodeURIComponent(str)` — codifica TODO excepto `A-Za-z0-9-_.!~*'()`
  - `decodeURI(str)` — inverso de encodeURI
  - `decodeURIComponent(str)` — inverso de encodeURIComponent
- Lanza `URIError` para secuencias `%XX` malformadas (no es hex válido)
- UTF-8 handling: caracteres >0x7F se codifican como múltiples `%XX` (uno por byte)
- Tabla de reserved chars para encodeURI: `;/?:@&=+$,#`
- Tabla de unreserved para encodeURIComponent: `A-Za-z0-9-_.!~*'()`
- Mantener tracking de allocaciones: `env.owned_strings.append(env.allocator, result)`
- Decoding: leer `%XX` y convertir de hex a byte, manejar UTF-8 multi-byte

## Código que falla
```js
console.log(encodeURI("hello world"));           // "hello%20world"
console.log(decodeURI("hello%20world"));          // "hello world"
console.log(encodeURIComponent("a&b=c"));         // "a%26b%3Dc"
console.log(decodeURIComponent("a%26b%3Dc"));     // "a&b=c"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Registrar las 4 funciones como globales.

### 2. Implementación
- `encodeURI(str)` — codificar URI, manteniendo caracteres especiales de URI
- `decodeURI(str)` — decodificar URI codificada
- `encodeURIComponent(str)` — codificar todo excepto letras, dígitos, `- _ . ! ~ * ' ( )`
- `decodeURIComponent(str)` — decodificar componente codificado
- Usar implementación manual de percent-encoding

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
- src/builtins/builtins.zig — registro de funciones
- src/builtins/string/ — manipulación de strings

### JS Examples Complejos
```js
// encodeURI
console.log(encodeURI("https://example.com/path?q=hello world"));
// "https://example.com/path?q=hello%20world"
console.log(encodeURI("hello/world#fragment"));
// "hello/world#fragment" (# se mantiene)
console.log(encodeURI("café"));
// "caf%C3%A9"

// decodeURI
console.log(decodeURI("https://example.com/path?q=hello%20world"));
// "https://example.com/path?q=hello world"
console.log(decodeURI("caf%C3%A9"));
// "café"

// encodeURIComponent
console.log(encodeURIComponent("a&b=c d"));
// "a%26b%3Dc%20d"
console.log(encodeURIComponent("https://example.com"));
// "https%3A%2F%2Fexample.com"
console.log(encodeURIComponent("hello/world"));
// "hello%2Fworld"

// decodeURIComponent
console.log(decodeURIComponent("a%26b%3Dc%20d"));
// "a&b=c d"

// Error handling
try {
    decodeURI("%E0%A4%A"); // URI malformada
} catch (e) {
    console.log(e instanceof URIError); // true
}

// Unicode
console.log(encodeURI("日本語"));
console.log(decodeURI(encodeURIComponent("日本語")));
```

### Verificacion
- `encodeURI` codifica espacios y caracteres especiales, pero mantiene `:/?#[]@!$&'()*+,;=`
- `encodeURIComponent` codifica TODO excepto `A-Z a-z 0-9 - _ . ! ~ * ' ( )`
- `decodeURI` y `decodeURIComponent` revierten la codificación
- Lanza `URIError` para secuencias de escape inválidas
- Maneja UTF-8 correctamente

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/encode-uri.js 2>&1 | od -c
node js/tests/encode-uri.js 2>&1 | od -c

### pendiente
- Registrar las 4 funciones como globales
- Implementar percent-encoding/decoding con soporte UTF-8

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
