# Object literal: zero-arg arrow with literal body, then another property

## status

pendiente

## Problema

En un object literal, una propiedad cuyo valor es un arrow de cero
argumentos y cuerpo **literal** (no bloque) seguida de otra propiedad
produce un error de parseo, aunque cada patrón por separado sí funciona.

```js
// Funciona — un solo prop, sin siguiente prop
const a = { f: () => 99 };
console.log(a.f());                          // 99

// Funciona — sin arrow
const b = { f: function() { return 99 }, g: function() { return 1 } };
console.log(b.f(), b.g());                   // 99 1

// Falla — zero-arg arrow con cuerpo literal + otro prop
const c = { f: () => 99, g: function() { return 1 } };
console.log(c.f());
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

`parseArrowFunction` llama a `parseStatement` para el cuerpo cuando el
cuerpo no es un bloque (`{ ... }`). `parseStatement` a su vez acepta
comas a nivel de statement (devuelve un `CommaExpression`), y ese consumo
greedy de comas rompe la delimitación de propiedades del literal que
contiene al arrow.

Patrones adyacentes que sí funcionan:
- `{ f: () => 99 }` — solo el prop del arrow (no hay siguiente prop que
  el parser intente leer).
- `{ f: () => { return 99; }, g: function() { return 1 } }` — el cuerpo
  es un bloque, así que `parseArrowFunction` toma la rama
  `parseBlockStatement` en vez de `parseStatement`. La coma entre
  propiedades queda intacta.
- `{ f: () => 99, g: 1 }` también falla — no es específico del tipo de
  la siguiente propiedad.

Patrón adyacente que falla por la misma razón raíz:
- `{ f: (x) => x * 3, g: ... }` — ver [./object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md).

## Baseline (qué existe ya)

- `parseArrowFunction` (parser.zig:1276+) tiene dos ramas para el body:
  `if (.LBrace) parseBlockStatement else parseStatement`. La rama
  `parseStatement` está mal aquí porque **un cuerpo de arrow NO es una
  statement** — es una expresión que puede continuar en
  object-literal-prop-list al regresar al caller.
- `parseStatement` (parser.zig:343+) maneja comma a nivel statement
  (`// Handle comma operator at statement level`).
- `parseObjectLiteral` espera que después del value expr vuelva un
  `.Comma` o un `.RBrace`, no otra cosa.

## Quick verify (estado actual)

```bash
printf '%s' 'const o = { f: () => 99, g: function() { return 1; } };
console.log(o.f());' > /tmp/r.lou
/home/lou/zig-out/bin/lou run /tmp/r.lou 2>&1 | head -3
# Actual: error: ExpectedCommaOrRBrace at parser.zig:806
```

## Patrones a seguir

- `specs/todos/hechos/equality-coercion.md` y otros completados — cómo
  se reporta un edge case que requiere un fix parser-side más pequeño.
- `parseFunctionExpression` (`parseFunctionDeclaration` cuando el nodo
  padre es parsePrimary con `.Fn`) usa la misma estructura
  `if (.LBrace) blockStatement else statement`. Si la rueda se cambia
  para arrow bodies, hay que considerar si `FunctionDeclaration.body`
  también debe dejar de pasar por `parseStatement` (probablemente no —
  `fn foo() expr` es una *forma Lou* explícita y debe seguir siendo un
  statement-level shortcut).
- ECMAScript ArrowFunction production: cuerpo es `AssignmentExpression`,
  NO statement. La rama `parseArrowFunction`'s else-branch debe llamar a
  `parseAssignmentExpression` (o equivalente que respete el final de
  arrow).

## Gotchas

- **No es un bug de TokenType**. Los tokens se emiten correctamente;
  el fallo es de la lógica de "qué agrego a qué lista de tokens cuando
  se anida".
- **No romper `fn foo() expr`**: la forma `function foo() expr` o
  `fn foo() expr` (Lou extension) sigue siendo statement-level, así
  que `parseFunctionDeclaration`'s `else parseStatement` debe quedarse.
- **El bug es la asimetría**: arrow bodies non-block son EXPRESIONES;
  function bodies non-block son STATEMENTS (Lou-specific).
- **Cuerpo con binary op también cae en el else-branch**: `() => a + b`
  en propiedad seguida de otra prop debería fallar igual que `() => 99`
  (misma ruta por `parseStatement`).
- Podría estar relacionado con:
  [object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md)
  y
  [object-method-call-edge-function-and-arrow.md](./object-method-call-edge-function-and-arrow.md).
  Si el root cause es común, conviene un solo fix que cubra los tres.

## Código que falla

```js
// Caso mínimo:
const o = { f: () => 99, g: 1 };
console.log(o.f(), o.g);
// Actual: error: ExpectedCommaOrRBrace

// Cuerpo con ops binarias (misma ruta):
const o2 = { f: () => 1 + 2, g: 3 };
console.log(o2.f(), o2.g);

// Cuerpo con string (misma ruta):
const o3 = { f: () => "x", g: "y" };

// Follow-up prop de arrow funciona solo:
const o4 = { f: () => 99 };           // OK — 99
```

## Implementación sugerida

### Diagnosis (paso previo al fix)

1. En `parseArrowFunction` (parser.zig:1276+), añadir un log
   `std.debug.print` antes del `if (.LBrace) … else parseStatement` que
   muestre `current_token` después de consumir `=>`. Verificar que para
   `() => 99` el token es exactamente `.Integer`.

2. En `parseStatement` (parser.zig), añadir logs antes y después del
   bloque `// Handle comma operator at statement level`. Verificar que
   la comma-handling SÍ dispara cuando el cuerpo del arrow es `99` y la
   siguiente prop es `g:`.

3. Confirmar la cadena: `parseObjectLiteral → parseExpression →
   parsePrecedece(.lowest) → parsePrimary(.LParen → parseArrowFunction
   → parseStatement → return CommaExpression(99, Identifier('g')),
   current_token=':'`. El ExpectedCommaOrRBrace en `parseObjectLiteral`
   es entonces derivado: el `:` de `g:` se ve en lugar de `,` o `}`.

### Fix propuesto

Cambiar en `parseArrowFunction` (parser.zig, dentro del campo
`ArrowFunction`):

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

`parseExpression` (= `parsePrecedece(.lowest)`) NO permite comas a nivel
de statement, así que respeta el delimitador externo del object literal.

### Patrón a evitar

No usar `parseCommaExpression` para el body del arrow: aunque a primera
vista parece simétrico con `parseExpression`, `parseCommaExpression`
consume comas top-level, que es exactamente el comportamiento no deseado
aquí.

### Lateral effects a auditar

- `parseArrowFunction` se llama desde `parsePrimary(.LParen → ...)`. Si
  el cambio rompe expresiones agrupadas legítimas como `(a, b)`, hay
  que revisar el flow de fallback entre arrow-fn parse y grouped-expr
  parse (líneas 343-356).
- También afecta a: [object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md)
  y
  [object-method-call-edge-function-and-arrow.md](./object-method-call-edge-function-and-arrow.md).
  Si los tres bugs comparten causa, un solo cambio los cubre.

## Verificación

```bash
# 1. Lou produce el output esperado
./zig-out/bin/lou run /tmp/r.lou
# Esperado: 99 1

# 2. Diff contra Node (referencia)
/home/lou/zig-out/bin/lou run /tmp/r.lou 2>&1 > /tmp/r_lou.txt
node /tmp/r.js 2>&1 > /tmp/r_node.txt
diff /tmp/r_lou.txt /tmp/r_node.txt  # debe ser vacío

# 3. Re-correr el compat suite
bash tests/compat/run.sh
```

## pendiente

- [ ] Confirmar la causa raíz con logs en `parseArrowFunction` y
      `parseStatement`.
- [ ] Decidir si el fix vive en `parseArrowFunction` (recomendado) o
      en `parseObjectLiteral` (alternativa: detectar el final del arrow
      body y restaurar el cursor si la comma se consumió de más).
- [ ] Una vez aplicado el fix, verificar que los tres edge cases
      relacionados también pasan.
- [ ] Considerar añadir un unit test en `parser.zig` que ejerza la
      forma explícitamente, además del compat test.
