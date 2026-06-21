# BigInt increment/decrement (`++`/`--` on BigInt)

## status
implementado

## Problema
`tests/compat/bigint-increment-decrement.lou` fallaba con dos síntomas:

1. **Postfix `x++` retornaba el valor nuevo, no el viejo.** El parser desugaba
   `x++` a `Assignment { name: x, value: x + 1.0 }`, y `evaluate(.Assignment)`
   retorna el valor asignado. Por lo tanto `let y = x++` daba el valor nuevo
   en vez del viejo, y `x++ + 1n` quedaba corrido por uno.

2. **Comparación BigInt en el VM.** El opcode `.lt` / `.gt` de `src/vm.zig`
   usaba `toF64()` que devuelve `null` para `big_int`, lo que resulta en
   `0.0 < 0.0 = false`. Esto rompía los bucles `for (let i = 0n; i < 5n; i++)`
   porque la condición nunca era verdadera.

## Contexto
ES2020 permite `++` y `--` sobre BigInts preservando el tipo:

```js
let x = 1n;
x++;        // x = 2n
let y = x++;  // y = 2n (postfix: viejo), x = 3n
```

El VM bytecode compiler delega nodos no especializados al AST evaluator vía
`eval_node`; los nodos especializados se compilan a bytecode directo. La fix
correcta es un nodo AST dedicado (`UpdateExpression`), no un desugar a
`Assignment` con `BinaryExpression`, porque la semántica de valor retornado
(postfix = viejo, prefix = nuevo) no se puede expresar con `Assignment` sin
perder la identidad del valor viejo.

## Implementacion

### `src/ast.zig` — nodo `UpdateExpression`

```zig
UpdateExpression: struct {
    name: []const u8,
    prefix: bool,
    operator: TokenType, // .Increment or .Decrement
},
```

`freeAst` y `printAst` se actualizan con un caso trivial (no tiene hijos).

### `src/parser.zig` — desugar a `UpdateExpression`

Las cuatro formas (`++i`, `--i`, `i++`, `i--`) ahora construyen
`UpdateExpression` directamente, en lugar de `Assignment { value: x ± 1.0 }`.

### `src/evaluator.zig` — `.UpdateExpression` en `evaluate()`

```zig
.UpdateExpression => |u| {
    const current = env.get(u.name) orelse return error.UndefinedVariable;
    const new_val = blk: {
        switch (current) {
            .big_int => |bi| {
                const result = ast.BigIntValue.init(env.allocator) catch ...;
                env.bigints.append(env.allocator, result) catch {};
                const delta = ast.BigIntValue.fromString(env.allocator, "1") catch ...;
                env.bigints.append(env.allocator, delta) catch {};
                if (u.operator == .Increment)
                    result.value.add(&bi.value, &delta.value) catch ...;
                else
                    result.value.sub(&bi.value, &delta.value) catch ...;
                break :blk ast.Value{ .big_int = result };
            },
            .integer => |i| { /* @addWithOverflow / @subWithOverflow, fallback a float */ },
            .float   => |f| { break :blk ast.Value{ .float = f ± 1.0 }; },
            else     => return error.InvalidAssignmentTarget,
        }
    };
    try env.setInScope(u.name, new_val);
    return if (u.prefix) new_val else current;
},
```

Decisiones:
- **Sin overflow a Number**: la rama `.big_int` usa `std.math.big.int.Managed`
  directamente, así que `2n ** 64n + 1n` se mantiene BigInt sin promoverse a
  float (igual que Node).
- **Postfix vs prefix**: el valor retornado es `current` (viejo) para postfix,
  `new_val` (nuevo) para prefix. La rama de almacenamiento no muta `current`;
  el resultado nuevo se registra en `env.bigints` para cleanup.
- **Overflow en `integer`**: `@addWithOverflow` / `@subWithOverflow` caen a
  `float` igual que la aritmética regular (consistente con el resto del
  evaluador).

### `src/vm.zig` — bytecode de `UpdateExpression`

El compilador emite una secuencia de opcodes existentes, sin opcodes nuevos.
La constante `1.0` es `Float`; el `add` / `sub` BigInt-aware del VM la
convierte a BigInt cuando el otro operando es BigInt.

```text
prefix  ++x:  get_global x; constant 1.0; add|sub; dup;  set_global x
postfix x++:  get_global x; get_global x; constant 1.0; add|sub; dup;
               set_global x; pop
```

`tryOptimizeSimpleLoop` y `optimizations.zig::optimizeSimpleForLoop` también
reconocen `UpdateExpression` como incremento válido (`name == loop_var`,
`!prefix`, `operator == .Increment`), manteniendo la optimización de
acumulador para enteros.

### `src/vm.zig` — `.lt` / `.gt` BigInt-aware

```zig
.lt => {
    const b = self.pop(); const a = self.pop();
    if (a == .big_int and b == .big_int)
        self.push(.{ .boolean = a.big_int.compare(b.big_int) == .lt });
    else {
        const av = toF64(a) orelse 0.0; const bv = toF64(b) orelse 0.0;
        self.push(.{ .boolean = av < bv });
    }
},
.gt => { /* simétrico */ },
```

`.le` y `.ge` se siguen implementando como `.gt` + `.not_` y `.lt` + `.not_`,
así que heredan el fix automáticamente.

## Tests

`tests/compat/bigint-increment-decrement.lou` y su `.js` — outputs idénticos
al ejecutar `./zig-out/bin/lou run` y `node`.

Cubre:
- `a++` postfix (retorna viejo) y `++a` prefix (retorna nuevo).
- `--` postfix y prefix.
- Negativos (`0n--` → `-1n`, `-5n--` → `-6n`).
- Round-trip `0n` → `++` → `--` → `0n`.
- BigInt > i64 (`2n ** 64n + 1n` se mantiene como BigInt, sin promoción).
- Cadenas de `chain++`.
- Expresiones compuestas: `a++ + 1n`, `++a + 1n`.
- Dentro de bucles `for (let i = 0n; i < 5n; i++) { acc++; }` (requiere
  comparación BigInt en VM).
- `typeof` permanece `"bigint"` tras `++` / `--`.
- Sanity: Number (`5` → `6`) sigue funcionando; mezclar Number y BigInt en el
  mismo scope no produce coerción cruzada.

### Verificacion
```bash
./zig-out/bin/lou run tests/compat/bigint-increment-decrement.lou
diff <(./zig-out/bin/lou run tests/compat/bigint-increment-decrement.lou) \
     <(node tests/compat/bigint-increment-decrement.js)
```

## Archivos de referencia
- `src/ast.zig:36` — `UpdateExpression` en `NodeType`.
- `src/ast.zig:116` — struct `{ name, prefix, operator }`.
- `src/parser.zig:440,481,546,558` — desugar a `UpdateExpression`.
- `src/evaluator.zig:916` — caso `.UpdateExpression` en `evaluate()`.
- `src/vm.zig:818` — compilación a bytecode.
- `src/vm.zig:497` — reconocimiento en `tryOptimizeSimpleLoop`.
- `src/vm.zig:1117` — `.lt` / `.gt` BigInt-aware.
- `src/optimizations.zig:217` — reconocimiento en `optimizeSimpleForLoop`.

## Edge cases encontrados durante implementación
- **BigInt muy grande (`> i64`)**: ya estaba manejado en `add/sub`/`exponent`.
- **Comparación `i < 5n` en `for`**: el VM tenía `.lt`/`gt` sin soporte
  BigInt, lo que rompía el bucle entero. Fix en `src/vm.zig:1117`.
- **`x++` con postfix**: requiere nodo AST dedicado — el desugar a
  `Assignment` no puede expresar "retornar el viejo".
