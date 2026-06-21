# Map.groupBy y Object.groupBy

## status
pendiente

## Problema
`Map.groupBy()` y `Object.groupBy()` (ES2024) no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Estos métodos agrupan elementos de un iterable según una función de callback.

## Baseline (qué existe ya)
- `Map` YA está implementado (`src/builtins/map/`)
- `Object` builtin (`src/builtins/object/`) — pero `Object.groupBy` no
- `Array` builtin (`src/builtins/array/`)
- Callbacks en builtins: revisar patrón de `Array.prototype.map`/`filter` que ya existen
- Faltan: `Map.groupBy` y `Object.groupBy` (ES2024)

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
const items = [{type: "a"}, {type: "b"}, {type: "a"}];
const g = Map.groupBy(items, i => i.type);
console.log(g.get("a").length);
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "Map.groupBy is not a function"
```

## Patrones a seguir
- `src/builtins/map/` — Map builtin; agregar método groupBy al array de métodos
- `src/builtins/object/` — Object builtin; agregar `groupBy`
- `src/builtins/array/` — patrón de métodos como `Array.prototype.map`
- `src/builtins/math/abs.zig` — patrón de builtin method individual
- `src/builtins/builtinObjects.zig` — MAP_OBJECT y OBJECT_OBJECT ya registrados

## Gotchas
- ES2024 feature — verificar versión target
- `Map.groupBy(items, callback)`:
  1. Crear nuevo Map
  2. Para cada item en items, llamar callback(item, index) — el index es opcional en JS
  3. Si resultado es `undefined` o `null`, NO incluir el item
  4. Si el key ya existe en Map, append al array; sino crear nuevo array
  5. Retornar Map
- `Object.groupBy(items, callback)`:
  - Similar pero usa Object (js_object) como contenedor
  - Claves que son símbolos se preservan; resto se coerce a string (property key)
- Callback se invoca con `(item, index)` (índice opcional según spec)
- Cross-check con `iterator-protocol.md` — `items` puede ser cualquier iterable
- Si el callback lanza, propagar el error

## Código que falla
```js
const items = [
    { name: "apple", type: "fruit" },
    { name: "carrot", type: "vegetable" },
    { name: "banana", type: "fruit" },
];

const grouped = Map.groupBy(items, item => item.type);
console.log(grouped.get("fruit").length); // 2
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
- `Map.groupBy(items, callbackFn)` — agrupar en Map
- `Object.groupBy(items, callbackFn)` — agrupar en Object (claves deben ser strings/symbols)

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
- src/builtins/map/ — implementación de Map
- src/builtins/object/ — implementación de Object
- src/builtins/array/ — implementación de Array

### JS Examples Complejos
```js
// Map.groupBy
const inventory = [
    { name: "asparagus", type: "vegetables" },
    { name: "bananas", type: "fruit" },
    { name: "goat", type: "meat" },
    { name: "cherries", type: "fruit" },
    { name: "fish", type: "meat" },
];

const restock = Map.groupBy(inventory, ({ type }) => type);
console.log(restock.get("fruit").length);   // 2
console.log(restock.get("meat").length);    // 2
console.log(restock.get("vegetables").length); // 1

// Object.groupBy
const students = [
    { name: "Alice", grade: "A" },
    { name: "Bob", grade: "B" },
    { name: "Charlie", grade: "A" },
    { name: "Diana", grade: "C" },
];

const byGrade = Object.groupBy(students, s => s.grade);
console.log(byGrade.A.length); // 2
console.log(byGrade.B.length); // 1

// Con función que retorna undefined (excluidos)
const data = [1, 2, 3, 4, 5, 6];
const evenOdd = Map.groupBy(data, n => {
    if (n % 2 === 0) return "even";
    if (n % 2 !== 0) return "odd";
    return undefined; // excluido
});
console.log(evenOdd.get("even")); // [2, 4, 6]
console.log(evenOdd.get("odd"));  // [1, 3, 5]

// Agrupar por condición
const people = [
    { name: "Alice", age: 25 },
    { name: "Bob", age: 17 },
    { name: "Charlie", age: 30 },
    { name: "Diana", age: 15 },
];
const adults = Object.groupBy(people, p => p.age >= 18 ? "adult" : "minor");
```

### Verificacion
- `Map.groupBy(iterable, fn)` retorna Map con grupos
- `Object.groupBy(iterable, fn)` retorna Object con grupos
- Callback retorna la clave de agrupación
- Elementos con misma clave se agrupan en array
- `undefined` como clave excluye el elemento

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/groupby.js 2>&1 | od -c
node js/tests/groupby.js 2>&1 | od -c

### pendiente
- Implementar Map.groupBy y Object.groupBy

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
