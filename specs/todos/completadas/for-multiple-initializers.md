# For loop con múltiples inicializadores + Comma operator

## status

✅ COMPLETADO

## Feature

- `for (var i = 0, j = 10; i < 3; i++, j++)` — múltiples declaradores var/let/const en init
- `for (i = 0, j = 10; ...; i++, j++)` — múltiples expresiones en init e increment
- `CommaExpression` como expresión general (funciona en condiciones, increments, grouped `(...)`, statement-level)
- Compound assignments (`+=`, `-=`, `*=`, `/=`, `%=`) con comma operator
- `++`/`--` con comma operator

## Implementación

### AST — `src/ast.zig`
- Nuevo nodo `CommaExpression { expressions: []*Node }`
- `printAst` / `freeAst`

### Parser — `src/parser.zig`
- `parseCommaExpression()` — llama `parsePrecedence(.lowest)` para cada operando, envuelve en `CommaExpression`
- `parseStatement` — labeled block + al final checkea si la expresión es comma, la envuelve
- `parseForLoop` — init/increment/condition usan `parseCommaExpression`; multi-declarator en var/let/const
- `parseWhileLoop`, `parseDoWhileLoop`, `parseIfStatement` — conditions usan `parseCommaExpression`
- `parsePrimary` grouped `(...)` usa `parseCommaExpression`

### Evaluador — `src/evaluator.zig`
- `CommaExpression` handler — evalúa left-to-right, retorna último
- For-loop init con `BlockStatement` se unrollea directamente en `eval_env` (evita nested scope que oculta let/const)
- `is_let_init` busca dentro de `BlockStatement`

### VM — `src/vm.zig`
- `CommaExpression` handler en `expr()` — compila cada expresión, hace `pop` de intermedias, mantiene última
- For-loop init con `BlockStatement` se unrollea directo (evita save/restore que borra let/const)

### Edge cases cubiertos
- `for (let i = 0, j = 1; ...)` — let/const multi-declarator no scoped incorrectamente
- `(1, 2, 3)` — grouped comma expression
- `for (; (console.log("hi"), i < 5); )` — comma en condición
- `i += 1, j *= 2` en increment
- `a, b, c` como statement

## Verificación

```bash
./zig-out/bin/lou run js/test.js 2>&1 | od -c
node js/test.js 2>&1 | od -c
```

Output idéntico al de Node.js en todos los casos.
