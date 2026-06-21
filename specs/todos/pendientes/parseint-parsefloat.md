# parseInt y parseFloat

## status
pendiente

## Problema
Las funciones globales `parseInt()` y `parseFloat()` no están implementadas.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Estas son funciones fundamentales para convertir strings a números.

## Baseline (qué existe ya)
- `src/builtins/builtins.zig` — registro de funciones globales (`initBuiltins`)
- `src/builtins/math/` — ejemplo de builtin que recibe argumentos
- `src/builtins/number/` — Number object (referencia de coerción)
- `parseInt`/`parseFloat` NO están registradas
- `std.fmt.parseInt` y `std.fmt.parseFloat` disponibles en Zig estándar

## Quick verify (estado actual)
```bash
echo 'console.log(parseInt("42"));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: ReferenceError "parseInt is not defined"
```

## Patrones a seguir
- `src/builtins/builtins.zig` — agregar `parseInt` y `parseFloat` al map de builtins
- `src/builtins/math/` — patrón de builtin que toma argumentos
- `src/evaluator.zig:11` — `evaluateArgs` para parsing de argumentos del builtin
- ECMAScript 7.1.4 (`ToInteger`), 7.1.4.1 (`ToIntegerOrInfinity`) — semántica de radix

## Gotchas
- `parseInt(string, radix)`:
  - Si radix es undefined → 0 (auto-detect: "0x" → 16, "0" → 8, otro → 10)
  - Si radix está fuera de [2, 36] o es NaN → usar base 10 en ES5+ (lanzar error en strict)
  - Ignorar whitespace al inicio
  - Leer opcionalmente `+` o `-` para signo
  - Si empieza con `0x`/`0X` y radix es 16 o undefined → parsear hex
  - Devolver NaN si no se puede parsear nada
- `parseFloat(string)`:
  - Ignorar whitespace al inicio
  - Leer opcionalmente `+` o `-`
  - Reconocer `Infinity` (case insensitive)
  - Devolver NaN si no se puede parsear nada
- `parseInt` debe truncar floats (no redondear)
- Compat test crítico: `parseInt("0xFF", 16) === 255`, `parseInt("42px") === 42`

## Código que falla
```js
console.log(parseInt("42"));      // 42
console.log(parseInt("10", 16));  // 16
console.log(parseFloat("3.14"));  // 3.14
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Registrar `parseInt` y `parseFloat` como funciones globales en el entorno.

### 2. Implementación
- `parseInt(string, radix)` — parsear string como entero con base dada
- `parseFloat(string)` — parsear string como float
- Usar `std.fmt.parseInt` y `std.fmt.parseFloat` de Zig

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
- src/builtins/builtins.zig — registro de funciones globales
- src/environment.zig — entorno global
- src/vm.zig — opcode `builtin` para funciones globales

### JS Examples Complejos
```js
// parseInt
console.log(parseInt("42"));          // 42
console.log(parseInt("  42  "));      // 42 (ignora whitespace)
console.log(parseInt("42px"));        // 42 (para en primer no-dígito)
console.log(parseInt("0xFF", 16));    // 255
console.log(parseInt("1010", 2));     // 10 (binario)
console.log(parseInt("077", 8));      // 63 (octal)
console.log(parseInt("abc"));         // NaN
console.log(parseInt(""));            // NaN
console.log(parseInt("0xZZZ"));       // 0 (para en ZZ)

// parseFloat
console.log(parseFloat("3.14"));      // 3.14
console.log(parseFloat("  3.14  "));  // 3.14
console.log(parseFloat("3.14abc"));   // 3.14
console.log(parseFloat("3.14e2"));    // 314
console.log(parseFloat(".5"));        // 0.5
console.log(parseFloat("abc"));       // NaN
console.log(parseFloat("Infinity"));  // Infinity

// Casos edge
console.log(parseInt("  +42  "));     // 42
console.log(parseInt("  -42  "));     // -42
console.log(parseInt("0x1G", 16));    // 1
console.log(parseInt("0o77", 8));     // 0 (prefijo 0o no soportado sin base)

// Radix 36
console.log(parseInt("zz", 36));      // 1295
```

### Verificacion
- `parseInt("42")` retorna 42
- `parseInt("10", 16)` retorna 16
- `parseInt` ignora whitespace al inicio
- `parseInt` para en el primer carácter no válido
- `parseInt` retorna NaN para strings inválidos
- `parseFloat("3.14")` retorna 3.14
- `parseFloat` soporta notación científica

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/parseint.js 2>&1 | od -c
node js/tests/parseint.js 2>&1 | od -c

### pendiente
- Registrar parseInt y parseFloat como funciones globales
- Implementar la lógica de parsing con radix

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
