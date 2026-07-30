# Lexer: unsigned right shift >>>

## status

**COMPLETADO** — verificado 2026-07-30

`unsigned-right-shift.lou` PASSes with byte-identical output to Node.js. Added `>>>` and `>>>=` across evaluator and VM. Also fixed `<<=` and `>>=` compound assignments (previously never implemented — masked by test crashing on `>>>=` first).

## Problema

El operador `>>>` (unsigned right shift) no estaba en el lexer ni en el evaluador. Tampoco existían las versiones compound assignment (`>>>=`, `>>=`, `<<=`).

## Resumen de implementación

Se tocaron 4 archivos:

1. **`src/lexer.zig`** — Añadidos 4 nuevos TokenTypes: `UnsignedRightShift`, `UnsignedRightShiftAssign`, `LeftShiftAssign`, `RightShiftAssign`. Handler `<`: añadido `<<=`. Handler `>`: reescrito con longest-match (`>>>=` antes de `>>>` antes de `>>=` antes de `>>` antes de `>=` antes de `>`). 37/37 tests pasan.

2. **`src/ast.zig`** — `getTokenPrecedence`: `UnsignedRightShift` → `.Comparison` (mismo nivel que `>>`/`<<`). `LeftShiftAssign`, `RightShiftAssign`, `UnsignedRightShiftAssign` → `.Assign`.

3. **`src/evaluator.zig`** — BinaryExpression paths:
   - BigInt: `>>>` → `UnsupportedOperator` (TypeError en JS)
   - Integer: zero-fill right shift via `@as(u32, @bitCast(@as(i32, @truncate(left)))) >> shift` con shift count enmascarado a `u5` (0-31)
   - Float/general: convierte a int primero, mismo zero-fill
   - Compound assignment: añadidos casos `LeftShiftAssign`, `RightShiftAssign`, `UnsignedRightShiftAssign` (solo integer ↔ integer)

4. **`src/vm.zig`** — Añadido opcode `unsigned_right_shift`. Compilador mapea `.UnsignedRightShift` al opcode. Compound assignments mapeados: `.LeftShiftAssign` → `.left_shift`, `.RightShiftAssign` → `.right_shift`, `.UnsignedRightShiftAssign` → `.unsigned_right_shift`.

## Cambios aplicados

```zig
// lexer.zig — handler de '>' (longest-match)
'>' => blk: {
    if (this.peekChar() == '>') {
        this.readChar();
        if (this.peekChar() == '>') {
            this.readChar();
            if (this.peekChar() == '=') { // >>>= 
                this.readChar(); break :blk .UnsignedRightShiftAssign
            }
            break :blk .UnsignedRightShift  // >>>
        }
        if (this.peekChar() == '=') { // >>=
            this.readChar(); break :blk .RightShiftAssign
        }
        break :blk .RightShift  // >>
    } else if (this.peekChar() == '=') {
        this.readChar(); break :blk .GreaterThanOrEqual  // >=
    } else {
        break :blk .GreaterThan
    }
},
```

```zig
// evaluator.zig — zero-fill right shift
.UnsignedRightShift => {
    const shift: u5 = @intCast(right_int & 31);
    return .{ .integer = @as(i64, @as(u32, @bitCast(@as(i32, @truncate(left_int)))) >> shift) };
},
```

## Verificación

```bash
./zig-out/bin/lou run tests/compat/unsigned-right-shift.lou
diff <(./zig-out/bin/lou run tests/compat/unsigned-right-shift.lou 2>&1) \
     <(node tests/compat/unsigned-right-shift.js 2>&1)
# Diff vacío → PASS
```

## pendiente

- (ninguno — spec implementado y verificado)
