# Arrow functions: sintaxis `=>`

## status

IMPLEMENTED

## Problema

El parser de Lou rechaza la sintaxis de arrow functions de JavaScript: `(...) => expr`, `x => expr`, `() => { ... }`. Cualquier uso dispara `error: UnexpectedToken` o `error: ExpectedComma` en `parseCallArguments`.

## Contexto

Las arrow functions son la forma idiomática de escribir callbacks en JS moderno (`arr.map(x => x * 2)`). Lou ya soporta la semántica de arrow functions en `ArrowFunction` (lexical `this`, ver `completadas/arrow-function-this.md`), pero la **sintaxis** no se reconoce al parsear.

## Código que falla

```js
const arr = [1, 2, 3];
const doubled = arr.map(x => x * 2);     // error: ExpectedComma
const sum = arr.reduce((a, b) => a + b); // error: ExpectedComma

const f = () => 42;                      // error: UnexpectedToken
const g = x => x * 2;                    // error: UnexpectedToken
```

```
error: ExpectedComma
/home/vital/Desktop/lou/src/parser.zig:1393:17
```

## Implementacion sugerida

### 1. Lexer (`src/lexer.zig`)

Asegurar que `=>` se tokeniza como un solo token (probablemente ya lo hace, o se confunde con `=` `>`). Si está mal tokenizado, agregar token `Arrow` (`=>`).

### 2. Parser (`src/parser.zig`)

En el path de parseo de argumentos de llamada (`parseCallArguments`, ~línea 1384-1393), o donde se decida el límite de expresión, agregar el caso `Token.Arrow`:

```zig
// Después de parsear una expresión, si el siguiente token es `=>`,
// hemos cruzado al cuerpo de la arrow function.
// Pseudocódigo:
if (peek() == .Arrow) {
    consume(.Arrow);
    const body = if (peek() == .LBrace) parseBlock() else parseExpression();
    return .{ .ArrowFunction = .{ .parameters = captured_params, .body = body } };
}
```

La detección de arrow function debe ocurrir **antes** de tratar la `(` como cierre de argumentos de la función externa (precedencia/consume ambiguo). Patrón: mirar si hay `=>` inmediatamente después de una lista de parámetros o un identificador.

### 3. Resto

`ArrowFunction` ya existe en el AST y se evalúa (`completadas/arrow-function-this.md`). Probablemente no se necesite trabajo adicional más allá del parser.

## Archivos de referencia

- `src/lexer.zig` — tokenización
- `src/parser.zig:1384-1393` — `parseCallArguments`
- `src/ast.zig` — nodo `ArrowFunction` (ya existe)
- `completadas/arrow-function-this.md` — semántica de `this` (ya resuelta)
- ECMAScript 15.2 — `ArrowFunction`

### JS Examples Complejos

```js
// Una expresión
const sq = x => x * x;
console.log(sq(5));           // 25

// Sin parámetros
const pi = () => 3.14;
console.log(pi());            // 3.14

// Múltiples parámetros
const add = (a, b) => a + b;
console.log(add(2, 3));       // 5

// Cuerpo en bloque
const fact = n => {
    if (n < 2) return 1;
    return n * fact(n - 1);
};
console.log(fact(5));         // 120

// Como callback
console.log([1, 2, 3].map(x => x * 2));  // [2, 4, 6]
console.log([1, 2, 3].filter(x => x > 1)); // [2, 3]

// Rest parameters
const head = (...xs) => xs[0];
console.log(head(1, 2, 3));   // 1
```

### Vereficacion

```bash
./zig-out/bin/lou run tests/compat/arrow-syntax.js
node tests/compat/arrow-syntax.js
```

Diff esperado: ninguna línea difiere, exit code 0 en ambos.

### Comparar salida raw (sin interpretar ANSI)

```bash
./zig-out/bin/lou run tests/compat/arrow-syntax.js 2>&1 | od -c
node tests/compat/arrow-syntax.js 2>&1 | od -c
```

### Implementación

- [x] Confirmar tokenización de `=>` en el lexer
- [x] Detectar arrow function en el parser (antes de cerrar argumentos)
- [x] Cubrir `x => expr`, `(x) => expr`, `() => expr`, `(...xs) => expr`
- [x] Cubrir cuerpo bloque `{ ... }` y cuerpo expresión
- [x] Verificar que callbacks tipo `arr.map(x => x * 2)` funcionan end-to-end
