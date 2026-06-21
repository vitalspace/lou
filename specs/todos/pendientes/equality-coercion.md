# Igualdad abstracta (==) vs estricta (===)

## status

NOT IMPLEMENTED

## Problema

El operador `==` se comporta idéntico a `===`. No hay coerción de tipos. Tanto el evaluador (`evaluator.zig:588-599`) como el VM (`vm.zig:786-787`) tratan ambos como comparación estricta.

## Contexto

ECMAScript define dos operadores de igualdad:
- `===` (StrictEqual): sin coerción, tipos deben coincidir
- `==` (Abstract Equality): con coerción según reglas de ECMAScript 7.2.14

## Baseline (qué existe ya)
- TokenType ya distingue `.Equal` y `.StrictEqual` (src/lexer.zig:32-35)
- `valuesEqual` (evaluator) y `valEq` (VM) YA manejan `==` — pero como strict equality (sin coerción)
- `null == undefined` falla (ver spec `null-undefined-equality.md`)
- `NaN == NaN` retorna `true` (debería ser `false`) — ver spec `nan-comparison.md`

## Quick verify (estado actual)
```bash
echo 'console.log(0 == "", 1 == true, "" == false);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "false false false" — debería ser "true true true"
```

## Patrones a seguir
- `src/evaluator.zig:588-599` — `valuesEqual` actual (referencia a modificar)
- `src/vm.zig:786-787` — dispatch de `.Equal` opcode (compila a `valEq`)
- `src/vm.zig:1617-1624` — `valEq()` actual
- ECMAScript 7.2.14 — especificación completa con 9 pasos
- `src/types/runtime.zig` — `Value` union para coercion helpers

## Gotchas
- Cambio mayor: implementar TODO el algoritmo de 7.2.14, no solo null/undefined
- Pasos del spec ECMAScript:
  1. Tipos iguales → strict eq (ya funciona)
  2. `null == undefined` → true (ver spec dedicado)
  3. `number == string` → convertir string a number
  4. `boolean == X` → convertir boolean a number (0/1) y volver a paso 1-6
  5. `object == primitive` → ToPrimitive(object) y volver
  6. `object == object` → sameValueZero (false si distintos objetos)
- NaN handling: cualquier comparación con NaN → false (también afecta `==`)
- Aplicar cambios en AMBOS lugares (evaluator Y VM) o el VM path diverge
- `null == 0` debe ser `false` — caso especial del spec que NO es coerción numérica
- Para arrays/objetos, implementar `ToPrimitive` que llama `.valueOf()` o `.toString()`

## Código que falla

```js
console.log(0 == "");        // Debería: true,  Actual: false
console.log(0 == false);     // Debería: true,  Actual: false
console.log(1 == true);      // Debería: true,  Actual: false
console.log("" == false);    // Debería: true,  Actual: false
console.log(null == undefined); // Debería: true, Actual: false
console.log(NaN == NaN);     // Debería: false, Actual: true
console.log(0 == null);      // Debería: false, Actual: false (correcto por casualidad)
```

## Implementacion sugerida

Implementar Abstract Equality Comparison (ECMAScript 7.2.14):

```
1. Si tipos son iguales → comparación estricta (ya funciona)
2. null == undefined → true
3. number == string → convertir string a number, comparar
4. boolean == any → convertir boolean a number (0/1), comparar
5. object == primitive → ToPrimitive(object), comparar
6. NaN == anything → false (siempre)
```

En `vm.zig`, crear función `abstractEq(a, b)` separada de `valEq`:
```zig
fn abstractEq(a: Value, b: Value) bool {
    // null == undefined
    if ((a == .null and b == .void) or (a == .void and b == .null)) return true;
    // same types → strict
    if (@as(ValueTag, a) == @as(ValueTag, b)) return valEq(a, b);
    // number == string → coerce string
    // boolean == any → coerce boolean to number
    // etc.
}
```

En el evaluador, lo mismo para `valuesEqual`.

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

- `src/evaluator.zig:588-599` — comparación actual
- `src/vm.zig:786-787` — compilación de Equal/StrictEqual
- `src/vm.zig:1617-1624` — `valEq()`
- ECMAScript 7.2.14 Abstract Equality Comparison

### JS Examples Complejos

```js
// Type coercion chains
console.log(0 == "");           // true
console.log(0 == "0");          // true
console.log("" == "0");         // false
console.log(false == "0");      // true
console.log(false == 0);        // true
console.log(false == "");       // true

// null/undefined
console.log(null == undefined);  // true
console.log(null == 0);          // false
console.log(null == "");         // false
console.log(undefined == 0);     // false

// Object coercion
console.log([1] == 1);          // true
console.log([] == 0);           // true
console.log([] == "");          // true
console.log([1] == "1");        // true
```

### Vereficacion

```bash
./zig-out/bin/lou run js/test-equality.js
node js/test-equality.js
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
