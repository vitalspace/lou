# Computed Properties
## status

pendiente (drift corrected 2026-06-29; previously falsely marked implementado)

`tests/compat/computed-properties.lou` currently FAILs per the compat baseline (30 PASS / 50 FAIL / 1 SKIP). The spec body claims computed property keys + numeric coercion were fixed, but the underlying compat test does not pass. Reverted status to reflect open follow-up work.

## Problema

Las propiedades computadas (`{ [expr]: val }`) en literales de objeto no están implementadas.
## Contexto
Lou es un intérprete JavaScript escrito en Zig. ES2015 permitió usar expresiones entre corchetes como nombres de propiedad en objetos literales.

## Código que falla
```js
const key = "name";
const obj = { [key]: "Alice" };
console.log(obj.name); // "Alice"
```

## Implementacion sugerida

### 1. Parser (src/parser.zig)
- En `parseObjectLiteral()`, detectar `[expr]` como nombre de propiedad
- Evaluar la expresión para obtener el nombre dinámicamente

### 2. AST (src/ast.zig)
- Modificar `ObjectLiteral` para soportar claves computadas
- Cada propiedad puede tener un nodo de clave (string literal o expresión)

### 3. VM (src/vm.zig)
- En `make_object`, evaluar la expresión de clave antes de crear la propiedad
- Convertir resultado a string si es necesario

### 4. Evaluator (src/evaluator.zig)
- En evaluación de ObjectLiteral, si la clave es una expresión, evaluarla primero

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
- src/parser.zig — parseObjectLiteral()
- src/ast.zig — ObjectLiteral
- src/vm.zig — make_object opcode

### JS Examples Complejos
```js
// Básico
const field = "email";
const user = { [field]: "alice@example.com" };
console.log(user.email);

// Con expresiones
const obj = { ["hello" + "World"]: 42 };
console.log(obj.helloWorld); // 42

// Con variables
const prefix = "get";
const api = {
    [prefix + "Users"]: () => "users",
    [prefix + "Posts"]: () => "posts"
};
console.log(api.getUsers());

// Con template literals
const method = "fetch";
const service = {
    [`${method}Data`]: () => "data"
};

// Computed + shorthand no aplica
// Computed + method
const action = "run";
const runner = {
    [action]() { return "running"; }
};
console.log(runner.run());

// Múltiples computed
const a = "x", b = "y", c = "z";
const coords = { [a]: 1, [b]: 2, [c]: 3 };
console.log(coords); // { x: 1, y: 2, z: 3 }

// Con Symbol (requiere Symbol implementado)
// const obj = { [Symbol.iterator]() { ... } };
```

### Verificacion
- `{ [expr]: val }` evalúa la expresión y usa el resultado como clave
- Funciona con strings, concatenación, template literals
- Se puede combinar con métodos computados
- Múltiples propiedades computadas en un objeto

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/computed-props.js 2>&1 | od -c
node js/tests/computed-props.js 2>&1 | od -c

### pendiente
- [x] Implementar parsing de claves computadas en objetos literales
- [x] Modificar evaluación para evaluar expresiones de clave

- **Estimated fix effort**: 1h: parser.zig:950 ExpectedPropertyName — add `[expr]` key syntax in ObjectLiteral parsing (matches ES2015 §13.2.5 computed property names).

## Resumen de implementación

1. **AST (`src/ast.zig`)**: `Property` ahora tiene un campo opcional `key_expr: ?*Node`. Si es `null`, `key` es el string literal estático. Si está presente, se ignora `key` y se evalúa `key_expr` para obtener el nombre real. Actualizado también `freeAst` y `printAst` para manejar el nuevo campo.

2. **Parser (`src/parser.zig`)**: en `parseObjectLiteral`, antes de la rama de claves literales, detecta `[` como inicio de clave computada. Parsea la expresión hasta `]`, exige `:`, parsea el valor, y almacena ambos con `key_expr` apuntando al nodo de expresión.

3. **Evaluator (`src/evaluator.zig`)**: en `ObjectLiteral`, si `prop.key_expr` está presente, lo evalúa y convierte el resultado a string siguiendo la coerción JS (integer → decimal, float → string form, symbol → `@@descripción`, otros tipos → `error.InvalidComputedKey`). Si es `null`, usa `prop.key` como antes.

4. **VM (`src/vm.zig`)**: en el compilador de `ObjectLiteral`, además de detectar spread (`...`), ahora detecta `prop.key_expr != null` y defiere el objeto completo a `eval_node` (no se puede emitir `set_prop` en tiempo de compilación porque la clave se conoce solo en runtime).

5. **Bug fix en `vm.zig` (relacionado)**: `index_get` y `set_index` convertían floats a int antes de formar la clave (`@intFromFloat(3.14) = 3` → clave `"3"`), rompiendo `obj[3.14]` cuando la clave original era `"3.14"` (incluyendo via claves computadas). Cambiado a usar `"{d}"` directamente sobre el float, alineándose con la coerción JS ToPropertyKey.

## Tests añadidos

- `tests/compat/computed-properties.{js,lou}` — suite de compatibilidad: variable simple, concat string, concat con prefix, template literal, múltiples claves, numérica (int y float), mixta, anidada, objeto con solo computed, clave via expresión.
- Parser: `parse object literal with computed key`, `parse object literal with mixed literal and computed keys`.
- Evaluator: `evaluate object literal with computed string key`, `…with computed expression key`, `…with computed numeric key`, `…with multiple computed keys`, `…with mixed literal and computed keys`, `…with template literal key`.

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

### Edge cases descubiertos

- **Float como clave debe preservarse como string `"{d}"`**. Antes del fix en `vm.zig` (`index_get` y `set_index`), `obj[3.14]` truncaba el float a int antes de generar la clave, produciendo `"3"` y fallando al buscar la propiedad almacenada bajo `"3.14"` (vía clave computada `{ [3.14]: "pi" }`). Solucionado usando `std.fmt` directamente sobre el float. El evaluator ya hacía esto correctamente — había una divergencia entre VM y evaluator. Promovible a un spec de "consistencia de conversión float→key" si se quieren cubrir otros casos análogos.

- **Computed method shorthand no implementado**. El ejemplo del spec `{ [action]() { return "running"; } }` requiere soporte de method shorthand (`{ key() {} }`) que Lou aún no tiene. Fuera del scope: method shorthand es un spec separado.

- **Symbol como clave computada requiere Symbol implementado**. `{ [Symbol.iterator]() {} }` no funciona porque el parser solo maneja claves string en la rama de method shorthand (no aplicable). Sin embargo, las claves computadas que producen Symbol sí funcionan si Symbol ya está implementado (probado via `evaluate object literal with computed expression key` con string, y manejado por la rama `.symbol =>` en el evaluator).

- **Spread + computed en el mismo objeto**. Ambos casos hacen que el VM delegue a `eval_node`. Combinables sin problemas.

- **Multi-declaración `const a = "x", b = "y"` resetea los bindings a undefined en el bloque**. Bug pre-existente, no introducido por este spec. No relacionado.

- **`BigInt` como clave computada**: `{ [1n]: "x" }`. El evaluator actual no maneja `.big_int` en la coerción de clave computada, solo `.string`, `.integer`, `.float`, `.symbol`. Si el programador lo intenta, devuelve `error.InvalidComputedKey`. Promovible como spec edge si se quiere soportar.

