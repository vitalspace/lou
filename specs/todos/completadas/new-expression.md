# Keyword `new` para constructores

**Prioridad: media** — ✅ COMPLETADO

## Estado

| Componente | Archivo | Estado |
|---|---|---|
| Lexer (token `New`) | `src/lexer.zig` | ✅ |
| AST (`NewExpression`) | `src/ast.zig` | ✅ |
| Parser (`new Identifier(args)`) | `src/parser.zig` | ✅ |
| Evaluador (`NewExpression`) | `src/evaluator.zig` | ✅ |
| VM | `src/vm.zig` | ✅ |

### Soporta

- `new Set([...])` ✅
- `new Map([...])` ✅
- `new Array(...)` ✅
- `new Set()` / `new Map()` / `new Array()` sin argumentos ✅
- `new` con funciones usuario: crea objeto `this`, bindea argumentos, retorna el objeto si la función retorna primitivo ✅

## Nota de diseño

Dado que los constructores en lou ya retornan objetos directamente (no crean un `this` vacío y lo pasan), `new` puede ser un alias de la llamada a función. Es decir, `new Set([1,2,3])` es equivalente a `Set([1,2,3])` en lou. Esto simplifica la implementación significativamente.

## Diferencias conocidas con Node.js

- `new Array(3)`: Node crea un **sparse array** (3 slots vacíos, `[ <3 empty items> ]`). Lou crea un array con 3 elementos `undefined` (`[ undefined, undefined, undefined ]`). Funcionalmente idéntico para acceso por índice; difiere en `hasOwnProperty` y `.map()` (Node salta slots vacíos). Aceptado como simplificación.

## Referencia

- `src/lexer.zig` — token `New`
- `src/ast.zig` — nodo `NewExpression`
- `src/parser.zig` — parsing de `new expr`
- `src/evaluator.zig` — evaluación de `NewExpression`
- `src/vm.zig` — compilación de `NewExpression`
- `src/builtins/builtins.zig` — constructores registrados

## Pendiente (futuro)

- Soporte para `new` con clases (cuando se implementen)

## Limitaciones conocidas

- `this` NO se bindea en llamadas a función regulares (`Func()`). Solo en `new Func()`. Ver `specs/todos/this-binding.md`.

## Verificación

- `new Set([1,2,3]).size` → `3`
- `new Map([["a",1]]).get("a")` → `1`
- `new Array(3).length` → `3`
- `new Array(1,2,3)` → `[1,2,3]`
- `new` con función usuario (retorna primitivo): retorna el nuevo objeto
- `new` con función usuario (retorna objeto): retorna ese objeto
- `function Bar() { this.x = 1; } new Bar().x` → `1`