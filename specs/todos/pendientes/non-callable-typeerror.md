# Method call sobre no-callable (TypeError)

## status

pendiente

## Problema

Intentar llamar como función a un valor que no es callable retorna `void` silenciosamente. En JS lanza `TypeError: x is not a function`. Casos concretos descubiertos:

- `m.size()` (donde `m` es `Map`/`Set`) — `size` es propiedad, no método
- `arr.length()` — `length` es propiedad, no método
- `"hi".length()` — idem

Antes del refactor de `properties.zig`, `m.size()` retornaba el número (peor: mentía). Ahora retorna `void` (mejor, pero sigue mal: debería ser error).

## Contexto

ECMAScript 8.6.1 (ordinary Call) requiere que el callee sea callable. Si no, `TypeError`. La arquitectura actual tiene el path de `MethodCall` que:

1. Resuelve la propiedad / método sobre el objeto
2. Si la resuelve como método builtin → llama
3. Si no la resuelve → retorna `void` (silencioso)

Falta el paso intermedio: **detectar "se resolvió algo que NO es callable" y lanzar error**.

## Baseline (qué existe ya)
- `MethodCall` path existe en evaluator (`src/evaluator.zig` línea ~2330+)
- VM tiene opcode equivalente (`src/vm.zig` — buscar)
- `Value` union con variants para callables y no-callables (`src/types/runtime.zig`)
- `BuiltinObjectImpl` registrado en `src/builtins/builtinObjects.zig`
- `completadas/this-binding.md` ya está implementado — `this` binding funciona
- Falta: helper `isCallable()` + chequeo en MethodCall

## Quick verify (estado actual)
```bash
echo 'const m = new Map(); m.set("a",1); console.log(m.size());' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: undefined silencioso; esperado: TypeError
echo 'const arr = [1,2,3]; console.log(arr.length());' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: undefined silencioso; esperado: TypeError
```

## Patrones a seguir
- `src/evaluator.zig` — `MethodCall =>` (línea ~2330)
- `src/vm.zig` — opcode de method call
- `src/types/runtime.zig` — `Value` variants
- `src/builtins/builtinObjects.zig` — registry de callables
- ECMAScript 8.6.1, 19.2.1.1.1 (IsCallable)

## Gotchas
- Tipos callables: `.function`, `.closure`, `.generator`, `.object` BuiltinObjectImpl (cuando es method, no el object mismo)
- Tipos NO callables: `.array`, `.string`, `.integer`, `.float`, `.boolean`, `.null`, `.void`, `.symbol`
- Distinguir `Math.max` (callable, es un method de un object) vs `Math` (no callable, es el object mismo)
- Crear helper `isCallable(value: Value) bool` en `src/types/runtime.zig` o `src/utils/`
- Aplicar en AMBOS paths: evaluator y VM
- Si solo se aplica en uno, el otro path diverge
- Cross-check con `object-method-call.md` — la lógica de method call debe distinguir ambos casos
- Para reportar error: usar `error.TypeError` (nuevo error set) o generic error
- Compat test: `tests/compat/non-callable.js` y `.lou` con varios casos (primitivos, propiedades, undefined lookup)

## Código que falla

```js
const m = new Map();
m.set("a", 1);
console.log(m.size());    // Actual: void silencioso. Esperado: TypeError
console.log(m.size);      // OK: 1

const arr = [1, 2, 3];
console.log(arr.length());  // Actual: void silencioso. Esperado: TypeError
console.log(arr.length);    // OK: 3

const s = "hi";
console.log(s.length());   // Actual: void silencioso. Esperado: TypeError
console.log(s.length);     // OK: 2
```

```
// Salida actual (silenciosa):
undefined

// Salida esperada (Node):
TypeError: ... is not a function
```

## Implementacion sugerida

### 1. Localizar el path

`src/evaluator.zig` y `src/vm.zig` tienen los handlers de `MethodCall` (en el evaluator) y el opcode correspondiente (en la VM). El punto exacto es **después** de resolver el método y **antes** de invocarlo:

- Si la resolución devolvió un `.function`, `.closure`, `.generator`, o un builtin (`.object` con signature call-able) → llamar
- Si devolvió `.void`, `.string`, `.integer`, `.float`, `.boolean`, `.js_object` no-callable, `.symbol` → **lanzar `TypeError`** o un error de Lou equivalente

### 2. Tipos que SÍ son callables

| Variant | Es callable? | Por qué |
|---------|-------------|---------|
| `.function` | sí | `FunctionDeclaration`, `ArrowFunction` |
| `.closure` | sí | funciones que capturan env |
| `.generator` | sí | `GeneratorDeclaration` |
| `.object` (BuiltinObjectImpl) | a veces | `Math.abs` se invoca con args, pero `Math` solo no |
| `.js_object` con `@@call` (callable wrapper) | sí | poco común en Lou |
| `.array`, `.string`, `.integer`, `.float`, `.boolean`, `.null`, `.void`, `.symbol` | **no** | siempre error |

### 3. Plan

1. Crear un helper `isCallable(value: Value) bool` (o `requireCallable`) en `src/types/runtime.zig` o como utility en `src/builtins/`
2. En el path de `MethodCall` del evaluator y la VM, después de resolver el callee, si NO es callable → `return error.NotCallable` (o el nombre que use el codebase)
3. Decidir cómo se reporta: `TypeError` de JS style, o un error genérico de Zig
4. Tests de regresión: `m.size()`, `arr.length()`, `"hi".length()`, `123()` (números no son callables), `null()`, etc.

### 4. Edge cases

- `Math.max` (que es un `.object` BuiltinObjectImpl) debe seguir siendo callable. Si el `isCallable` rechaza `.object`, hay que agregar lógica para verificar `getMethod`.
- `obj.f()` donde `obj.f` es una `function` debería bindear `this` correctamente (ver `completadas/this-binding.md`).
- `obj[0]()` (índice en array) — no aplica, no es un patrón común en JS.
- `arr.map()` (sin args) — debería tirar `TypeError: arr.map is not a function` o funcionar? Map es un `.object` (BuiltinObjectImpl), así que la lógica tiene que distinguir "object que es callable" (cuando es un método builtin) de "object no callable" (cuando es el BuiltinObjectImpl mismo).

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

- `src/evaluator.zig` — `MethodCall` handler (línea ~2330+)
- `src/vm.zig` — opcode path de `MethodCall`
- `src/types/runtime.zig` — `Value` union (línea 233-250)
- `src/builtins/builtinObjects.zig` — registry de `*_OBJECT` con métodos callables
- `completadas/this-binding.md` — el path de `MethodCall` ya bindea `this`; este spec es ortogonal
- ECMAScript 8.6.1 — OrdinaryCallBindThis + TypeError
- ECMAScript 19.2.1.1.1 — el hook de `IsCallable`

### JS Examples Complejos

```js
// 1. Propiedades no-callables
const m = new Map();
m.size();          // TypeError

const arr = [1, 2];
arr.length();       // TypeError

const s = "hi";
s.length();         // TypeError

// 2. Primitivos no-callables
1();                // TypeError
"hello"();          // TypeError
true();             // TypeError
null();             // TypeError
undefined();        // TypeError

// 3. Lo que SIGUE funcionando
const add = (a, b) => a + b;
console.log(add(2, 3));         // 5 (es una función)

const calc = { x: 10 };
console.log(calc.x);            // 10 (no es llamada)
calc.x();                       // TypeError (number no es callable)

const m2 = new Map();
console.log(m2.get);            // undefined (no existe)
m2.get("a");                    // TypeError (undefined no es callable)

const m3 = new Map();
m3.set("a", 1);
console.log(m3.get("a"));       // 1 (es método builtin callable)
console.log(Math.max(1, 2, 3)); // 3 (es método builtin callable)
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/non-callable.js
node tests/compat/non-callable.js
```

Diffs esperados:
- `m.size()` → en Lou: error; en Node: error (exit codes 1 vs 1)
- `(1)()` → en Lou: error; en Node: error
- Casos válidos siguen funcionando sin cambios

### Comparar salida raw (sin interpretar ANSI)
```bash
./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1 | od -c
node tests/compat/<nombre>.js 2>&1 | od -c
```

### pendiente

- [ ] Definir `isCallable(value)` en un lugar común
- [ ] Aplicar en el path de `MethodCall` del evaluator
- [ ] Aplicar en el path equivalente de la VM
- [ ] Decidir nombre del error (`TypeError` de JS-style o genérico)
- [ ] Tests: propiedades, primitivos, undefined lookup, null lookup
- [ ] Verificar que builtins callables (`Math.max`, `m.get`) sigan funcionando
- [ ] No romper el suite compat existente (5/6 PASS actual)

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
