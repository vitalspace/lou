# Boolean — Constructor + `toString`/`valueOf`

## status
implementado

## Problema

El objeto `Boolean` no estaba implementado como constructor. Los
booleanos se manejaban solo como primitivos, sin wrapper ni métodos
de prototipo. Esto causaba que `Boolean(1)`, `new Boolean(true)`,
`true.toString()` y `true.valueOf()` no funcionaran.

## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los booleanos son
primitivos en el runtime (`Types.Value.boolean`), pero JS estándar
expone el constructor `Boolean` y métodos en `Boolean.prototype`.
El spec se implementó siguiendo el patrón de `BigInt` (ver
`bigint-prototype-template.md`): un `BuiltinObjectImpl` con métodos
`toString` y `valueOf`, más dispatch en `evaluator.zig` y `vm.zig`
para llamadas sobre primitivos y wrappers.

## Código que falla (antes)
```js
console.log(Boolean(1));        // error: UndefinedVariable
console.log(new Boolean(true)); // error: no constructor
true.toString();                // error: UndefinedMethod
true.valueOf();                 // error: UndefinedMethod
```

## Implementación

### 1. Builtin (`src/builtins/boolean/boolean.zig`)

```zig
/// Boolean(value?) — JS Boolean() constructor. Convierte a booleano
/// siguiendo ToBoolean del estándar ES (falsy: 0, -0, NaN, "",
/// null, undefined, 0n, false; resto es truthy).
pub fn BooleanConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len == 0) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = toBoolean(args[0]) } };
}

/// Boolean.prototype.toString() — "true" o "false".
/// Acepta primitivo booleano o wrapper (`@@type="Boolean"`).
pub fn BooleanToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    const b = switch (args[0]) {
        .boolean => |v| v,
        .js_object => |obj| extractBooleanFromWrapper(obj) orelse return .{ .value = .{ .void = {} } },
        else => return .{ .value = .{ .void = {} } },
    };
    const result = env.allocator.dupe(u8, if (b) "true" else "false") catch {
        return .{ .value = .{ .void = {} } };
    };
    env.owned_strings.append(env.allocator, result) catch {};
    return .{ .value = .{ .string = result } };
}

/// Boolean.prototype.valueOf() — primitivo booleano.
pub fn BooleanValueOf(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .void = {} } };
    return switch (args[0]) {
        .boolean => |v| .{ .value = .{ .boolean = v } },
        .js_object => |obj| {
            const b = extractBooleanFromWrapper(obj) orelse return .{ .value = .{ .void = {} } };
            return .{ .value = .{ .boolean = b } };
        },
        else => .{ .value = .{ .void = {} } },
    };
}

/// ToBoolean del estándar ES2025.
pub fn toBoolean(v: Types.Value) bool {
    return switch (v) {
        .boolean => |b| b,
        .integer => |i| i != 0,
        .float => |f| f != 0.0 and !std.math.isNan(f),
        .big_int => |big| !big.value.eqlZero(),
        .string => |s| s.len > 0,
        .void, .null, .hole => false,
        else => true,
    };
}
```

### 2. Registro

- `src/builtins/builtins.zig` — `Boolean` agregado a `BUILTIN_FUNCTIONS`
- `src/builtins/builtinObjects.zig` — `BOOLEAN_OBJECT` agregado a
  `BUILTIN_OBJECTS`

### 3. Wrapper para `new Boolean` (`src/evaluator.zig`)

`NewExpression` no diferencia entre `new` y llamada directa para
builtins built-in. Para que `new Boolean(true)` devuelva un wrapper
(`typeof === "object"`), se agregó un helper `wrapNewIfNeeded` que
envuelve el resultado del constructor en un `*ObjectValue` con
`@@type="Boolean"` y `@@primitive` cuando el builtin es `Boolean`.

```zig
fn wrapNewIfNeeded(func_name: []const u8, val: ast.Value, env: *Environment) anyerror!ast.Value {
    if (std.mem.eql(u8, func_name, "Boolean")) {
        if (val == .boolean) {
            if (try @import("builtins/boolean/boolean.zig").makeBooleanWrapper(env, val)) |wrapper| {
                return wrapper;
            }
        }
    }
    return val;
}
```

### 4. Dispatch de métodos (`src/evaluator.zig` y `src/vm.zig`)

Para que `true.toString()` y `(new Boolean(true)).toString()`
funcionen, se añadieron dos ramas nuevas:

- `.boolean` (primitivo) — busca el método en `BOOLEAN_OBJECT` y lo
  invoca con el primitivo como `args[0]`. Análogo al dispatch de
  `.big_int` que ya existía.
- `.js_object` con `@@type="Boolean"` — mismo dispatch pero usando
  el wrapper como `args[0]` (las funciones `BooleanToString`/
  `BooleanValueOf` saben extraer el primitivo de `@@primitive`).

En el VM se hizo lo mismo en ambas ramas del opcode `method_call`
(con args y sin args).

## Verificación

- `tests/compat/boolean.lou` y `tests/compat/boolean.js` — output
  byte-idéntico entre Lou y Node.
- 18 unit tests en `src/builtins/boolean/boolean.zig` cubriendo:
  - `Boolean()` con cada tipo de input (number, string, null,
    undefined, bigint, object, array, NaN, -0, etc.)
  - `Boolean()` sin argumentos → `false`
  - `BooleanToString` con primitivo y con wrapper
  - `BooleanValueOf` con primitivo y con wrapper
  - Rechazo de `js_object` con `@@type` distinto a `"Boolean"`
  - Rechazo de input no booleano (retorna void)

### Comandos
```bash
# Unit tests
zig build test

# Compat test
bash tests/compat/run.sh

# Diff raw
diff <(./zig-out/bin/lou run tests/compat/boolean.lou 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g') \
     <(node tests/compat/boolean.js 2>&1)
```

## Tests
- `tests/compat/boolean.js` — referencia canónica
- `tests/compat/boolean.lou` — versión Lou (idéntica para JS puro)

## pendiente
- [x] `Boolean(value)` con ToBoolean correcto
- [x] `new Boolean(value)` retorna wrapper con `typeof === "object"`
- [x] `Boolean.prototype.toString()`
- [x] `Boolean.prototype.valueOf()`
- [x] Dispatch sobre primitivo (`true.toString()`)
- [x] Dispatch sobre wrapper (`(new Boolean(true)).toString()`)
- [x] Tests compat (Lou vs Node idénticos)
- [x] Unit tests en el builtin

## Edge cases

### NaN handling
La función `truthy` de `src/vm.zig:2204` (usada por `&&`, `||`, `if`,
`while`) tiene un bug pre-existente: para `f64` retorna
`f != 0.0`, lo cual es `true` para `NaN` (porque NaN no es igual a
nada, ni siquiera a 0.0). Eso significa que `if (NaN)` se evalúa
como truthy en Lou, contradiciendo el estándar. Sin embargo, esto es
un bug pre-existente fuera del scope de este spec. La nueva función
`toBoolean` en `src/builtins/boolean/boolean.zig` sí implementa
correctamente `ToBoolean` (falsy para NaN, 0, -0, "", null,
undefined, 0n, false).

### `new Boolean()` con cero argumentos
`new Boolean()` (sin args) retorna un wrapper con valor primitivo
`false` (per spec: convierte el argumento ausente a `false`). Cubierto
por la suite de unit tests y por `tests/compat/boolean.lou`.

### Wrapper `js_object` con `@@type="Boolean"`
Lou no tiene un sistema de prototype chain completo. Para que
`b.valueOf()` y `b.toString()` funcionen donde `b = new Boolean(true)`,
se usa el patrón `@@type` (mismo que Set/Map). El wrapper es un
`*ObjectValue` con:
- `@@type` = `"Boolean"` (string owned por `env.owned_strings`)
- `@@primitive` = el valor booleano primitivo

El dispatch en `evaluator.zig` y `vm.zig` revisa primero el `@@type`
antes de hacer el dispatch genérico a Array.

### `Number("abc")` para NaN
Lou no expone la global `NaN`. En el compat test se usa
`Number("abc")` para producir NaN, que es falsy.

## Limitaciones conocidas

- `Boolean.prototype` no es directamente accesible como objeto (no
  expone el prototipo de la misma forma que Node).
- `Boolean.prototype.toString.call(true)` no funciona porque Lou no
  soporta `Function.prototype.call()` con `this` primitive binding.
  El método `toString` solo se puede invocar como `true.toString()`
  o `(new Boolean(true)).toString()`.
- Loose equality entre boolean y number (`true == 1`) no se comporta
  como en Node (Lou retorna `false`). Es un bug pre-existente del
  operador `==` no relacionado con este spec.
- Solo se implementan `toString()` y `valueOf()`. No hay soporte
  para `Boolean.prototype.constructor`, `Symbol.toPrimitive`, ni
  otros miembros del prototipo de Node.
- `truthy()` en `src/vm.zig` sigue con el bug de NaN — el spec solo
  implementa el `Boolean()` constructor, no repara el bug
  pre-existente del runtime.
