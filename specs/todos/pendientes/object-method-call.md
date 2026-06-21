# Object literal: llamar a una función almacenada como propiedad

## status

pendiente

## Problema

En un object literal, las propiedades cuyo valor es una función (`{ a: function() { return 1; } }`) existen (`typeof obj.a === 'function'`) pero **llamarlas** (`obj.a()`) retorna `undefined` en vez del valor de retorno de la función.

`Array.prototype.map(function(x) { ... })` SÍ funciona — el problema es específicamente llamar a una función que es **propiedad de un objeto literal plano**.

## Contexto

Lou evalúa el acceso a propiedades en `evaluator.zig`. La distinción crítica es:
- `arr.map(fn)` — `map` es un método del `Array` builtin object; se lookup'a vía `getMethod` y se llama con `this = arr`.
- `obj.f()` — `f` es una propiedad de un `js_object` (object literal). La resolución debe: encontrar `f` en `properties`, detectar que es un `.function`, e invocarla pasando `this = obj`.

El bug está en ese segundo path.

## Baseline (qué existe ya)
- `Array.prototype.map(fn)` SÍ funciona — builtins están bien
- `completadas/this-binding.md` YA está implementado — `this` binding funciona
- Evaluator tiene path de `MethodCall` que distingue `js_object` pero no invoca funciones como propiedades
- Bug específico: el branch para `.js_object` no detecta que la propiedad es `.function`
- `Value` tiene variant `.function` y `.closure` (callable)

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
const o = { f: function() { return 42; } };
console.log(o.f());
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: undefined; esperado: 42
```

## Patrones a seguir
- `src/evaluator.zig` — buscar `MethodCall =>` y `MemberAccess =>`
- `src/evaluator.zig` — buscar `callFunctionValue` o similar para invocación de funciones
- `src/builtins/array/` — cómo invocar Array.prototype.map (referencia del path correcto)
- `src/types/runtime.zig` — `Value.function`, `Value.closure`
- `src/environment.zig:200` — `getBuiltinObject` (cómo se hace para builtins)

## Gotchas
- El fix debe diferenciar entre:
  1. `js_object.property` (MemberAccess) — solo lookup
  2. `js_object.property()` (MethodCall) — lookup + invocar si es function
- Si la propiedad es `.function` o `.closure`, invocarla pasando `this = obj`
- Si la propiedad es `.js_object` (delegación), seguir buscando dentro
- Cross-check con `prototype-chain.md` — si la propiedad no está en el objeto directo, buscar en prototype
- Cross-check con `completadas/this-binding.md` — usar el mecanismo de bind `this` ya implementado
- Verificar que `Array.prototype.map(fn)` (que sí funciona) no se rompa
- Bug no es cosmético: cualquier objeto literal con funciones como propiedades está afectado
- Test crítico: `obj.fact(5)` con recursión — debe mantener el binding a `this` correcto entre llamadas

## Código que falla

```js
const obj1 = {
    a: function() { return 1; },
    b: function() { return 2; }
};
console.log(typeof obj1.a);    // "function" (correcto)
console.log(obj1.a());         // undefined (debería: 1)

const obj2 = {
    val: 99,
    getVal: function() { return this.val; }
};
console.log(obj2.getVal());    // undefined (debería: 99)
```

```
function
function
undefined       <- obj1.a()  ← debería ser 1
undefined       <- obj1.b()  ← debería ser 2
```

Mismo síntoma para cualquier acceso a propiedad cuyo valor es un `Value.function` y se invoca con `()`.

## Implementacion sugerida

### 1. Localizar el path

Buscar en `evaluator.zig` el branch de `MemberAccess` / `CallExpression` cuando la base es un `.js_object` y la propiedad es `.function`. Ahí debería:
1. Leer la propiedad (`obj.properties.get(name)`).
2. Si es `.function`, llamar a la función con `this_val = obj` (o sea, el `js_object`).
3. Manejar también el caso donde la propiedad es `.js_object` que envuelve a una función (delegación).

### 2. Diagnóstico probable

El evaluador probablemente tiene un branch para `value == .js_object` que busca `method_val = properties.get(name)` y lo trata como otro `js_object` o como una property, no como una función call-able. Verificar la lógica de `CallExpression` y `MemberAccess` en `evaluator.zig`.

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

- `src/evaluator.zig` — `MemberAccess`, `CallExpression`, `callFunctionValue`
- `src/types/runtime.zig` — `Value` variants `.js_object`, `.function`
- `src/environment.zig:200` — `getBuiltinObject` (cómo se hace para builtins)
- `completadas/this-binding.md` — `this` ya debería estar bindeado; verificar que llegue a object methods
- ECMAScript 14.3.3 — `CallExpression`, 14.3.5 — `MemberExpression`

### JS Examples Complejos

```js
// Una función
const o1 = { f: function() { return 42; } };
console.log(o1.f());                       // 42

// Múltiples funciones
const o2 = {
    add: function(a, b) { return a + b; },
    sub: function(a, b) { return a - b; }
};
console.log(o2.add(2, 3));                // 5
console.log(o2.sub(10, 4));               // 6

// this binding
const o3 = {
    value: 100,
    double: function() { return this.value * 2; }
};
console.log(o3.double());                 // 200

// Con argumentos
const o4 = {
    greet: function(name) { return "Hi " + name; }
};
console.log(o4.greet("Ada"));             // "Hi Ada"

// Recursión
const o5 = {
    fact: function(n) {
        if (n < 2) return 1;
        return n * this.fact(n - 1);
    }
};
console.log(o5.fact(5));                  // 120
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/object-method-call.js
node tests/compat/object-method-call.js
```

Diff esperado: ningún `undefined` donde debería haber un valor; exit 0.

### Verificacion
*(Pendiente: listar los criterios de aceptación — qué casos deben pasar para considerar el spec como implementado.)*

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/object-method-call.js 2>&1 | od -c
node tests/compat/object-method-call.js 2>&1 | od -c
```

### pendiente

- [ ] Localizar el path `js_object.property()` en el evaluador
- [ ] Distinguir entre propiedad-callable (`.function`) y property-data
- [ ] Bindear `this = obj` al llamar (verificar coherencia con `completadas/this-binding.md`)
- [ ] Tests: 1 fn, N fns, `this`, argumentos, recursión
- [ ] Verificar que `Array.map(fn)` (que sí funciona) no se rompa

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
