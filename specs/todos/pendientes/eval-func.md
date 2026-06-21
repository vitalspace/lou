# eval()

## status
pendiente

## Problema
La función global `eval()` no está implementada.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. `eval()` ejecuta código JavaScript representado como string. Es compleja de implementar de forma segura.

## Baseline (qué existe ya)
- Parser (`src/parser.zig`) — funciona sobre string input
- Evaluator (`src/evaluator.zig:151`) — entry point `evaluate`
- Lexer (`src/lexer.zig`) — entry point `Lexer.init`
- Main pipeline: `main.zig` parse → compile → run
- Builtins registrados (`src/builtins/builtins.zig`)
- eval NO existe — pero toda la pipeline puede reusarse

## Quick verify (estado actual)
```bash
echo 'console.log(eval("2 + 2"));' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: "eval is not defined"
```

## Patrones a seguir
- `src/builtins/builtins.zig` — registrar `eval` como builtin global
- `src/main.zig` — cómo se hace el pipeline completo (parse + eval) sobre un string
- `src/parser.zig:16` — `Parser.init(lexer, allocator)`
- `src/evaluator.zig:151` — `pub fn evaluate(node: *ast.Node, env: *Environment)`

## Gotchas
- IMPLEMENTACIÓN:
  1. Crear nuevo Lexer sobre el string
  2. Crear nuevo Parser sobre el Lexer
  3. Parsear program (sequence de statements)
  4. Evaluar cada statement en el env del caller
  5. Retornar el valor del último statement
- DECISIÓN CRÍTICA: ¿qué env usar?
  - Direct call `eval(...)` — usa el env del caller (acceso a variables locales)
  - Indirect call `(0, eval)(...)` — usa el global env (sin acceso a locales)
- Más simple: siempre usar el env del caller
- Cross-check con `closure.md` — el env capturado debe permitir acceso a variables
- `var x = 10; eval("x")` debe retornar 10
- `eval("var z = 100")` — la declaración `z` debe persistir en el env del caller
- `eval` con `let`/`const` — también persiste, pero respeta TDZ
- Strict mode: separado scope — IGNORAR por simplicidad
- Error handling: si el código tiene syntax error, lanzar SyntaxError
- Si el código lanza exception, propagar

## Código que falla
```js
console.log(eval("2 + 2"));         // 4
console.log(eval("var x = 10; x")); // 10
```

## Implementacion sugerida

### 1. Builtin (src/builtins/)
Registrar `eval` como función global.

### 2. Implementación
- Recibir string como argumento
- Parsear el string como código JavaScript
- Ejecutar en el scope actual (no en uno nuevo)
- Retornar el resultado de la última expresión

### 3. Consideraciones
- `eval` tiene acceso al scope local (closure sobre variables actuales)
- En strict mode, `eval` crea un scope separado
- Es una función de alto riesgo — considerar limitaciones de seguridad

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
- src/main.zig — pipeline de ejecución (parse → compile → run)
- src/environment.zig — entorno/scope
- src/vm.zig — máquina virtual

### JS Examples Complejos
```js
// Básico
console.log(eval("2 + 2"));         // 4
console.log(eval("'hello'"));       // "hello"
console.log(eval("[1,2,3].length")); // 3

// Acceso a variables locales
let x = 10;
console.log(eval("x")); // 10

// Modificación de variables locales
let y = 1;
eval("y = 42");
console.log(y); // 42

// Declaración en eval
eval("var z = 100");
console.log(z); // 100

// Código multi-línea
const result = eval(`
    const a = 1;
    const b = 2;
    a + b
`);
console.log(result); // 3

// Retorno de última expresión
console.log(eval("1 + 2; 3 + 4; 5 + 6")); // 11

// Funciones definidas en eval
eval("function add(a, b) { return a + b; }");
console.log(add(2, 3)); // 5

// JSON parsing alternativo
const obj = eval('(' + '{"a": 1}' + ')');
console.log(obj.a); // 1
```

### Verificacion
- `eval("2 + 2")` retorna 4
- `eval` tiene acceso a variables del scope actual
- `eval` puede modificar variables existentes
- `eval` retorna el resultado de la última expresión
- Declaraciones en `eval` persisten en el scope

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/eval.js 2>&1 | od -c
node js/tests/eval.js 2>&1 | od -c

### pendiente
- Registrar eval como función global
- Implementar ejecución de código dinámico con acceso al scope actual

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
