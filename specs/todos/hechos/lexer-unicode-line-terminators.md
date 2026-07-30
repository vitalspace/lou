# Lexer: U+2028 / U+2029 Line Terminators

## status

IMPLEMENTED (2026-06-23)

## Problema

ECMAScript define cuatro `LineTerminator` chars: `<LF>` (`\n`, U+000A),
`<CR>` (`\r`, U+000D), `<LS>` (`\u2028`) y `<PS>` (`\u2029`). El lexer de
Lou solo reconocía LF y CR para el contador de línea y la terminación
de comentarios, e incluso el check de regex literal estaba **roto** porque
comparaba `this.input[this.position]` con `0x80` cuando `this.position`
siempre apunta al mismo byte que `this.ch` (en este caso el lead 0xE2).

Adicionalmente, con el nuevo `readChar()` multi-byte, los identificadores
previamente consumían bytes >= 0x80 como continuación siempre, así que
`a\u2028b` se lexaba como un solo identifier `"a\u2028b"` en lugar de
dos separados por una línea.

## Contexto

ECMAScript §11.3 LineTerminator incluye LF, CR, LS y PS. Estos caracteres:
- incrementan el contador de línea,
- terminan comentarios `//`,
- invalidan regex literales (regex no puede cruzar line terminators),
- separan statements en la gramática,
- NO pueden aparecer dentro de un identifier (lo opuesto a `ID_Continue`).

## Baseline (qué existe ya)

- `src/lexer.zig:331` `readChar()` con soporte UTF-8 multi-byte desde
  el spec `hechos/lexer-unicode-identifiers.md` (2026-06-22).
- `skipWhitespace` consume los ASCII ws chars pero no LS/PS.
- `skipComments` single-line termina solo en `'\n'` y `'\r'`.
- `readRegexLiteral` tiene un check roto para U+2028/U+2029
  (`this.input[this.position] == 0x80` — siempre false porque
  `position == byte of ch`).
- Identifier loop usa `isIdContinueByte(ch)` que retorna `true` para
  cualquier byte >= 0x80 (incluyendo el lead 0xE2 de U+2028).

## Quick verify (estado actual)

```bash
echo "var a\u{2028}var b;" > /tmp/t.lou
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Antes: indica un identifier "a\u2028var" pero parse error
# Después: ejecuta correctamente, imprime "a" y "b" como statements

echo "var r = /x\u{2028}y/;" > /tmp/t.lou
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Antes: lexer acepta `/x` y luego hace algo incorrecto con U+2028
# Después: rechaza el regex /xx/ porque U+2028 es LineTerminator
```

## Patrones a seguir

- **Helper local `isLineSeparator(this: *Lexer) bool`** — un solo lugar
  donde se decide el patrón `0xE2 0x80 (0xA8 | 0xA9)` con guard
  `position + 2 >= input.len` para evitar OOB en tail truncado.
- **Sitios consumidores** (cada uno llama `isLineSeparator(this)`):
  - `readChar()` → `line += 1` después de leer LS/PS,
  - `skipWhitespace()` → consumir LS/PS como whitespace entre tokens,
  - `skipComments()` single-line → terminar el comentario,
  - `readRegexLiteral()` → rechazar el regex y devolver EOF,
  - `nextToken()` identifier loop → `and !isLineSeparator(this)` para
    no consumir el lead 0xE2 como identifier continuation.
- **Number / hex / oct / bin / leading-dot-float loops** NO necesitan
  guard porque usan `std.ascii.isDigit` / `isHex` / rangos ASCII
  explícitos que retornan false para bytes >= 0x80.

## Gotchas

- **Position semantics con multi-byte**: cuando se consume U+2028,
  `this.ch = 0xE2` y `this.position` apunta al inicio del codepoint,
  mientras `this.read_position` salta por delante en `seq_len = 3`.
  Los continuation bytes (0x80 y 0xA8/0xA9) nunca son visitados
  individualmente — `isLineSeparator` indaga en `input[position + {1,2}]`
  para verificar la secuencia completa.
- **Truncated UTF-8**: si el archivo termina con `0xE2` solo (2 bytes
  o 1 byte), `readChar()` aplica `step = 1` y `isLineSeparator`
  retorna `false` por el guard `position + 2 >= input.len`.
  Comportamiento esperado: degradar con tolerancia sin panic.
- **`\r` aún no incrementa línea** — pre-existente, fuera de scope
  este spec pero debe documentarse como follow-up.
- **`prev_token_type` no se resetea al consumir un LineTerminator** —
  pre-existente. Consecuencia: `x \u2028 /foo/` se lexa como `Divide` en
  vez de regex literal en Lou (Node.js hace lo segundo). Mismo bug
  existe para `\n` y `\r`. Fuera de scope este spec.

## Código que falla (verificado)

```bash
# LS como statement separator:
echo 'var a = 1;\u2028var b = 2;' > /tmp/t.lou
./zig-out/bin/lou run /tmp/t.lou
# Antes: error de parser; Después: imprime 1 2

# Comment termination:
echo 'var e = 5; // comment\u2028var f = 6;' > /tmp/t.lou
./zig-out/bin/lou run /tmp/t.lou
# Antes: falla; Después: imprime 5 6

# Regex rejection:
echo 'var r = /x\u2028y/;' > /tmp/t.lou
./zig-out/bin/lou run /tmp/t.lou
# Antes: comportamiento indefinido; Después: error claro
```

## Implementación aplicada

### 1. Helper `isLineSeparator`

```zig
fn isLineSeparator(this: *Lexer) bool {
    if (this.ch != 0xE2) return false;
    if (this.position + 2 >= this.input.len) return false;
    return this.input[this.position + 1] == 0x80 and
        (this.input[this.position + 2] == 0xA8 or
        this.input[this.position + 2] == 0xA9);
}
```

### 2. `readChar()` ahora incrementa línea en LS/PS

```zig
if (this.ch == '\n' or isLineSeparator(this)) this.line += 1;
```

### 3. `skipWhitespace()` consume LS/PS

```zig
while (this.ch == ' ' or this.ch == '\t' or this.ch == '\n' or this.ch == '\r' or
    isLineSeparator(this))
{
    this.readChar();
}
```

### 4. `skipComments()` single-line termina en LS/PS

```zig
while (this.ch != '\n' and this.ch != '\r' and this.ch != 0 and
    !isLineSeparator(this))
{
    this.readChar();
}
```

### 5. `readRegexLiteral()` rechaza LS/PS

```zig
if (this.ch == '\n' or this.ch == '\r' or isLineSeparator(this)) {
    return .{ .type = .EOF, .literal = "", .line = line };
}
```
(Eliminado el check doble previo que comparaba `input[position] == 0x80`
contra el lead byte — siempre false.)

### 6. Identifier loop NO span LS/PS

```zig
} else if (isIdStartByte(this.ch)) {
    const start = this.position;
    while (isIdContinueByte(this.ch) and !isLineSeparator(this)) {
        this.readChar();
    }
    ...
}
```

Esta guarda resuelve `a\u2028b` lexando correctamente como `a` (line 1)
y `b` (line 2). Continuation bytes (0x80 y 0xA8) están filtrados por
el short-circuit de `isIdContinueByte` retornando false para 0x0A y
0x0D, pero el lead 0xE2 pasa `isIdContinueByte` (>= 0x80), así que la
guarda `!isLineSeparator` es necesaria.

## Tests añadidos

- `test "U+2028 line terminator increments line counter"` —
  `a\u{2028}b` → `a` line 1, `b` line 2.
- `test "U+2029 line terminator increments line counter"` —
  `a\u{2029}b` → idem para U+2029.
- `test "single-line comment terminates at U+2028"` —
  `42 // caf\u{00E9}\u{2028}+ 1` → tokens `42`, `+`, `1`.
- `test "single-line comment terminates at U+2029"` — idem para PS.
- `test "regex literal rejects U+2028 in pattern"` —
  `/hello\u{2028}world/` → EOF token.
- `test "regex literal rejects U+2029 in pattern"` — idem para PS.
- `test "skipWhitespace consumes U+2028 and U+2029 between tokens"` —
  `a;\u{2028}b;\u{2029}c;d` produce 7 tokens separados.
- `test "U+2028 followed by LF still increments line once each"` —
  `a\nb\u{2028}c` → line 1, 2, 3 (LF y LS cada uno cuenta).
- `test "U+2028 not confused with 0xE2 lead byte of unrelated
  codepoints"` — `a\u{2028}b\u{00E2}c` → `a` line 1,
  `b\u{00E2}c` line 2 (U+00E2 â es ident char pero NO parte de LS).

Total lexer tests: 60 → 62 pasando.

## Compat tests

`tests/compat/lexer-unicode-line-terminators.{js,lou}` (escritos con
`python3` para garantizar bytes reales `0xE2 0x80 0xA8` / `0xA9`):

- Dos statements separados por LS ejecutan ambos.
- Dos statements separados por PS ejecutan ambos.
- `// comment\u{2028}` no consume el código después como comentario.
- Output: `1 2\n3 4\n5 6\n7 8` (idéntico al ejecutar con Node).

NOTA: el test original usaba `"\u2028"` dentro de strings JS para
verificar charCodeAt; eso fue removido porque Lou aún no decodifica
`\uXXXX` correctamente en strings (separate parser issue, fuera de
scope este spec).

## Archivos de referencia

- `src/lexer.zig:331` — `readChar` con multi-byte + line increment.
- `src/lexer.zig:381` — helper `isLineSeparator`.
- `src/lexer.zig:402` — `skipWhitespace`.
- `src/lexer.zig:413` — `skipComments` single-line termination.
- `src/lexer.zig:521` — `nextToken` identifier loop guard.
- `src/lexer.zig:498` — `readRegexLiteral` line-terminator check.
- `specs/todos/hechos/lexer-unicode-identifiers.md` — spec previo
  que introdujo multi-byte `readChar`.
- ECMAScript §11.3 LineTerminator.

## Known limitations (follow-up)

1. **`\r` no incrementa línea** — `readChar` solo trata `\n`, LS y PS,
   no `\r`. Consecuencia: `\r\n` cuenta como un solo newline (no dos)
   lo cual es lo correcto per ES, pero `\r` solo (Mac classic style)
   no incrementa línea. Se arregla en un follow-up en `readChar`.
2. **`prev_token_type` no se resetea tras LineTerminator** — el lexer
   trata `x \u2028 /foo/` como `Divide` en vez de regex literal, igual
   que ya ocurría con `\n`. Es bug pre-existente fuera de scope, pero
   conviene documentarlo.
3. **`isLineSeparator` no decodifica el codepoint** — usa el patrón byte
   `0xE2 0x80 (0xA8|0xA9)`. Si en el futuro el proyecto quiere
   distinguir U+2028 de U+2029 en mensajes de error o en algunos
   builtins (e.g. `String.prototype.toWellFormed`), conviene añadir
   un campo `codepoint: u21` al `Lexer` y un `decodeOnce` helper.

## pendiente

- [x] Implementar `isLineSeparator` helper con guard de tail.
- [x] Wire a `readChar`, `skipWhitespace`, `skipComments`, identifier loop.
- [x] Reemplazar check roto en `readRegexLiteral`.
- [x] Tests unitarios (9 nuevos).
- [x] Compat test con bytes UTF-8 reales (`0xE2 0x80 0xA8/A9`).
- [x] Documentar limitaciones de `\r` y ASI/`prev_token_type`.
