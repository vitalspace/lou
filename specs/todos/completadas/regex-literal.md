# Regex literals (`/pattern/flags`)

## status

**completada** — implementada (compat: 84 PASS / 1 FAIL / 1 SKIP)

`tests/compat/regex-literal.lou` produce salida byte-idéntica a Node.

## Problema

El lexer reconocía los literales de regex (token `.Regex`) y ya resolvía la
ambigüedad división/regex con `prev_token_type`, pero el parser no tenía
ningún caso para `.Regex`: cualquier `/hello/` abortaba con `UnexpectedToken`.
El AST tampoco tenía un nodo `RegexLiteral`.

## Implementación

### `src/parser.zig`

- Nuevo caso `.Regex` en `parsePrimary`: consume el token y lo desazucara a
  `NewExpression` con callee `Identifier("RegExp")` y dos `StringLiteral`
  (`pattern` y `flags`).
- Los strings apuntan al buffer fuente (el lexer no duplica el patrón), así
  que los escapes (`\d`, `\/`, clases `[/]`) llegan intactos al constructor.
- La desambiguación sigue en el lexer: `/` tras un token que puede cerrar una
  expresión es división; en posición de operando es regex.

### Tests

- Parser: el literal produce `NewExpression` con patrón y flags correctos;
  `6 / 3` sigue siendo `BinaryExpression` con operador `.Divide`.
- Evaluator: `typeof /hello/gi` es `"object"`, `6 / 3` es `2.0`.

## Verificación

- `diff <(./zig-out/bin/lou run tests/compat/regex-literal.lou) <(node tests/compat/regex-literal.js)`
- `bash tests/compat/run.sh` — 84 PASS / 1 FAIL / 1 SKIP
- `zig test src/main.zig` — 1,072 tests
