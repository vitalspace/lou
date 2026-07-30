# Operadores ++ y --

## status

NOT IMPLEMENTED

## Problema

Los operadores `++` y `--` son parseados por el lexer (TokenType `Increment` y `Decrement`) pero nunca evaluados. No hay implementación en el evaluador ni en el VM.

## Contexto

ECMAScript define `++` y `--` como UpdateExpression:
- `x++` (post-increment): retorna valor anterior, luego incrementa
- `++x` (pre-increment): incrementa, retorna nuevo valor
- `x--` (post-decrement): retorna valor anterior, luego decrementa
- `--x` (pre-decrement): decrementa, retorna nuevo valor

## Baseline (qué existe ya)
- Lexer YA tiene tokens `.Increment` y `.Decrement` (`src/lexer.zig:16-17`)
- Lexer YA tokeniza `++`/`--` (`src/lexer.zig:155-174`)
- AST NO tiene `UpdateExpression` node
- Parser NO lo maneja como expression
- Evaluator NO lo evalúa

## Quick verify (estado actual)
```bash
echo 'var x = 5; x++; console.log(x);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: error de parseo (++x no es expression válida) o x se queda en 5
```

## Patrones a seguir
- `src/lexer.zig:16-17` — tokens Increment/Decrement (ya existen)
- `src/lexer.zig:155-174` — tokenización (ya existe)
- `src/ast.zig:101-105` — `BinaryExpression` como template de expression operator
- `src/ast.zig:243-245` — `TypeOfExpression` (unary, no assignment)
- `src/parser.zig:293` — `parsePrecedece` (punto de inserción)
- `src/evaluator.zig` — buscar dónde se manejan assignments simples
- `src/environment.zig:228-241` — `setVar` para asignar nuevo valor
- `src/environment.zig:174-184` — `setFunction` (similar pattern)

## Gotchas
- Prefix vs postfix: postfix retorna OLD value, prefix retorna NEW value
- Side effect: la variable SIEMPRE se modifica, sin importar el retorno
- Para variables: lookup, modificar, set
- Para member access (`obj.x++`): lookup, modificar, set
- Solo funciona en variables (no en expresiones arbitrarias como `5++`)
- Coerción: resultado siempre es número (increment de string `s` da NaN)
- BigInt: `1n++` debe funcionar pero mantener tipo BigInt
- Si creas `UpdateExpression` AST node, actualizar freeAst, printAst, evaluator switch
- Cross-check con `update-expression.md` (spec duplicado)
- VM: probablemente necesite opcodes nuevos (o desugar a existing compound assign)

## Código que falla

```js
var x = 5;
x++;           // Debería: x = 6, retorna 5
console.log(x); // Debería: 6

var y = 10;
++y;           // Debería: y = 11, retorna 11
console.log(y); // Debería: 11

var z = 3;
z--;           // Debería: z = 2, retorna 3
--z;           // Debería: z = 1, retorna 1
```

## Implementacion sugerida

1. En el parser, detectar `++`/`--` como `UpdateExpression`:
   - Prefijo: `++x` — parsear como `UpdateExpression(++, x, prefix=true)`
   - Sufijo: `x++` — parsear como `UpdateExpression(++, x, prefix=false)`

2. En el evaluador, evaluar `UpdateExpression`:
   - Obtener valor actual de la variable
   - Verificar que es un número
   - Aplicar incremento/decremento
   - Asignar nuevo valor a la variable
   - Retornar valor anterior (postfix) o nuevo (prefix)

3. En el VM, emitir opcodes `Increment`/`Decrement` con modo pre/post.

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

- `src/lexer.zig:153-173` — tokenización de `++`/`--`
- `src/parser.zig` — parsing (no hay UpdateExpression actualmente)
- ECMAScript 13.5 Update Expressions

### JS Examples Complejos

```js
// Loop counters
for (var i = 0; i < 10; i++) {
    console.log(i);
}

// Post-increment in expression
var a = 5;
var b = a++; // b = 5, a = 6

// Pre-increment in expression
var c = 5;
var d = ++c; // d = 6, c = 6

// Chained
var x = 0;
console.log(x++ + ++x); // 0 + 2 = 2
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-increment-decrement.js
node js/test-increment-decrement.js
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- [ ] *(Pendiente: detallar los pasos concretos de implementación derivados de las secciones anteriores.)*

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


## Estado del test (auto 2026-06-22)

- Compat test match: `bigint-increment-decrement.lou` (FUZZY — decrement increment)
- Test status: `PASS`

- Disposition: test PASSES — but stays in pendientes/ because match is FUZZY on tokens; verify spec scope matches the test (manual confirmation required before move).

