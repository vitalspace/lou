# Object literal: function expression with non-trivial body as a property value

## status

pendiente

## Problema

En un object literal, una propiedad cuyo valor es una `fn` o `function`
expression con cuerpo no-trivial dispara `ExpectedPropertyName` en
`parseObjectLiteral` (parser.zig:792), incluso en el caso minimal sin
segunda propiedad.

```js
// Funciona — `fn foo() expr` (Lou form), bodies no-bloque simples
// no cubiertos en este spec.

function function_a_b() { return 1 + 2; }
const a = { f: function_a_b };            // solo ident, OK
console.log(typeof a.f);                  // function

// Falla — `fn(a, b) { return a + b; }` como valor (con parámetros
// y cuerpo de bloque con `return`):
const o = { fn: function(a, b) { return a + b; } };
console.log(o.fn(1, 2));
```

```
$ ./zig-out/bin/lou run o.lou
error: ExpectedPropertyName
/home/lou/src/parser.zig:792
```

Casos confirmados por bisect (2026-06-29):
- `{ fn: function(a, b) { return a + b; }, arrow: (a, b) => a + b }` → fail
- `{ fn: function() { return 1; }, arrow: () => 2 }` → fail
- `{ fn: function(x) { return x+1; }, arrow: y => y+2 }` → fail
- `{ fn: function(a, b) { return a + b; } }` (single prop, sin arrow) → **también** fail

## Contexto

Spec hermano: [object-method-call.md](./object-method-call.md) (status:
COMPLETADO 2026-06-29). El fix principal de ese spec cubre el dispatch
evaluator-side de `obj.f()` sobre propiedades de tipo `.function` /
`.closure`. Este edge case es un bug **parser-side** que vive en
`parseFunctionDeclaration` (parser.zig) y nunca fue cubierto.

A diferencia de los edge cases
[object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md) y
[object-method-call-edge-parens-single-arrow.md](./object-method-call-edge-parens-single-arrow.md),
este caso produce `ExpectedPropertyName` (línea 792), no
`ExpectedCommaOrRBrace` (línea 806). Eso indica una causa raíz distinta.

Hipótesis: el lexer/interacción entre la rama `.Fn` de `parsePrimary`
y `parseFunctionDeclaration` está consumiendo un número inesperado de
tokens cuando el cuerpo de la función tiene la forma `{ stmt; stmt; }`
con statements múltiples (e.g. `return expr;`) y posiblemente laissant
`current_token` apuntando a algo no-key al regresar a
`parseObjectLiteral`.

## Baseline (qué existe ya)

- `parsePrimary` tiene rama `.Fn =>
        base = try this.parseFunctionDeclaration()` (parser.zig).
- `parseFunctionDeclaration` (parser.zig) acepta 3 caminos para nombre:
  Identifier actual, peek Identifier, o anónimo.
- `parseBlockStatement` consume statements con terminador `;` opcional.
- `parseObjectLiteral` espera `.String/.Identifier/.Integer/.Float`
  como key después del value expr anterior.

## Quick verify (estado actual)

```bash
printf '%s' 'const o = { fn: function(a, b) { return a + b; } };
console.log(o.fn(1,2));' > /tmp/r.lou
/home/lou/zig-out/bin/lou run /tmp/r.lou 2>&1 | head -3
# Actual: error: ExpectedPropertyName at parser.zig:792
```

## Patrones a seguir

- Bisectionar qué parte del body de la función dispara el off-by-N
  tokens: con `{ return 1; }` (single return vs. `{ return a + b; }`
  (return con binary op)).
- Comparar contra function expression con cuerpo NO-bloque (forma Lou
  `fn foo() expr`): `const b = { f: function() 42 }; console.log(b.f());`
  — si funciona, el bug es específico al flujo
  `parseFunctionDeclaration → parseBlockStatement`.
- ECMAScript `MethodDefinition` y `FunctionExpression`: ambos esperan
  un solo nodo AST, no un bloque de statements mal-foldeado.
- ECMAScript FunctionExpression production no permite el cuerpo en
  forma de single-expression (eso es la *expression body* arrow
  function production). En JavaScript estricto, `function() 42` no es
  legal; la forma equivalente es `function() { return 42 }`. **La
  forma "Lou " `fn foo() expr` no debería aplicar a function
  expressions sin nombre** — pero el parser actual la acepta vía el
  `else parseStatement` de parseFunctionDeclaration.

## Gotchas

- **No es un bug introducido por object-method-call**. Existe de antes
  y queda enmascarado porque los compat tests previos no incluyeron
  function expressions como object literals con cuerpos de bloque y
  parámetros nombrados.
- **Aun un único prop falla**. Sorprendente: sugeriría que el bug no es
  sobre delimitación de props sino sobre el manejo interno de tokens al
  parsear el body de la función. Estudiar el comportamiento post-block
  en `parseFunctionDeclaration`.
- **Cross-check con arrow functions**: si el fix no es exclusivamente
  aquí, podría haber un fix unificado que toque `parseArrowFunction` Y
  `parseFunctionDeclaration`. Pero la evidencia indica causas
  distintas (`ExpectedPropertyName` ≠ `ExpectedCommaOrRBrace`).
- `parseFunctionDeclaration body's parseStatement` Lightning path:
  cuando el cuerpo NO es LBrace, llama `parseStatement` (forma Lou
  `fn foo() expr`). Esto podría estar dejando tokens sin consumir en
  algunos sub-casos.
- `parseObjectLiteral`'s key switch:
  ```zig
  const key = switch (this.current_token.type) {
      .String => this.current_token.literal,
      .Identifier => this.current_token.literal,
      .Integer => this.current_token.literal,
      .Float => this.current_token.literal,
      else => return error.ExpectedPropertyName,
  };
  ```
  En el momento del fallo, `current_token` es algo distinto a esas 4
  categorías. Hipótesis: un token residual (e.g. `.RBrace` después
  prematuro de cierre de function body, o `.RParen` de un cierre que no
  se consumió, etc.).

## Código que falla

```js
// Caso mínimo confirmado:
const o = { fn: function(a, b) { return a + b; } };
console.log(o.fn(1, 2));
// Actual: error: ExpectedPropertyName at parser.zig:792

// Variantes confirmadas:
const o2 = { fn: function(a, b) { return a + b; }, arrow: (a, b) => a + b };
const o3 = { fn: function() { return 1; }, arrow: () => 2 };
const o4 = { fn: function(x) { return x+1; }, arrow: y => y+2 };
```

Variantes para bisectionar:

- Cuerpo de bloque con `return` simple: `{ return 1; }`
- Sin `return`: `{ 1 + 2; }` (statement expr)
- Cuerpo non-bloque Lou (single-expression): `function() 42`
- Sin parámetros: `function() { return 1; }`

## Implementación sugerida

### Diagnosis (paso previo al fix)

1. En `parseFunctionDeclaration` (parser.zig), inmediatamente después
   del `if (.LBrace) parseBlockStatement else parseStatement`, añadir
   log de `current_token` para ver qué queda al regresar.

2. Comparar contra la forma ident-only (function decl con nombre) que
   ya sabemos funciona:
   `function foo(a, b) { return a + b; }` (decl standalone), confirmar
   que NO falla. Eso descartaría bugs en `parseBlockStatement` puro.

3. Comparar contra function expression sin nombre con cuerpo non-block:
   `const f = function() 42;` (forma Lou) — ver si dispara el mismo
   fallo.

4. Mirar específicamente `parseFunctionDeclaration` names handling:
   ```zig
   } else if (this.peek_token.type == .Identifier) {
       this.nextToken(); // consume 'fn'
       name = this.current_token.literal;
       this.nextToken(); // consume identifier
   } else {
       ...
   }
   ```
   Esta rama es compleja y puede leer tokens extra cuando el source
   no es una declaración con nombre sino una expression.

### Fix propuesto

Una vez la diagnosis identifique la causa, el fix probablemente vive
en uno de estos lugares (a confirmar):
1. `parseFunctionDeclaration`'s names handling: simplificar la lógica
   para detectar correctamente function expressions vs declaraciones.
2. `parseObjectLiteral`'s value position: terminar de consumir la
   function expression de forma robusta antes de pedir la siguiente
   key.
3. Si está relacionado con `parseStatement` siendo llamado por
   `parseFunctionDeclaration` para bodies non-block: revisar el path
   igual que en
   [object-method-call-edge-zero-arg-arrow.md](./object-method-call-edge-zero-arg-arrow.md),
   pero esta evidencia sugiere causa distinta.

### Lateral effects a auditar

- `parseFunctionDeclaration` se usa tanto para function declarations
  (`function foo() {...}`) como para function expressions (`const f =
  function() {...}`). Cuidado de no romper la primera mientras se
  arregla la segunda.
- Si el fix cambia el parser, verificar que no afecta a ningún compat
  test existente (especialmente closures, generators, arrow-as-methods).

## Verificación

```bash
# 1. Lou produce el output esperado
printf '%s' 'const o = { fn: function(a, b) { return a + b; } };
console.log(o.fn(1,2));' > /tmp/r.lou
./zig-out/bin/lou run /tmp/r.lou
# Esperado: 3

# 2. Diff contra Node
diff <(/home/lou/zig-out/bin/lou run /tmp/r.lou 2>&1) \
     <(node /tmp/r.js 2>&1)
# Debe ser vacío

# 3. Compat suite
bash tests/compat/run.sh
```

## pendiente

- [ ] Diagnosticar exactamente en qué parte de
      `parseFunctionDeclaration` queda `current_token` apuntando a algo
      no-key.
- [ ] Confirmar si la causa raíz es común con los otros dos edge
      cases (zero-arg arrow, parenthesized single-arg arrow) o si es
      independiente.
- [ ] Aplicar fix y verificar que los tres bugs se cierren.
- [ ] Considerar unit test en `src/parser.zig` específicamente sobre
      function-expression-como-property-value.
