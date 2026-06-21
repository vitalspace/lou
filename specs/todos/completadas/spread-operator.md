# Spread operator (`...`)

**Prioridad: baja** — ✅ COMPLETADO

## Estado (Auditoría 2026-05-28)

### ✅ Implementado

| Componente | Archivo | Estado |
|---|---|---|
| Lexer (`DotDotDot` token) | `src/lexer.zig` | ✅ |
| AST (`SpreadExpression` node) | `src/ast.zig` | ✅ |
| Parser: array spread `[...x]` | `src/parser.zig` | ✅ |
| Parser: object spread `{...x}` | `src/parser.zig` | ✅ |
| Parser: function call spread `f(...x)` | `src/parser.zig` | ✅ |
| Parser: method call spread `o.m(...x)` | `src/parser.zig` | ✅ |
| Evaluador: `evaluateArgs` helper | `src/evaluator.zig` | ✅ |
| Evaluador: ArrayLiteral spread | `src/evaluator.zig` | ✅ |
| Evaluador: ObjectLiteral spread | `src/evaluator.zig` | ✅ |
| Evaluador: FunctionCall spread | `src/evaluator.zig` | ✅ |
| Evaluador: MethodCall spread | `src/evaluator.zig` | ✅ |
| VM: `eval_node` opcode fallback | `src/vm.zig` | ✅ |
| Set spread (`[...Set([...])]`) | — | ✅ |
| Map spread (`[...Map([...])]`) | — | ✅ |
| String spread (`[..."hello"]`) | — | ✅ |
| Chained spread (`filter(...).map(...)`) | — | ✅ |

### Tests

- `js/test-spread.js` — Test completo para Node.js (usa `new`) — ✅
- `js/test-spread-lou.js` — Test para Lou (sin `new`) — ✅ 10 secciones, exit code 0

### Cobertura (10 secciones)

1. Array spread — ✅
2. Object spread — ✅
3. Function call spread — ✅
4. Set spread — ✅
5. Map spread — ✅
6. Method call spread — ✅
7. Arrow function spread — ✅
8. Chained spread — ✅
9. Edge cases (vacíos, anidados, flotantes) — ✅
10. Real-world scenarios (clone, merge, combine) — ✅

## Implementación

- Lexer: token `DotDotDot` ya existía
- AST: `SpreadExpression { value: *Node }`
- Parser: detecta `...expr` en arrays, objetos, y argumentos de función/método
- Evaluador: helper `evaluateArgs` para expandir spreads en llamadas; lógica inline para arrays y objetos
- VM: usa `eval_node` opcode para spread
- Dependencia: `Symbol.iterator` — ✅ implementado

## Referencia

- `src/parser.zig` — parsing de `...`
- `src/ast.zig` — nodo `SpreadExpression`
- `src/evaluator.zig` — evaluación de `SpreadExpression`
- `src/vm.zig` — compilación de `SpreadExpression`
- `specs/todos/symbol-well-known.md` — dependencia de `Symbol.iterator`
- `js/test-spread-lou.js` — suite de pruebas
- `js/test-spread.js` — suite de pruebas (Node.js)

## Verificación

```js
// Spread en arrays
var a = [1, 2];
var b = [3, 4];
console.log([...a, ...b]); // [1, 2, 3, 4]

// Spread con Set
var s = Set([10, 20, 30]);
console.log([...s]); // [10, 20, 30]

// Spread con Map
var m = Map([["a", 1], ["b", 2]]);
console.log([...m]); // [["a", 1], ["b", 2]]

// Spread en argumentos
function sum(a, b, c) { return a + b + c; }
console.log(sum(...[1, 2, 3])); // 6

// Spread en objetos
var obj1 = { a: 1 };
var obj2 = { b: 2 };
console.log({...obj1, ...obj2}); // { a: 1, b: 2 }
```

## Limitaciones conocidas

- Spread con generators (`[...gen()]`) no funciona — requiere que generators expongan `Symbol.iterator`
- Spread en `for...of` no aplica (no es uso directo de spread)