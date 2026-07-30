# Object literal: parenthesized single-arg arrow, then another property

## status

pendiente

## Problema

En un object literal, una propiedad cuyo valor es un arrow con un único
parámetro entre paréntesis `(...args) => expr` (en vez de la forma
ident-only `x => expr`) seguida de otra propiedad produce un error de
parseo, aunque cada patrón por separado sí funciona.

```js
// Funciona — un solo prop, sin siguiente prop
const a = { singleArrow: (x) => x * 3 };
console.log(a.singleArrow(4));              // 12

// Funciona — forma ident-only sin paréntesis
const b = { double: x => x * 2, square: x => x * x };
console.log(b.double(5), b.square(5));      // 10 25

// Falla — parens single-arg arrow con cuerpo de expr, + otro prop
const c = { singleArrow: (x) => x * 3, other: function() { return 1 } };
console.log(c.singleArrow(4), c.other());
```

```
$ ./zig-out/bin/lou run c.lou
error: ExpectedCommaOrRBrace
/home/lou/src/parser.zig:806
```

## Contexto

Spec hermano: [object-method-call.md](./object-method-call.md) (status:
COMPLETADO 2026-06-29). El fix principal de ese spec cubre el dispatch
evaluator-side de `obj.f()` sobre propiedades de tipo `.function` /
`.closure`. Este edge case es un bug **parser-side** que vive en
`parseObjectLiteral` + `parseArrowFunction` y nunca fue cubierto.

Misma causa raíz que
[object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md):
`parseArrowFunction` para cuerpos non-block delega a `parseStatement`,
que a su vez consume comas de statement-level (vía
`// Handle comma operator at statement level`). Esa coma consumida es la
que delimitaría la siguiente propiedad del object literal.

Diferencia respecto al caso zero-arg: el cuerpo `x * 3` requiere que
`parsePrimary` haga un fold binary-op para llegar al BinaryExpression.
Eso termina ocurriendo, pero antes de retornar al caller, el fold
completo del body se hace dentro de un `parseStatement` que también
come la comma.

Patrones adyacentes que sí funcionan:
- `{ singleArrow: x => x * 3, ... }` — forma ident-only (parsePrimary
  detecta `=>` directamente, ya no entra en `parseArrowFunction`).
- `{ singleArrow: (x) => x * 3 }` — sin siguiente prop.
- `{ singleArrow: (x) => { return x * 3; }, ... }` — cuerpo en bloque.

Patrón adyacente que falla por la misma razón raíz:
- `{ f: () => 99, g: ... }` — ver [./object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md).

## Baseline (qué existe ya)

- `parseArrowFunction` (parser.zig:1276+) rama else-branch usa
  `parseStatement` para bodies non-block.
- `parsePrimary(.Identifier)` (parser.zig:343) tiene fast-path para
  `Identifier => Arrow` (forma ident-only) que evita entrar a
  `parseArrowFunction`. Este fast-path NO cubre `() => expr` ni
  `(x) => expr` — esas formas siempre pasan por `parseArrowFunction`.
- `parseStatement` permite comma-expression al nivel de statement y la
  construye como `CommaExpression` (parser.zig:178-194).

## Quick verify (estado actual)

```bash
printf '%s' 'const o = { singleArrow: (x) => x * 3, other: function() { return 1 } };
console.log(o.singleArrow(4), o.other());' > /tmp/r.lou
/home/lou/zig-out/bin/lou run /tmp/r.lou 2>&1 | head -3
# Actual: error: ExpectedCommaOrRBrace at parser.zig:806
```

## Patrones a seguir

- Mismo patrón de fix que
  [object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md).
- EmmaScript ArrowFunction production: cuerpo es `AssignmentExpression`,
  no statement.

## Gotchas

- **No es el fast-path de ident-only**. El fast-path en `parsePrimary`
  para `Identifier => Arrow` solo cubre la forma `x => expr` y bypass
  completamente `parseArrowFunction`. La forma `(x) => expr` no entra
  ahí, así que el bug le pega igual.
- **Tampoco es issue de parsing de parámetros**. Los parámetros
  paréntesis simple se parsean correctamente — el problema es solo en
  el cuerpo cuando va seguido de otra prop.
- **Cuerpo con binary op es el caso natural** (la mayoría de arrow con
  cuerpo non-block tiene al menos una binary op), así que el bug es muy
  fácil de disparar en código real.
- Si el root cause es común con
  [object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md),
  un solo fix los cubre.
- Cross-check con
  [object-method-call-edge-function-and-arrow.md](./object-method-call-edge-function-and-arrow.md):
  ese caso produce `ExpectedPropertyName`, no
  `ExpectedCommaOrRBrace`. Probablemente sea un bug distinto a
  investigar por separado.

## Código que falla

```js
// Caso mínimo:
const o = { singleArrow: (x) => x * 3, other: 1 };
console.log(o.singleArrow(4), o.other);    // Actual: parse error

// Multi-arg, cuerpo con binary op:
const o2 = { sum: (a, b) => a + b, c: 3 };
console.log(o2.sum(1, 2), o2.c);          // Actual: parse error

// Multi-arg, cuerpo binario con propiedad calculada:
const o3 = { m: (x, y) => x * y + 1, n: 0 };

// Follow-up prop de arrow (forma ident-only) funciona:
const o4 = { a: x => x + 1, b: y => y + 1 };  // OK
```

## Implementación sugerida

### Diagnosis (paso previo al fix)

1. En `parseArrowFunction` (parser.zig:1276+), añadir log
   `std.debug.print` antes del `if (.LBrace) … else parseStatement` y
   después del `parseStatement`/`parseBlockStatement` call. Verificar
   que el `parseStatement` SÍ entra en el comma-handling block
   (`// Handle comma operator at statement level`).

2. Confirmar la cadena: `parseObjectLiteral → parseExpression →
   parsePrecedece(.lowest) → parsePrimary(.LParen → parseArrowFunction
   → parseStatement → return CommaExpression(BinaryExpr(x,*,3),
   Identifier('other')), current_token=':'`. De nuevo,
   `ExpectedCommaOrRBrace` se dispara porque el `:` de `other:` está en
   lugar de `,` o `}`.

### Fix propuesto

Idéntico al de
[object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md):
cambiar `parseStatement` → `parseExpression` en la rama else-branch de
`parseArrowFunction`.

```zig
// Actual:
const body = if (this.current_token.type == .LBrace)
    try this.parseBlockStatement()
else
    try this.parseStatement();

// Propuesto:
const body = if (this.current_token.type == .LBrace)
    try this.parseBlockStatement()
else
    try this.parseExpression();
```

### Lateral effects a auditar

- El cambio NO debe romper la forma ident-only `x => expr` porque
  esa ruta bypassa `parseArrowFunction` (parsePrimary fast-path).
- Sí afecta a TODOS los arrow functions no-block en posición value
  dentro de un object literal seguido de otra prop — eso es
  exactamente lo que se quiere cubrir.

## Verificación

```bash
# 1. Lou produce el output esperado
printf '%s' 'const o = { singleArrow: (x) => x * 3, other: 1 };
console.log(o.singleArrow(4), o.other);' > /tmp/r.lou
./zig-out/bin/lou run /tmp/r.lou
# Esperado: 12 1

# 2. Diff contra Node
diff <(/home/lou/zig-out/bin/lou run /tmp/r.lou 2>&1) \
     <(node /tmp/r.js 2>&1)
# Debe ser vacío

# 3. Compat suite
bash tests/compat/run.sh
```

## pendiente

- [ ] Confirmar la causa raíz con logs en `parseArrowFunction` y
      `parseStatement`.
- [ ] Aplicar el mismo fix que
      [object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md).
- [ ] Verificar que los tres edge cases adyacentes se cierran con el
      mismo cambio.
- [ ] Considerar unit test en `src/parser.zig` que abarque `parseArrowFunction`
      body parsing explícitamente.
