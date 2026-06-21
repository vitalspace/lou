# JSON.parse

## status
pendiente

## Problema
`JSON.stringify` está implementado pero `JSON.parse` no.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `JSON.parse` es esencial para leer datos JSON.

## Baseline (qué existe ya)
- `JSON.stringify` YA está implementado (`src/builtins/json/stringify.zig`)
- `JSON_OBJECT` registrado en `src/builtins/json/json.zig`
- Falta agregar método `parse` al `JSON_METHODS` array
- ObjectValue y ArrayObject ya existen en `src/types/runtime.zig`

## Quick verify (estado actual)
```bash
echo 'const o = JSON.parse("{\"x\":1}"); console.log(o.x);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "JSON.parse is not a function"
```

## Patrones a seguir
- `src/builtins/json/stringify.zig` — patrón de método builtin
- `src/builtins/json/json.zig` — registro del método
- `src/builtins/builtinObjects.zig` — JSON_OBJECT ya registrado
- `src/types/runtime.zig` — `ObjectValue`, `ArrayObject`, `Value` constructors
- ECMAScript 24.5.1 `JSON.parse` — especificación completa

## Gotchas
- Crear archivo `src/builtins/json/parse.zig` con la función `Parse(args, env)`
- Agregar a `JSON_METHODS` array en `src/builtins/json/json.zig`
- JSON grammar: `{...}`, `[...]`, string, number, true, false, null — implementar state machine o recursive descent
- Ignorar whitespace entre tokens
- Strings JSON admiten `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX` (NO `\u{...}`)
- Numbers: signo opcional, integer part, decimal opcional, exponente opcional
- Strings resultantes deben allocarse con `env.allocator` y tracked en `env.owned_strings`
- Lanzar `SyntaxError` para input inválido — usar error return de Zig
- Soporte opcional de `reviver`: aplicar función a cada key:value después de parsear
- Distinguir integers vs floats al parsear: `42` → integer, `42.0` → float, `42e0` → float
- ObjectValue debe tener keys en orden de aparición (importante para `JSON.stringify` después)

## Código que falla
```js
const obj = JSON.parse('{"name":"Alice","age":30}');
console.log(obj.name); // "Alice"
```

## Implementacion sugerida

### 1. Builtin (src/builtins/json/)
Agregar `JSON.parse` al módulo JSON existente:
- Parsear string JSON a Value de Lou
- Soportar: objetos, arrays, strings, números, booleanos, null
- Lanzar `SyntaxError` para JSON inválido

### 2. Opcional: replacer/reviver
- `JSON.parse(text, reviver)` — función de transformación

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
- src/builtins/json/ — implementación actual de JSON.stringify
- src/types/runtime.zig — Value union, ObjectValue, ArrayObject

### JS Examples Complejos
```js
// Básico
console.log(JSON.parse('42'));           // 42
console.log(JSON.parse('"hello"'));      // "hello"
console.log(JSON.parse('true'));         // true
console.log(JSON.parse('null'));         // null
console.log(JSON.parse('[1,2,3]'));      // [1, 2, 3]
console.log(JSON.parse('{"a":1,"b":2}')); // {a: 1, b: 2}

// Anidado
const complex = JSON.parse('{"arr":[1,{"nested":true}],"str":"text"}');
console.log(complex.arr[1].nested); // true

// Números
console.log(JSON.parse('0'));            // 0
console.log(JSON.parse('-1.5'));         // -1.5
console.log(JSON.parse('1e10'));         // 10000000000
console.log(JSON.parse('1.23e-4'));      // 0.000123

// String con escapes
console.log(JSON.parse('"hello\\nworld"')); // "hello\nworld"
console.log(JSON.parse('"hello\\"world"')); // "hello\"world"
console.log(JSON.parse('"\\u0041"'));       // "A"

// Reviver
const result = JSON.parse('{"a":1,"b":2}', (key, value) => {
    if (typeof value === "number") return value * 2;
    return value;
});
console.log(result.a); // 2

// Error handling
try {
    JSON.parse('{invalid}');
} catch (e) {
    console.log(e instanceof SyntaxError); // true
}

// Whitespace
console.log(JSON.parse('  {  "a" : 1  }  ')); // {a: 1}
```

### Verificacion
- Parsea todos los tipos JSON: objetos, arrays, strings, números, booleanos, null
- Maneja números con signo, exponentes, decimales
- Maneja secuencias de escape en strings
- Lanza `SyntaxError` para JSON inválido
- Ignora whitespace
- Reviver transforma valores durante el parsing

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/json-parse.js 2>&1 | od -c
node js/tests/json-parse.js 2>&1 | od -c

### pendiente
- Implementar JSON.parse en src/builtins/json/
- Parser JSON completo con manejo de errores

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
