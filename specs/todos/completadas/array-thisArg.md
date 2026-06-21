# Soporte thisArg en métodos callback de Array

**Prioridad: alta** — ✅ COMPLETADO (reduce/reduceRight correctamente NO tienen thisArg)

## Problema

Los métodos `every`, `filter`, `find`, `findIndex`, `findLast`, `findLastIndex`, `flatMap`, `forEach`, `map`, `reduce`, `reduceRight`, `some` no aceptan el parámetro `thisArg`. Node.js lo soporta.

## Contexto

- ECMAScript especifica `thisArg` como segundo parámetro opcional después del callback
- En lou, ningún callback recibe `thisArg` — todos llaman al callback sin `this`
- La corrección es propagar `thisArg` como `this` del callback vía `callWithThis` o similar
- `reduce`/`reduceRight` son diferentes: el segundo parámetro es `initialValue`, no `thisArg`

## Implementación

- `thisArg` se pasa como 3er argumento en todos los métodos
- Se almacena como variable `"this"` en el `func_env` del callback
- El evaluator resuelve `this` vía `env.get("this")` en el scope del callback
- Arrow functions heredan `this` léxicamente (sin binding propio) — spec en `specs/todos/this-binding.md`

## Métodos actualizados

| Método          | Archivo                           | Estado            |
|-----------------|-----------------------------------|-------------------|
| every          | src/builtins/array/every.zig     | ✅                |
| filter         | src/builtins/array/filter.zig    | ✅                |
| find           | src/builtins/array/find.zig      | ✅                |
| findIndex      | src/builtins/array/findIndex.zig | ✅                |
| findLast       | src/builtins/array/findLast.zig  | ✅                |
| findLastIndex  | src/builtins/array/findLastIndex.zig | ✅           |
| flatMap        | src/builtins/array/flatMap.zig   | ✅                |
| forEach        | src/builtins/array/forEach.zig   | ✅                |
| map            | src/builtins/array/map.zig       | ✅                |
| some           | src/builtins/array/some.zig      | ✅                |
| reduce         | src/builtins/array/reduce.zig      | ❌ (no soporta thisArg - estándar ECMA no lo incluye) |
| reduceRight    | src/builtins/array/reduceRight.zig | ❌ (no soporta thisArg - estándar ECMA no lo incluye) |

## Referencia

- `specs/arrays/every.md`, `filter.md`, `find.md`, `findIndex.md`, `findLast.md`, `findLastIndex.md`
- `specs/arrays/flatMap.md`, `forEach.md`, `map.md`, `some.md`
- `specs/arrays/reduce.md`, `reduceRight.md`
- `src/builtins/array/`
- `src/evaluator.zig:319-326` — resolución de `this` en Identificador

## Verificación

### Código JavaScript a verificar

```js
// reduce y reduceRight NO tienen thisArg en el estándar ECMAScript
// Solo callback y (opcional) initialValue
// Ver: https://tc39.es/ecma262/#sec-array.prototype.reduce
```

### Nota sobre arrow functions

En JavaScript estándar, las arrow functions **heredan `this` léxicamente** y no pueden recibir `thisArg`. Por eso los tests usan `function(x) { ... }` no `x => ...` para probar el binding de `this`.

### Cómo correr y verificar

1. **Archivo de prueba**: `js/test-thisArg.js`

```js
console.log("filter:", [1,2,3].filter(function(x) { return x > this.min; }, {min: 2}));
console.log("map:", [1,2,3].map(function(x) { return x * this.factor; }, {factor: 2}));
console.log("every:", [1,2,3].every(function(x) { return x > this.min; }, {min: 0}));
console.log("some:", [1,2,3].some(function(x) { return x > this.max; }, {max: 2}));
console.log("find:", [1,2,3].find(function(x) { return x == this.target; }, {target: 2}));
console.log("findIndex:", [10,20,30].findIndex(function(x) { return x == this.target; }, {target: 20}));
console.log("findLast:", [1,2,3,2,1].findLast(function(x) { return x == this.val; }, {val: 2}));
console.log("findLastIndex:", [1,2,3,2,1].findLastIndex(function(x) { return x == this.val; }, {val: 2}));
console.log("flatMap:", [1,2].flatMap(function(x) { return [x, x * this.inc]; }, {inc: 10}));
```

2. **Ejecutar con Lou (Zig)**:
```bash
zig build run -- run js/test-thisArg.js
```

3. **Comparar con Node.js**:
```bash
node js/test-thisArg.js
```

4. **Verificar outputs coinciden**:
- Lou: `filter: [3] map: [2, 4, 6] every: true some: true find: 2 findIndex: 1 findLast: 2 findLastIndex: 3 flatMap: [1, 10, 2, 20]`
- Node: `filter: [ 3 ] map: [ 2, 4, 6 ] every: true some: true find: 2 findIndex: 1 findLast: 2 findLastIndex: 3 flatMap: [ 1, 10, 2, 20 ]`

### Tests unitarios Zig

Los tests existentes en cada archivo `.zig` pueden actualizarse para incluir verificación de `thisArg`:

```zig
test "filter with thisArg accesses this" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();
    try array.elements.append(allocator, .{ .integer = 1 });
    try array.elements.append(allocator, .{ .integer = 2 });
    try array.elements.append(allocator, .{ .integer = 3 });

    // Crear objeto this: {min: 2}
    const this_obj = try Ast.ObjectValue.init(allocator);
    try env.objects.append(allocator, this_obj);
    try this_obj.properties.put("min", .{ .integer = 2 });

    // Callback: function(x) { return x > this.min; }
    const body = try allocator.create(Ast.Node);
    body.* = .{ .BinaryExpression = .{
        .left = try allocator.create(Ast.Node),
        .operator = .GreaterThan,
        .right = try allocator.create(Ast.Node),
    }};
    body.BinaryExpression.left.* = .{ .Identifier = .{ .name = "x" }};
    body.BinaryExpression.right.* = .{ .MemberAccess = .{
        .object = try allocator.create(Ast.Node),
        .property = try allocator.dupe(u8, "min"),
    }};
    body.BinaryExpression.right.MemberAccess.object.* = .{ .Identifier = .{ .name = "this" }};

    const func_node = try allocator.create(Ast.Node);
    func_node.* = .{ .ArrowFunction = .{
        .parameters = try allocator.dupe([]const u8, &.{ "x" }),
        .body = body,
    }};
    try env.setFunction("cb", func_node);

    var args = [_]Types.Value{
        .{ .array = array },
        .{ .string = "cb" },
        .{ .js_object = this_obj },
    };
    const result = Filter(&args, &env);

    try testing.expect(result.value.array.elements.items.len == 1);
    try testing.expectEqual(@as(i64, 3), result.value.array.elements.items[0].integer);
}
```