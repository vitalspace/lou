# Lexer: Hex, Octal, Binario

## status

**COMPLETADO** — verificado 2026-07-30

`hex-octal-binary.lou` PASSes with byte-identical output to Node.js. Parser `parseIntegerLiteral` now auto-detects base from prefix (`0x`/`0o`/`0b`).

## Problema

El lexer solo soportaba números decimales. `0xFF` se tokenizaba como `0` + identificador `xFF`. Lo mismo para `0o77` (octal) y `0b1010` (binario).

## Resumen de implementación

1. **`src/lexer.zig`** — En el bloque de parseo numérico, cuando el primer dígito es `0`, se verifica el siguiente carácter para detectar prefijos `x`/`X` (hex, lee con `isHex`), `o`/`O` (octal, lee dígitos 0-7), `b`/`B` (binario, lee 0/1). Si no es un prefijo válido, se continúa con el parseo decimal normal. Los prefijos inválidos (sin dígitos) devuelven solo `"0"` como literal.

2. **`src/parser.zig`** — `parseIntegerLiteral` ahora detecta automáticamente la base a partir del prefijo. Extrae los dígitos después del prefijo (`literal[2..]`) y usa `parseInt` con base 16/8/2 según corresponda. Literales decimales usan base 10 sin cambios.

3. **Unit test** — Añadido test "hex octal binary literals" en `src/lexer.zig` con 9 casos: `0xFF`, `0X1A`, `0o77`, `0O52`, `0b1010`, `0B1100`, `0`, `42`, `0xFFFFFFFF`. 36/36 tests pasan.

4. **Compat test** — `tests/compat/hex-octal-binary.{lou,js}` con 9 casos incluyendo expresiones aritméticas. Diff vacío contra Node.js.

## Cambios aplicados

```zig
// src/lexer.zig — number parsing block, after "if (std.ascii.isDigit(this.ch))"
if (this.ch == '0') {
    this.readChar(); // consume '0'
    const prefix = this.ch;
    if (prefix == 'x' or prefix == 'X') {
        this.readChar();
        if (!std.ascii.isHex(this.ch)) {
            return .{ .type = .Integer, .literal = this.input[start..(start+1)], ... };
        }
        while (std.ascii.isHex(this.ch)) { this.readChar(); }
        return .{ .type = .Integer, .literal = this.input[start..this.position], ... };
    } else if (prefix == 'o' or prefix == 'O') {
        // octal (digits 0-7)
    } else if (prefix == 'b' or prefix == 'B') {
        // binary (digits 0-1)
    }
    // fall through to normal decimal parsing
}
```

```zig
// src/parser.zig — parseIntegerLiteral
const base: u8, const digits: []const u8 = if (literal.len >= 2 and literal[0] == '0') switch (literal[1]) {
    'x', 'X' => .{ 16, literal[2..] },
    'o', 'O' => .{ 8, literal[2..] },
    'b', 'B' => .{ 2, literal[2..] },
    else => .{ 10, literal },
} else .{ 10, literal };
const value = try std.fmt.parseInt(i64, digits, base);
```

## Verificación

```bash
./zig-out/bin/lou run tests/compat/hex-octal-binary.lou
diff <(./zig-out/bin/lou run tests/compat/hex-octal-binary.lou 2>&1) \
     <(node tests/compat/hex-octal-binary.js 2>&1)
# Diff vacío → PASS
```

## pendiente

- (ninguno — spec implementado y verificado)
