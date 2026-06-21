# Operador de exponenciación (**)

## status
pendiente

## Problema
El operador `**` (exponenciación) y `**=` (asignación de exponenciación) no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. ES2016 agregó el operador `**` como alternativa a `Math.pow()`.

## Baseline (qué existe ya)
- TokenType NO tiene `Power` ni `PowerAssign` (ver enum `src/lexer.zig:11-50`)
- Lexer NO tiene handler para `*` que considere `**` o `**=`
- Evaluator maneja `Multiply` y `Divide` como `BinaryExpression`, NO hay exponenciación
- `std.math.pow` disponible en Zig estándar

## Quick verify (estado actual)
```bash
echo 'console.log(2 ** 3);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error o resultado incorrecto (probablemente evalúa como 2 * *3)
```

## Patrones a seguir
- `src/lexer.zig:11-50` — enum `TokenType`; agregar `Power` y `PowerAssign` siguiendo convención
- `src/lexer.zig:175-190` — handler de `*` para división/multiplicación como referencia para construir handler de `**`
- `src/lexer.zig:155-175` — handler de `+` con `PlusAssign` como ejemplo de compound assign
- `src/parser.zig:293` — `parsePrecedece`; agregar precedencia (mayor que `*`, asociativo derecha — recursivo en lugar de loop)
- `src/parser.zig:770-830` — `parseAssignment` para agregar rama de `**=`
- `src/evaluator.zig:380-450` — switch sobre `BinaryExpression.operator`; agregar caso `.Power` con `@pow(comptime_float, comptime_float)`

## Gotchas
- `**` es asociativo a la DERECHA: `2 ** 3 ** 2 = 2 ** 9 = 512`. En `parsePrecedece` se logra haciendo la recursión sobre `right` con la misma precedencia
- Precedencia mayor que `*` y `/`, pero menor que unarios (`-2 ** 2` es ambiguo en JS, `-4` en algunos engines)
- `NaN ** 0 = 1`, `1 ** NaN = NaN`, `0 ** 0 = 1` (convención JS)
- `2 ** -1 = 0.5` (exponente negativo retorna float)
- `-2 ** 2` es SyntaxError en JS estricto — pero el spec dice "implementation-defined" en sloppy mode. Mejor lanzar error
- Para `**=`, similar a `*=` pero llamar `pow` en vez de `mul`
- Si agregás AST no hace falta (es BinaryExpression nuevo operador); pero SÍ hay que actualizar todos los switches sobre `BinaryExpression.operator`

## Código que falla
```js
console.log(2 ** 3);  // 8
console.log(10 ** 2); // 100

let x = 2;
x **= 3;
console.log(x); // 8
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar tokens: `Power` (`**`), `PowerAssign` (`**=`)

### 2. Parser (src/parser.zig)
- En `parseExpression()`, agregar `**` con precedencia correcta (mayor que multiplicación, asociativo a la derecha)
- En `parseAssignment()`, manejar `**=`

### 3. VM (src/vm.zig)
- Opcode `pow` — calcular base^exponente
- Usar `@pow()` de Zig o implementación manual

### 4. Evaluator (src/evaluator.zig)
- En `evaluateBinaryExpression()`, caso `Power` — calcular potencia

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
- src/lexer.zig — tokens de operadores
- src/parser.zig — precedencia de operadores
- src/vm.zig — Op enum, operaciones aritméticas

### JS Examples Complejos
```js
// Básico
console.log(2 ** 10);   // 1024
console.log(3 ** 3);    // 27
console.log(10 ** 0);   // 1
console.log(0 ** 0);    // 1 (definido en JS)

// Negativo
console.log(2 ** -1);   // 0.5
console.log(4 ** -0.5); // 0.5

// Float
console.log(2.5 ** 2);  // 6.25

// Asignación
let a = 5;
a **= 2;
console.log(a); // 25

a **= 0.5;
console.log(a); // 5

// Encadenado (asociativo a la derecha)
console.log(2 ** 3 ** 2); // 512 (2 ** (3 ** 2) = 2 ** 9)

// Con variables
const base = 2;
const exp = 8;
console.log(base ** exp); // 256

// NaN e Infinity
console.log(NaN ** 2);    // NaN
console.log(Infinity ** 0); // 1
```

### Verificacion
- `**` calcula la potencia correctamente
- `**=` modifica la variable in-place
- Asociatividad derecha: `2 ** 3 ** 2` = `2 ** 9` = 512
- Maneja NaN, Infinity, negativos correctamente
- `0 ** 0` = 1

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/exponentiation.js 2>&1 | od -c
node js/tests/exponentiation.js 2>&1 | od -c

### pendiente
- Implementar tokens, precedencia, VM opcode y evaluator para **

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
