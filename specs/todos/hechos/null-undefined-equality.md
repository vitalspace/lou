# null == undefined debe retornar true

## status

NOT IMPLEMENTED

## Problema

`null == undefined` retorna `false`. ECMAScript 7.2.14 especifica que `null == undefined` debe ser `true`. Esto es un caso especial de la igualdad abstracta.

## Contexto

ECMAScript 7.2.14 Abstract Equality, paso 2:
> If x is null and y is undefined, return true.
> If x is undefined and y is null, return true.

## Baseline (qué existe ya)
- `valuesEqual` existe en evaluator (`src/evaluator.zig` — buscar la función)
- `valEq` existe en VM (`src/vm.zig` — buscar la función)
- Ambos tratan `void` y `null` como tipos distintos — falla el caso `null == undefined`
- TokenType `.Equal` ya existe (operador `==`)

## Quick verify (estado actual)
```bash
echo 'console.log(null == undefined);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "false" — debería ser "true"
```

## Patrones a seguir
- `src/evaluator.zig` — buscar `valuesEqual` o `pub fn valuesEqual` — el switch sobre tipos está allí
- `src/vm.zig` — buscar `valEq` o `pub fn valEq` — la versión optimizada del VM
- Ambos archivos tienen lógica duplicada que debe mantenerse en sync

## Gotchas
- Cambio DEBE aplicarse en AMBOS lugares: evaluator (`valuesEqual`) Y VM (`valEq`) — sino solo uno de los paths funcionará
- Solo afecta `==` (`.Equal`), NO `===` (`.StrictEqual`) — `null === undefined` debe seguir siendo `false`
- Cambio muy simple (1-2 líneas) — pero crítico hacerlo bien en ambos archivos
- Verificar que `void == null` y `null == void` ambos retornan `true` (simetría)
- Compat test: `tests/compat/null-undefined-eq.js` + `.lou`

## Código que falla

```js
console.log(null == undefined);    // Debería: true,  Actual: false
console.log(undefined == null);    // Debería: true,  Actual: false
console.log(null == null);         // Debería: true,  Actual: true
console.log(undefined == undefined); // Debería: true, Actual: true
console.log(null === undefined);   // Debería: false, Actual: false (correcto)
```

## Implementacion sugerida

En `evaluator.zig:115-116`:
```zig
// Antes:
void => right == .void,
null => right == .null,

// Después (combinar null y undefined):
void => right == .void or right == .null,
null => right == .null or right == .void,
```

En `vm.zig:1617-1624` (`valEq`):
```zig
// Add before the type comparison:
if ((a == .null and b == .void) or (a == .void and b == .null)) return true;
```

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

- `src/evaluator.zig:115-116` — `valuesEqual` null/void cases
- `src/vm.zig:1617-1624` — `valEq()`
- ECMAScript 7.2.14 Abstract Equality Comparison

### JS Examples Complejos

```js
// Common pattern: check for null or undefined
function getLength(s) {
    if (s == null) {  // should match both null and undefined
        return 0;
    }
    return s.length;
}

console.log(getLength(null));      // 0
console.log(getLength(undefined)); // 0
console.log(getLength("hello"));  // 5
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-null-undefined.js
node js/test-null-undefined.js
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

- Compat test match: `-` (NO-MATCH)
- Test status: `-`

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/null-undefined-equality.lou + tests/compat/null-undefined-equality.js to enable automatic PASS/FAIL tracking.

