# Optional Chaining (?.)

## status
pendiente

## Problema
El operador `?.` (optional chaining) no está implementado. No se puede acceder a propiedades de forma segura cuando el objeto puede ser null/undefined.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. ES2020 agregó optional chaining para evitar errores al acceder a propiedades de objetos que podrían ser null/undefined.

## Baseline (qué existe ya)
- Lexer ya tiene `.` (Dot), `?.` NO existe como token (`src/lexer.zig:289-300`)
- AST NO tiene `OptionalChainExpression` (`src/ast.zig:48-66`)
- Member access normal funciona vía `MemberAccess` y `MethodCall` nodes
- No existe precedent de "short-circuit on null" en el evaluator

## Quick verify (estado actual)
```bash
echo 'const x = null; console.log(x?.foo);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (`?` no es token reconocido)
```

## Patrones a seguir
- `src/parser.zig` — buscar `parseMemberAccess` para ver cómo se parsea `.prop` y `.method()`
- `src/ast.zig:48-49` — `MemberAccess` y `MethodCall` como AST nodes de referencia
- `src/evaluator.zig` — búsqueda de `MemberAccess =>` y `MethodCall =>` para ver el path de evaluación
- `src/lexer.zig:289-300` — handler de `.` para agregar rama de `?.`

## Gotchas
- `?.` debe funcionar como dot: con propiedad (`obj?.prop`), índice (`obj?.[expr]`), y método (`obj?.method()`)
- Cortocircuito: si el LHS es null/undefined, retornar `.{ .void = {} }` (undefined) sin evaluar RHS
- NO permitir `obj?.prop = value` (SyntaxError en JS) — `?.` no es válido como target de asignación
- `obj?.a.b.c` debe cortocircuitar en `obj` pero seguir evaluando `.b.c` si `obj.a` no es nullish
- Cross-check con `in-operator.md` — `"x" in obj?.props` debe cortocircuitar igual
- Si añadís AST node nuevo (`OptionalChainExpression`), actualizar `freeAst` (~line 800), `printAst` (~line 470), y switch en `evaluate` (~line 187)
- Si añadís token nuevo, agregar a `TokenType` enum y a `getKeywordType`/lexer dispatcher

## Código que falla
```js
const user = { address: { street: "Main St" } };
console.log(user?.address?.street); // "Main St"
console.log(user?.phone?.number);   // undefined (no error)
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar token: `OptionalChain` (`?.`)

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `OptionalChainExpression` — `obj?.prop`, `obj?.[key]`, `obj?.method()`

### 3. Parser (src/parser.zig)
- En `parseMemberAccess()`, detectar `?.` como acceso opcional
- Soportar `obj?.prop`, `obj?.[expr]`, `obj?.method(args)`

### 4. VM (src/vm.zig)
- Opcode `optional_get_prop` — como `get_prop` pero retorna undefined si el objeto es null/undefined
- Opcode `optional_index_get` — similar para acceso por índice

### 5. Evaluator (src/evaluator.zig)
- En evaluación de acceso a miembro, si el objeto es null/undefined, retornar undefined en lugar de error

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
- src/parser.zig — parseMemberAccess()
- src/vm.zig — get_prop, index_get

### JS Examples Complejos
```js
// Propiedad
const obj = { a: { b: 1 } };
console.log(obj?.a?.b);     // 1
console.log(obj?.x?.y);     // undefined

// Con null
const nil = null;
console.log(nil?.prop);     // undefined

// Con undefined
const undef = undefined;
console.log(undef?.prop);   // undefined

// Acceso por índice
const arr = [1, 2, 3];
console.log(arr?.[1]);      // 2
console.log(null?.[0]);     // undefined

// Llamada a método
const obj2 = { greet: () => "hi" };
console.log(obj2?.greet()); // "hi"
console.log(null?.greet()); // undefined

// Encadenado mixto
const data = { users: [{ name: "Alice" }] };
console.log(data?.users?.[0]?.name); // "Alice"
console.log(data?.items?.[0]?.name); // undefined

// Asignación NO funciona (SyntaxError en JS)
// obj?.prop = 1; // Error
```

### Verificacion
- `obj?.prop` retorna el valor si existe, undefined si obj es null/undefined
- `obj?.[key]` funciona igual
- `obj?.method()` funciona igual
- No lanza TypeError cuando el objeto es null/undefined
- Se puede encadenar: `a?.b?.c?.d`

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/optional-chaining.js 2>&1 | od -c
node js/tests/optional-chaining.js 2>&1 | od -c

### pendiente
- Implementar token, AST, parser, VM opcode y evaluator para ?.

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

- Disposition: stays in pendientes/ — no corresponding test exists in tests/compat/. Create tests/compat/optional-chaining.lou + tests/compat/optional-chaining.js to enable automatic PASS/FAIL tracking.

