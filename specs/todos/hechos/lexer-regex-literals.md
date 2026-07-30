# Regex Literal Syntax (`/pattern/flags`)

## status
IMPLEMENTED (lexer + parser; runtime pending RegExp builtin wiring)

## Resumen

- **Lexer (`src/lexer.zig`)**: Añadido `TokenType.Regex`, campo `regex_flags` en `Token`, tracking de `prev_token_type`, helper `canEndExpression()`, y función `readRegexLiteral()`. El carácter `/` ahora se desambigua: si el token anterior cierra una expresión → división; si no → regex literal. Añadidas actualizaciones de `prev_token_type` en todos los 22 early returns de `nextToken`.
- **Parser (`src/parser.zig`)**: El token `.Regex` se desugara a `NewExpression(Identifier("RegExp"), [StringLiteral(pattern), StringLiteral(flags)])`, reutilizando el constructor `RegExp` existente.
- **AST (`src/ast.zig`)**: Sin cambios netos (se eliminó el nodo `RegexLiteral` que era innecesario tras el desugaring).
- **Evaluator (`src/evaluator.zig`)**: Sin cambios (el desugaring delega al handler `NewExpression` existente).
- **Tests**: 39/39 lexer tests pasando (añadido test "regex literals", restaurado test "pipeline expression", arreglado test "single character operators"). Compat test `tests/compat/regex-literal.lou` creado.

## Problema

El lexer no reconocía la sintaxis de regex literal `/pattern/flags`. Cualquier `/` se tokenizaba como división, haciendo imposible escribir expresiones regulares inline.

```js
/hello/.test("hello");  // SyntaxError: / tratado como división
const re = /pattern/gi;  // SyntaxError
```

## Solución

### 1. Lexer: desambiguación `/` como división vs regex

Se añadió `prev_token_type` al struct `Lexer` (default `.EOF`). En cada llamada a `nextToken()`, se actualiza `prev_token_type` con el tipo del token retornado.

La función `canEndExpression(tok)` retorna `true` para tokens que cierran una expresión:
- `Identifier`, `Integer`, `Float`, `BigInt`
- `String`, `TemplateString`
- `Null`, `Undefined`, `True`, `False`
- `RParen`, `RBracket`
- `Increment`, `Decrement`
- `Regex`

En el handler de `/`:
```zig
'/' => {
    if (canEndExpression(self.prev_token_type)) {
        // división (o DivideAssign)
    } else {
        return self.readRegexLiteral(tok_line);
    }
}
```

### 2. Lexer: `readRegexLiteral()`

Lee el patrón entre `/` y `/`, respetando `\/` escapado. Luego lee los flags (`g`, `i`, `m`, `s`, `u`, `y`, `d`, `v`). Retorna un token `.Regex` con `literal = pattern` y `regex_flags = flags`.

### 3. Parser: desugaring a `new RegExp()`

`parseRegexLiteral()` crea un AST equivalente a `new RegExp("pattern", "flags")`:
```zig
NewExpression {
    callee: Identifier("RegExp"),
    arguments: [StringLiteral(pattern), StringLiteral(flags)]
}
```

Esto reutiliza el constructor `RegExp` existente sin necesidad de un nuevo nodo AST ni una nueva variante en `Value`.

### 4. Fix: `prev_token_type` en early returns

El `nextToken()` original solo actualizaba `prev_token_type` al final de la función (para tokens que usaban `break :blk`). Los 22 early returns (en number parsing, strings, templates, regex, etc.) no lo actualizaban. Se añadió `this.prev_token_type = .<type>;` antes de cada `return .{...}`.

## Archivos modificados

- `src/lexer.zig` — TokenType.Regex, regex_flags, prev_token_type, canEndExpression, readRegexLiteral, fixes en 22 early returns, tests
- `src/parser.zig` — parseRegexLiteral con desugaring a NewExpression
- `src/ast.zig` — (cleanup: removido RegexLiteral)
- `src/evaluator.zig` — (cleanup: removido RegexLiteral handler)
- `tests/compat/regex-literal.{lou,js}` — compat test (limitado por falta de RegExp builtin)

## Limitación conocida

El constructor `RegExp` no está registrado como builtin en `src/builtins/builtins.zig` (falta `RegExpConstructor` en `BUILTIN_FUNCTIONS`). Además, el tipo `RegExpValue` no tiene una variante `.regexp` en el union `Value` de `src/types/runtime.zig`. Esto impide la evaluación completa de regex literales en runtime. El desugaring del parser es correcto y funcionará una vez que `RegExp` esté completamente integrado.

## Verificación

```bash
# Lexer tests
zig test src/lexer.zig

# Compat test (parcial — división funciona, typeof falla por falta de RegExp builtin)
./zig-out/bin/lou run tests/compat/regex-literal.lou
node tests/compat/regex-literal.js
```
