# let en for-loop: bindings por iteración

## status

**completado** — 2026-11-26 (compat: 65 PASS / 20 FAIL / 1 SKIP)

`tests/compat/let-per-iteration.lou` y `tests/compat/closure-capture.lou` producen
output byte-idéntico a Node. La verificación es:

```bash
bash tests/compat/run.sh 2>&1 | tail -1
# PASS=65  FAIL=20  SKIP=1
```

## Problema original

Los closures creados en un `for (let i ...)` compartían un único binding:
`fns[0]()`, `fns[1]()` y `fns[2]()` devolvían todos `3` en vez de `0 1 2`.
ECMAScript 14.7.4.2 exige un Environment Record nuevo por iteración para las
declaraciones `let`/`const`.

## Implementación

### Valores closure con captura léxica

- `ast.ClosureValue` (`func_node` + `env` capturado) y la variante `.closure` de
  `Value`; `ast.containsClosure(node)` detecta si un subárbol crea funciones.
- `Environment.captureEnv()`: los envs de root/iteración/closure se reutilizan
  tal cual; un env heap `owned` se marca `captured` y se registra en
  `root().closure_envs`; un scope de pila se copia a `initClosureHeap`.
- `invokeFunctionNode` crea su frame con `Environment.initHeap` y sólo lo libera
  si `!func_env.captured`; las llamadas `.closure` pasan el env capturado como
  padre, de modo que el lookup es léxico y no dinámico.

### Bytecode VM (`src/vm.zig`)

- `Op.make_closure` sustituye la emisión de `.function` para
  `ArrowFunction`/`FunctionDeclaration`; el dispatch `.builtin`/`.method_call`
  resuelve `.closure` vía `callClosureValue`.
- Nuevos opcodes `enter_loop_scope` / `next_loop_scope` / `exit_loop_scope`
  (payload: `u16` count + count índices de constantes de nombre).
- `forStmt` emite esos opcodes cuando el init es `let`/`const` y
  `ast.containsClosure(body)`; en ese caso desactiva
  `tryOptimizeSimpleLoop` y usa `continue` forward-patching.
- `next_loop_scope` copia los nombres del loop al env de la iteración nueva
  antes de ejecutar el increment; `exit_loop_scope` restaura el env padre.

### Evaluador (`src/evaluator.zig`)

- `ForLoop` aplica el mismo criterio (`per_iter`) para los cuerpos que evalúa
  el árbol (funciones invocadas desde callbacks, generadores, etc.), con
  `Environment.initIterHeap` y copia de nombres antes del increment/continue.
- Los generadores conservan el env de iteración en `for_yield_iter_env` para
  que `yield` no reinicie el binding.

### Ciclo de vida

- Los envs de iteración y de closure se registran en el root
  (`iter_envs`/`closure_envs`) y se liberan en orden inverso de creación, para
  que un hijo nunca use un padre ya liberado.
- Los builtins que invocan callbacks (`Array.map/filter/find/...`, `sort`,
  `Map.forEach`, `Set.forEach`, `Object.groupBy`, `DisposableStack`) aceptan
  `.closure` y crean el frame con `Environment.initCallable`, que usa el env
  capturado como padre.

## Tests

- `tests/compat/let-per-iteration.{js,lou}` — `0 1 2` / `3 3 3` (var) /
  `10 10 10` (closure sobre acumulador) / `0 1 2` (arrow en array).
- `tests/compat/closure-capture.{js,lou}` — contador, arrays de closures,
  función anidada y `this` capturado.
- Casos manuales verificados: 10.000 closures en un loop, loops anidados
  (`0,0 0,1 1,0 1,1`), `break`/`continue` con closures, generadores con
  `for (let ...)` y closures dentro de funciones compiladas y evaluadas.

## Limitaciones conocidas

- Un `var` declarado dentro del cuerpo de un `for (let ...)` queda en el scope
  de iteración (Node lo hoistea al scope de función):
  `for (let i...) { var x = i; fns.push(() => x); }` da `0 1 2` en Lou y
  `2 2 2` en Node. No afecta a ningún fixture; queda como mejora futura
  (requeriría distinguir declaraciones de `var` y `let` en el compilador).
- `for-in`/`for-of` con `let` ya funcionan con el binding reasignado por
  iteración; no necesitan los opcodes nuevos (ver `for-in-loop.md`).
- El mensaje de error de TDZ por iteración sigue el comportamiento general de
  `let` (ver `temporal-dead-zone.md`).

## Referencias

- `src/vm.zig` (`forStmt`, `enterLoopScope`, `nextLoopScope`, `makeClosure`)
- `src/evaluator.zig` (`ForLoop`, `invokeFunctionNode`, `callFunctionValue`)
- `src/environment.zig` (`captureEnv`, `initIterHeap`, `initClosureHeap`,
  `initCallable`)
- `src/ast.zig` (`ClosureValue`, `containsClosure`)