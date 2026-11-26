# typeof en variables no declaradas

## status

**COMPLETADO** — verificado 2026-11-26 (compat: 60 PASS / 25 FAIL / 1 SKIP)

`typeof undeclaredVar` devuelve `"undefined"` sin lanzar y `tests/compat/typeof-undeclared.lou`
pasa byte-identical. La tolerancia se limita al identifier directo: `typeof (x + 1)` o
`typeof nope.prop` con `x`/`nope` sin declarar siguen lanzando, como Node.

## Problema

`typeof` en una variable no declarada lanzaba `UndefinedVariable`. ECMAScript 13.5.3 dice que si
el operando es una Reference a un binding no declarado, `typeof` retorna `"undefined"` sin
evaluar el operando. Es uno de los pocos casos donde JS permite tocar una variable inexistente.

## Solución

- `src/vm.zig` (`.TypeOfExpression`): si el operando es `.Identifier`, el compilador emite
  `eval_node` en vez de compilar la carga del identificador. El opcode de carga lanzaba
  `UndefinedVariable` antes de que el evaluador pudiera decidir; delegando, el lookup ocurre
  dentro de `evaluate`, que sí distingue el caso.
- `src/evaluator.zig` (`.TypeOfExpression`): el `catch error.UndefinedVariable` ya existía, pero
  atrapaba cualquier error del operando. Ahora solo se aplica cuando `t.operand` es un
  `.Identifier` directo; el resto se evalúa normal y propaga el error.

## Gotchas

- `typeof (x + 1)` con `x` sin declarar debe lanzar (no es una Reference directa).
- `typeof nope.prop` también lanza: se evalúa `nope` como referencia.
- Un identifier declarado con valor `undefined` no lanza; el valor se evalúa normal.

## Tests

- `tests/compat/typeof-undeclared.lou` + `.js`: `typeof` sobre tres variables no declaradas,
  declaradas, expresión, función y `null`.
- Verificación manual:

```bash
diff <(./zig-out/bin/lou run tests/compat/typeof-undeclared.lou) \
     <(node tests/compat/typeof-undeclared.js) && echo OK
```
