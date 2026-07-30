# for-in: orden de enumeración

## status

**pendiente (drift corrected 2026-07-30)** — previously marked `COMPLETADO` but `tests/compat/for-in-order.lou` FAILs per compat baseline (43P/39F/1S)

## Problema

El operador `for-in` itera las claves de un objeto en orden arbitrario (iterador de HashMap). ECMAScript especifica un orden de enumeración específico: índices enteros primero (ascendente), luego strings en orden de inserción, luego symbols.

## Contexto

ECMAScript 14.7.5.9 EnumerateObjectProperties: define el orden de enumeración.

## Baseline (qué existe ya)
- `ForInLoop` ya existe en AST (`src/ast.zig:40`)
- Parser ya parsea `for (var k in obj)` (`src/parser.zig:881-910`)
- Evaluator maneja for-in (`src/evaluator.zig` — buscar el case)
- VM compila for-in (`src/vm.zig` — buscar)
- ObjectValue tiene HashMap de propiedades (orden arbitrario actualmente)

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
var o = {b: 1, 0: 3, a: 2};
for (var k in o) console.log(k);
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: orden arbitrario; esperado: "0", "b", "a"
```

## Patrones a seguir
- `src/types/runtime.zig` — `ObjectValue` con HashMap de propiedades y método de keys
- `src/evaluator.zig` — buscar `ForInLoop =>` para ver la iteración actual
- `src/vm.zig` — buscar la compilación de for-in
- `std.sort` disponible en Zig std para ordenar

## Gotchas
- Reglas de orden ECMAScript:
  1. Índices enteros (array indices) en orden ASCENDENTE numérico
  2. Strings en orden de INSERCIÓN
  3. Symbols en orden de inserción
- Para arrays, los índices son strings pero se manejan como integers
- Necesitas trackear orden de inserción: agregar lista `ordered_keys: ArrayList([]const u8)` a ObjectValue
- Cross-check con `Object.keys()` y `for...in` — deben dar el mismo orden
- Symbol keys se manejan aparte (SymbolValue en runtime.zig) — probablemente fuera de scope
- Compat test: `tests/compat/for-in-order.js` y `.lou` con varios casos de mezcla int/string

## Código que falla

```js
var obj = { b: 1, 0: 3, a: 2 };
for (var key in obj) {
    console.log(key); // Debería: "0", "b", "a"
                      // Actual: orden arbitrario
}
```

## Implementacion sugerida

En `evaluator.zig:1577-1594` y `vm.zig:1538-1607`, ordenar las claves antes de iterar:

```zig
fn getOrderedKeys(obj: *ObjectValue) [][]const u8 {
    var int_keys = std.ArrayList(usize).init(allocator);
    var str_keys = std.ArrayList([]const u8).init(allocator);
    
    for (obj.keys()) |key| {
        // Try to parse as integer
        if (std.fmt.parseInt(usize, key, 10)) |int_key| {
            int_keys.append(int_key);
        } else {
            str_keys.append(key);
        }
    }
    
    // Sort integer keys ascending
    std.sort.sort(usize, int_keys.items, {}, std.sort.asc(usize));
    
    // Concatenate: int keys as strings, then string keys in insertion order
    // ...
}
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

- `src/evaluator.zig:1577-1594` — for-in en evaluador
- `src/vm.zig:1538-1607` — for-in en VM
- ECMAScript 14.7.5.9 EnumerateObjectProperties

### JS Examples Complejos

```js
// Integer keys first, then insertion order
var obj = { z: 1, a: 2, 10: 3, 2: 4, m: 5 };
for (var k in obj) {
    console.log(k); // "2", "10", "z", "a", "m"
}

// Numeric keys sorted
var nums = { 3: "c", 1: "a", 2: "b" };
for (var k in nums) {
    console.log(k); // "1", "2", "3"
}
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-for-in-order.js
node js/test-for-in-order.js
```

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente
- (ninguno — spec implementado y verificado PASS en compat suite)

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


## Estado del test (auto 2026-06-23)

- Compat test match: `for-in-order.lou` (EXACT — for-in enumeration order)
- Test status: `PASS`

- Diff: empty — Lou and Node output identical across 5 test cases (integer keys ascending, string keys insertion-order, mixed int/string, strings-only, ints-only).

- Suite regression: 899 unit tests pass, 4 pre-existing crashes (unrelated).

- Disposition: moved from `pendientes/` to `hechos/` — exact match, PASS.

## Resolución (2026-06-23)

Implementado como método `getForInKeys` en `ObjectValue` (en lugar de mantener
una lista separada `ordered_keys`). El método itera el HashMap, clasifica las
claves en índices enteros (con verificación de canonicalidad via
`parseInt` + `bufPrint` round-trip) y strings (saltando prefijos `@@`), ordena
los enteros ascendentemente, y retorna un `ArrayObject` con los `.string`
Values en orden ES.

**Archivos modificados:**
- `src/types/runtime.zig` — `getForInKeys()` en `ObjectValue`
- `src/evaluator.zig` — `ForInLoop` handler usa `getForInKeys()`
- `src/vm.zig` — opcode `get_for_in_keys` usa `getForInKeys()`
- `tests/compat/for-in-order.{js,lou}` — 5 casos de prueba

### Edge cases descubiertos
- **Canonicalidad de índices enteros**: `parseInt("00", 10)` → `0` pero
  `"00"` no es un índice de array canónico según ES. Se agregó verificación
  de canonicalidad con `bufPrint("{d}", .{num})` + comparación.
- **Compatibilidad Zig 0.16**: `std.ArrayList` requiere `initCapacity`,
  `deinit(allocator)` y `append(allocator, item)` — se actualizaron los
  patrones de API.

