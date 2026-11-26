# Switch/Case

## status

**completado** — 2026-11-26 (compat: 67 PASS / 18 FAIL / 1 SKIP)

`tests/compat/switch-case.{js,lou}` produce output byte-idéntico a Node.
El lexer, el AST y `printAst`/`freeAst` ya existían; faltaban el parser, el
compilador de la VM y una implementación real en el evaluador (había un stub).

```bash
diff <(./zig-out/bin/lou run tests/compat/switch-case.lou) <(node tests/compat/switch-case.js)
# sin diferencias
```

## Problema original

`switch` producía `error: UnexpectedToken`: los tokens `.Switch`, `.Case` y
`.Default` existían pero `parseStatement` no los despachaba. La VM tampoco
tenía caso para `.SwitchStatement` y el evaluador devolvía `void` sin evaluar
nada.

## Implementación

### Parser (`src/parser.zig`)

`parseSwitchStatement` parsea:

```
switch (discriminante) {
    case expr: sentencias...
    default:    sentencias...
}
```

- El discriminante se parsea con `parseCommaExpression` y se evalúa una sola vez.
- Cada cláusula produce un `SwitchCase { test_expr: ?*Node, consequent: *Node }`
  donde `consequent` es un `BlockStatement`.
- `default` tiene `test_expr = null` y puede aparecer en cualquier posición.
- Una cláusula vacía (`case 1: case 2:`) genera un bloque vacío.

### VM (`src/vm.zig`)

`switchStmt` compila el discriminante y lo guarda en un binding oculto
(`__switch_disc_<offset>`) para poder compararlo con cada `case` sin
reevaluarlo:

```
expr(discriminante); def_global oculto
para cada case con test:
    get_global oculto; expr(test); strict_eq; jump_if_false siguiente
    jump cuerpo_i
jump default_0_fin
cuerpo_0: ... cuerpo_1: ... (fall-through natural)
```

- La comparación usa `strict_eq` (igualdad estricta), como exige JS.
- Los tests se emiten en orden; solo se ejecutan hasta encontrar el primer
  match (los posteriores no se evalúan).
- Si ningún test coincide se salta al cuerpo de `default` (o al final).
- `break` dentro del switch salta al final del switch. `popLoop` parchea esos
  saltos.
- Se añadió `LoopInfo.is_switch`: el `break` sin etiqueta puede apuntar a un
  switch, pero `continue` lo ignora y sigue apuntando al loop que lo contiene.
- `break etiqueta` sigue resolviéndose por la entrada de bloque que crea
  `LabeledStatement`, así que `foo: switch (...) { break foo; }` funciona.
- `ptchTo(pos, target)` permite parchear saltos a posiciones absolutas.

### Evaluador (`src/evaluator.zig`)

- Evalúa el discriminante y recorre los `case` en orden con `valuesEqual`
  (estricta), deteniéndose en el primer match y recordando la posición de
  `default`.
- Ejecuta los consecuentes desde el match (o desde `default`) con
  fall-through.
- Consume `break` sin etiqueta o con la etiqueta del switch; propaga
  `break`/`continue`/`return`/`yield` que pertenecen a construcciones
  externas.

### Igualdad estricta

Al probar el switch dentro de loops se descubrió que `valStrictEq` era
asimétrica: `1 === 1.0` daba `false` (la rama `.integer` no contemplaba
`.float`, mientras que la rama `.float` sí contemplaba `.integer`). Ahora
ambas ramas comparan como Number, como en JS. Esto también arregla
comparaciones estrictas entre enteros y floats en la VM.

## Tests

- `tests/compat/switch-case.{js,lou}` — 15 bloques: match, default, `break`
  vs fall-through, default en medio, sin match, discriminante booleano,
  switch anidado y `case` con `break`.
- Casos extra verificados contra Node:
  - `default` en medio y al principio, con fall-through posterior;
  - `case` con efectos laterales (solo se evalúan hasta el match);
  - `switch (i)` dentro de `for` con `continue`/`break`;
  - `break outer` desde un switch anidado;
  - `break foo` sobre un switch etiquetado;
  - `switch` vacío, solo `default`, sobre `null`/`undefined`, strings y
    booleanos;
  - `return` desde un `case`; `let` dentro de un `case`.

## Limitaciones conocidas

- La VM deja el binding oculto `__switch_disc_*` en el entorno global; no es
  visible como variable de usuario pero aparece si se enumeran las claves
  internas del entorno.
- No se implementa TDZ ni error de sintaxis por `default` duplicado.

## Referencias

- `src/parser.zig` (`parseSwitchStatement`)
- `src/vm.zig` (`switchStmt`, `ptchTo`, `LoopInfo.is_switch`)
- `src/evaluator.zig` (rama `.SwitchStatement`)
- `src/ast.zig` (`SwitchStatement`, `SwitchCase`)