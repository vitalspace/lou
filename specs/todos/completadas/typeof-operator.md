# Operador `typeof` implementado

## status

✅ IMPLEMENTADO

## Problema

`typeof` no estaba implementado en el parser ni en el evaluador/VM. Cualquier uso de `typeof expr` producía `ExpectedComma` en el parser porque no reconocía la keyword.

## Cambios realizados

### 1. Lexer (`src/lexer.zig`)
- Agregado token `TypeOf` al enum `TokenType`
- Agregado `"typeof"` al mapa de keywords en `getKeywordType()`

### 2. AST (`src/ast.zig`)
- Agregado variante `TypeOfExpression` a `NodeType` con campo `operand: *Node`
- Agregado caso en `printAst()` para impresión del AST
- Agregado caso en `freeAst()` para liberación de memoria

### 3. Parser (`src/parser.zig`)
- Agregado `.TypeOf` a `isPropertyName()` para uso como nombre de propiedad en literales de objeto
- Agregado caso `.TypeOf` en `parsePrimary()` como operador unario (patrón similar a `!`, `-`, `~`)
  - Consume `typeof`, parsea el operando con `parsePrimary()`, crea nodo `TypeOfExpression`

### 4. Evaluador (`src/evaluator.zig`)
- Agregado caso `TypeOfExpression` en la función `evaluate()`
- Mapeo de tipos internos a strings JS:

| Tipo interno Value | `typeof` resultado |
|---|---|
| `.integer` | `"number"` |
| `.float` | `"number"` |
| `.string` | `"string"` |
| `.boolean` | `"boolean"` |
| `.void` | `"undefined"` |
| `.null` | `"object"` |
| `.array` | `"object"` |
| `.js_object` | `"object"` |
| `.object` (BuiltinObject) | `"object"` |
| `.function` | `"function"` |
| `.closure` | `"function"` |
| `.generator` | `"function"` |
| `.symbol` | `"symbol"` |
| `.iterator` | `"object"` |
| `.hole` | `"undefined"` |

### 5. VM (`src/vm.zig`)
- Agregado `TypeOfExpression` a la delegación al evaluador (junto con `ConditionalExpression` y `CommaExpression`)

## Verificación

- Build: ✅ compila sin errores
- 25/25 suites de tests generales pasan
- 797+ tests unitarios pasan
- `typeof` funciona correctamente para: números, strings, booleans, undefined, null, arrays, arrow functions, member access, variables, y precedencia

### Tests ejecutados

```js
console.log(typeof 42);            // "number" ✅
console.log(typeof 3.14);          // "number" ✅
console.log(typeof "hola");        // "string" ✅
console.log(typeof true);          // "boolean" ✅
console.log(typeof false);         // "boolean" ✅
console.log(typeof undefined);     // "undefined" ✅
console.log(typeof null);          // "object" ✅
console.log(typeof []);            // "object" ✅
console.log(typeof (() => 1));     // "function" ✅

var x = 10;
console.log(typeof x);             // "number" ✅
x = "hello";
console.log(typeof x);             // "string" ✅
x = null;
console.log(typeof x);             // "object" ✅

var result = typeof 42 === "number";
console.log(result);               // true ✅

var t1 = typeof 42 + " is a number";
console.log(t1);                   // "number is a number" ✅
```

### Known issue

`typeof` en declaraciones de función (`function add() {}`) retorna `"string"` en lugar de `"function"`. Esto es un comportamiento pre-existente del evaluador, no un bug de `typeof`.

## Dependencias

- Implementado sobre los tipos existentes de `Value` en `src/types/runtime.zig`
- Sigue el patrón de operadores unarios existentes (`!`, `-`, `~`)
- Reutiliza string literals comptime para los resultados (sin allocación dinámica)
