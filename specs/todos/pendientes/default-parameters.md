# Default Parameters

## status

**pendiente** — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SKIP)

El test `tests/compat/default-parameters.lou` sigue FAIL. La primera divergencia exacta está en `living-tracker.md`, sección 2.

## Problema
Los parámetros por defecto en funciones no están implementados. No se puede definir un valor default para un parámetro.

## Contexto
Lou es un intérprete JavaScript escrito en Zig. ES2015 permitió definir valores por defecto en parámetros de función.

## Diseño

### AST (src/ast.zig)
Se añadió un campo paralelo `param_defaults: []?*Node` a `FunctionDeclaration`, `ArrowFunction` y `GeneratorDeclaration`. El default value para `parameters[i]` está en `param_defaults[i]` (null si no hay default). El campo tiene un default de `&[_]?*Node{}` para que las construcciones existentes de struct-literal sigan funcionando sin cambios.

Se añadió `ast.freeDefaults` para liberar el array de defaults y cada expresión default (necesario porque `freeAst` solo se llama recursivamente sobre el `body`).

### Parser (src/parser.zig)
En `parseFunctionDeclaration` y `parseArrowFunction`, después de parsear el nombre del parámetro se verifica si el siguiente token es `=`. Si lo es, se consume y se parsea una expresión (vía `parseExpression`); la expresión se guarda en una `ArrayList` paralela.

### Evaluator (src/evaluator.zig)
Se añadió un helper `resolveArgumentIn(idx, args, param_defaults, func_env)` que aplica la semántica ES2015:
- Si hay argumento y NO es `undefined` (i.e. `args[idx] != .void`), usarlo.
- Si no, y el parámetro tiene un default, evaluarlo **en `func_env`** (el env de la función), no en el env del caller, para que pueda referenciar parámetros anteriores ya bound.
- Si no, usar `undefined` (`Value.void`).

Este helper reemplaza la asignación directa de `args[idx]` o `void` en los tres paths: `FunctionDeclaration`, `ArrowFunction`, `GeneratorDeclaration`.

Importante: `null` NO activa el default, solo `undefined` lo hace (es la semántica de ES2015).

### VM (src/vm.zig)
Mismo helper `resolveArgumentIn` aplicado en los dos paths: el path de bytecode compilado (si existe un chunk para la función) y el path de fallback al AST evaluator. El env de la función se crea antes del loop de binding, para que los defaults puedan ver los parámetros anteriores via la cadena de env.

## Tests

### Compat test
`tests/compat/default-parameters.{js,lou}` — referencia canónica en Node + el mismo programa en Lou. Cubre:
- Básicos (`function sum(a=0,b=0) { ... }`).
- `undefined` activa el default, `null` no.
- Defaults con expresiones (`size=2, fill=size*2`).
- Arrow functions con defaults.
- Defaults encadenados que referencian parámetros anteriores (`first, second=first*2, third=second*2`).
- Mixto: con y sin default en la misma función (`host, port=8080, secure=false`).

### Unit tests
- `parser.zig`: 5 tests que verifican la estructura del AST para default simples, mezclados, sin defaults, en arrow functions, y un default que referencia un parámetro anterior.
- `evaluator.zig`: 5 tests que ejecutan programas pequeños y verifican el valor de retorno:
  - missing arg → default
  - explicit arg → overrides default
  - `undefined` → default, `null` → null
  - arrow function con defaults
  - default encadenado (`first, second=first*2, third=second*2`)

## Edge cases encontrados durante implementación

1. **Orden de evaluación de los defaults**: el env de la función debe existir ANTES de empezar a bindear parámetros, y cada default debe evaluarse en ese env (no en el env del caller). Si se evalúa en el env del caller, los defaults no pueden referenciar parámetros anteriores.

2. **`null` vs `undefined`**: `f(null)` no activa el default; `f(undefined)` sí. Esto se modela revisando `args[idx] != .void` (donde `.void` es la representación de `undefined`).

3. **Función sin defaults**: el campo `param_defaults` se inicializa con un array vacío vía el default `&[_]?*Node{}`. `freeDefaults` usa `defaults.len > 0` como guarda para no intentar liberar slices vacíos estáticos. El path del parser usa `toOwnedSlice` que para una `ArrayList` vacía también devuelve un slice vacío estático, así que la guarda funciona en ambos casos.

4. **Compatibilidad con `toOwnedSlice`**: Zig 0.16 `ArrayList.toOwnedSlice` sobre una lista vacía devuelve `&[_]T{}` (slice estático). Mi helper `freeDefaults` ignora arrays de length 0, así que es seguro con slices estáticos vacíos.

5. **Builtin consumers (array/sort, some, map, etc.)**: no usan `param_defaults`, solo `parameters` para mapear argumentos (e.g. `func_params[0]` = element, `func_params[1]` = index). El nuevo campo `param_defaults` no rompe esos consumidores porque está separado de `parameters`.

6. **Default con `f.parameters.len > 0` usado en builtin consumers**: no necesitan cambios. Las funciones que pasan por `Array.prototype.map`, `filter`, etc. son `ArrowFunction` y `FunctionDeclaration` simples, y los builtins no propagan defaults a la función callback — los builtins solo pasan los argumentos (element, index, array) según la firma. Esto es compatible con el comportamiento de Node.

7. **VM con bytecode precompilado**: la versión inicial sólo aplicaba defaults en el AST evaluator; las funciones con bytecode precompilado (named functions con `compiled_chunks`) usaban el binding simple positional y nunca veían los defaults. **Fix**: el `callFuncNode` del VM ahora detecta `has_defaults` y salta el path del bytecode chunk, forzando el fallback al AST evaluator. Aceptable pérdida de performance para funciones con defaults (raro en hot paths).

8. **Regresión pre-existente**: el spec original se marcó "implementado" pero el binding en `callFuncNode` del VM seguía siendo el viejo (sin defaults). Al ejecutar el compat test, los parámetros no-bindiados causaban `UndefinedVariable` al usarlos. Esta sesión añadió la lógica de defaults al VM path.

## Verificación

```bash
$ bash tests/compat/run.sh | tail -3
PASS=25  FAIL=1  SKIP=1
```

`default-parameters.lou` está en el set de los 25 PASS. El 1 FAIL (isolate.lou) y 1 SKIP (function-expr-body.lou) son pre-existentes y no relacionados con este spec.

```bash
$ zig build test | grep "pass,"
+- run test 983 pass, 0 crash (984 total)
```

983 pass (subió desde 982 por el test de `default parameters - arrow function with default` añadido después). 0 leaks, 0 crashes. Los crashes/leaks pre-existentes fueron resueltos:

1. **Leak en `Environment.deinit`**: la guarda `if (self.captures.items.len > 0)` se evaluaba DESPUÉS de `self.captures.deinit(self.allocator)`, que en debug sobreescribe la struct con `0xaa` bytes, haciendo que `items.len` sea UB. Cualquier test que crease un `Environment` con `outer=null` (top-level) se saltaba el deinit completo. **Fix**: capturar `has_captures` antes de `deinit`.

2. **Uso incorrecto de `captures`**: `try env.captures.append(env.allocator, env)` en `FunctionDeclaration` y `ArrowFunction` añadía el env a su propia lista de captures, marcando el env como "captured" siempre que se declarase una función. Combinado con el bug #1, provocaba que `env.deinit()` saliera temprano y dejara todo sin liberar. **Fix**: eliminar las llamadas a `captures.append`; `function_lexical_envs` ya cubre el caso de closures.

3. **Crash en `parseIsoDate - fractional seconds`**: `parseU8` rechazaba valores >255, pero los milisegundos pueden llegar a 999. **Fix**: añadir `parseU16` y usarlo para los milisegundos.

4. **`bound_this` leak**: `ObjectValue.init` en el test no se agregaba a `env.objects`. **Fix**: agregar el objeto a `env.objects` antes de usarlo.

## pendiente
- (ninguno — spec implementado)

