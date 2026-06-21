# Operador delete

## status
pendiente

## Problema
El operador `delete` no está implementado. No se pueden eliminar propiedades de objetos ni elementos de arrays.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `delete` es un operador fundamental para manipular objetos.

## Baseline (qué existe ya)
- Lexer NO tiene keyword `Delete` (`src/lexer.zig:3-113`)
- AST NO tiene `DeleteExpression`
- `ObjectValue` tiene HashMap de propiedades (`src/types/runtime.zig`)
- `ArrayObject` tiene ArrayList de elementos con holes (`src/types/runtime.zig`)
- Builtins object tiene helpers de manipulación (`src/builtins/object/`)

## Quick verify (estado actual)
```bash
echo 'const o = {a:1}; delete o.a; console.log(o);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (`delete` no es keyword)
```

## Patrones a seguir
- `src/lexer.zig:74-95` — keywords; agregar `Delete` siguiendo el patrón
- `src/lexer.zig:442-460` — `getKeywordType` para mapear literal `"delete"`
- `src/ast.zig:243-245` — `TypeOfExpression` como template de operador unario
- `src/parser.zig` — buscar donde se parsea `!expr` y agregar `delete expr`
- `src/evaluator.zig` — buscar `MemberAccess =>` y `ArrayIndex =>` para entender la lógica
- `src/environment.zig:228-241` — `setVar` con su walk-up a function scope

## Gotchas
- `delete obj.prop` retorna `true` siempre (incluso si la propiedad no existía)
- `delete arr[1]` crea un "hole" en el array (`.hole` variant en Value ya existe) — el array NO se reindexa
- `delete variable` (sin member access) retorna `false` en strict mode (SyntaxError); `true` en sloppy. Implementación mínima: aceptar `delete ident` y retornar `true`
- `delete x` donde `x` es `const`/`let` debe retornar `false` (o lanzar en strict)
- Cross-check con `in-operator.md` — `"x" in obj` debe reflejar la eliminación
- Si añadís AST node nuevo (`DeleteExpression`), actualizar `freeAst` (~line 800), `printAst` (~line 470), y switch en evaluator (~line 187)
- Para member access el evaluador necesita hacer el `findEnv`-style walk-up si la prop pertenece a un objeto en scope superior

## Código que falla
```js
const obj = { a: 1, b: 2, c: 3 };
delete obj.b;
console.log(obj); // { a: 1, c: 3 }

const arr = [1, 2, 3];
delete arr[1];
console.log(arr); // [1, empty, 3]
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keyword: `Delete`

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `DeleteExpression` — `delete obj.prop` o `delete arr[i]`

### 3. Parser (src/parser.zig)
- En `parsePrimary()`, detectar `delete` seguido de una expresión de acceso
- `delete obj.prop` → DeleteExpression con MemberAccess
- `delete arr[i]` → DeleteExpression con ArrayIndex

### 4. VM (src/vm.zig)
- Opcode `delete_prop` — eliminar propiedad de js_object
- Opcode `delete_index` — eliminar elemento de array (convertir a hole)
- Retornar `true` si se eliminó, `false` si no

### 5. Evaluator (src/evaluator.zig)
- `evaluateDeleteExpression()` — eliminar propiedad del objeto
- Para arrays: marcar índice como `hole`
- Para objetos: remover del HashMap de propiedades

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
- src/types/runtime.zig — ObjectValue, ArrayObject
- src/builtins/object/ — manipulación de propiedades
- src/vm.zig — Op enum, get_prop/set_prop

### JS Examples Complejos
```js
// Delete propiedad de objeto
const user = { name: "Alice", age: 30, email: "a@b.com" };
delete user.email;
console.log("email" in user); // false

// Delete índice de array
const items = ["a", "b", "c", "d"];
delete items[1];
console.log(items.length); // 4
console.log(items[1]);     // undefined
console.log(1 in items);   // false

// Delete con acceso encadenado
const nested = { a: { b: { c: 1 } } };
delete nested.a.b.c;

// Delete retorna boolean
const obj2 = { x: 1 };
console.log(delete obj2.x);  // true
console.log(delete obj2.x);  // true (idempotente)

// Delete con variable global (no debería funcionar en strict)
// delete globalVar;
```

### Verificacion
- `delete obj.prop` elimina la propiedad y retorna `true`
- `delete arr[i]` crea un agujero en el array
- `delete` en propiedad inexistente retorna `true`
- `delete` no afecta variables declaradas con `const`/`let`
- `in` operator refleja la eliminación

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/delete.js 2>&1 | od -c
node js/tests/delete.js 2>&1 | od -c

### pendiente
- Implementar keyword, AST, parser, VM y evaluator para delete

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
