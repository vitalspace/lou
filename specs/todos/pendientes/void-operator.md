# Operador void

## status
pendiente

## Problema
El operador `void` no está implementado.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `void expr` evalúa la expresión y retorna `undefined`.

## Baseline (qué existe ya)
- Lexer NO tiene keyword `Void` (src/lexer.zig:3-113)
- AST NO tiene `VoidExpression` — `VoidLiteral` ya existe para el valor `undefined`
- `Value.void` ya existe en `src/types/runtime.zig`
- Operadores unarios como `!` (Not) ya están en el evaluator

## Quick verify (estado actual)
```bash
echo 'console.log(void 0);' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (`void` no es keyword)
```

## Patrones a seguir
- `src/lexer.zig:3-50` — enum TokenType (agregar `Void` siguiendo convención)
- `src/lexer.zig:442-460` — `getKeywordType` para mapear literal `"void"` a `.Void`
- `src/ast.zig:65` — `TypeOfExpression` como ejemplo de operador unario con `operand`
- `src/ast.zig:243-245` — `TypeOfExpression` struct como template
- `src/parser.zig` — buscar `parseUnary` o el lugar donde se parsea `!expr` para agregar `void expr`
- `src/evaluator.zig:1909` — `TypeOfExpression =>` como template

## Gotchas
- `void` es un operador UNARIO, no función — sintaxis `void(0)` también funciona pero NO es call
- Siempre retorna `undefined`, sin importar el operando
- PERO evalúa el operando (para side effects): `void console.log("hi")` imprime y retorna undefined
- Diferencia con `typeof`: `typeof expr` retorna string, `void expr` retorna undefined
- `void 0 === undefined` debe ser `true` — cross-check con `typeof-undeclared.md`
- Si la expresión interna referencia una variable no declarada (`void undeclaredVar`), debe lanzar error como cualquier otra ref — a diferencia de `typeof`

## Código que falla
```js
console.log(void 0);           // undefined
console.log(void (2 + 2));     // undefined
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keyword: `Void`

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `VoidExpression` — `void expr`

### 3. Parser (src/parser.zig)
- En `parsePrimary()`, detectar `void` seguido de una expresión
- Crear `VoidExpression`

### 4. VM (src/vm.zig)
- Opcode `void_` — evaluar expresión, descartar resultado, pushear undefined

### 5. Evaluator (src/evaluator.zig)
- Evaluar la expresión, ignorar resultado, retornar undefined

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
- src/lexer.zig — keywords
- src/parser.zig — parsePrimary(), operadores unarios
- src/vm.zig — Op enum

### JS Examples Complejos
```js
// Básico
console.log(void 0);         // undefined
console.log(void 1);         // undefined
console.log(void "hello");   // undefined
console.log(void null);      // undefined

// Expresiones
console.log(void (2 + 2));   // undefined
console.log(void [1, 2, 3]); // undefined

// Uso en IIFE (común en codebases antiguas)
void function() {
    console.log("executed");
}();

// Uso en href (previene navegación)
// <a href="javascript:void(0)">Link</a>

// En arrow functions con side effects
const log = (msg) => void console.log(msg);

// Diferencia con undefined (en contextos antiguos)
// void 0 es más seguro porque undefined puede ser reasignado (en ES3)
console.log(void 0 === undefined); // true
```

### Verificacion
- `void expr` evalúa la expresión
- `void expr` siempre retorna `undefined`
- No importa el tipo de la expresión
- `void 0 === undefined` es `true`

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/void.js 2>&1 | od -c
node js/tests/void.js 2>&1 | od -c

### pendiente
- Implementar keyword, AST, parser, VM y evaluator para void

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
