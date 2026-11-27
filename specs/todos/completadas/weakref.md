# WeakRef

## status

**completada** — implementada (compat: 85 PASS / 0 FAIL / 1 SKIP)

`tests/compat/weakref.lou` produce salida byte-idéntica a Node.

## Problema

`WeakRefConstructor` ya validaba el target y llamaba a `throwError`, pero los
errores se perdían: `new WeakRef(42)`, `new WeakRef("x")`, `new WeakRef()`,
etc. no lanzaban nada, y el `try/catch` del fixture no se ejecutaba.

## Causa

- El evaluator llama a los builtins directamente en `.FunctionCall`,
  `.NewExpression` y en el operador pipe, y devolvía el valor sin mirar
  `env.throw_hit`. El throw quedaba pendiente y se ignoraba.
- El VM compila `new` como `eval_node`; el `catch` de ese opcode devolvía
  `error.Thrown` sin consultar la pila de handlers del VM, así que el
  `try/catch` compilado por el VM tampoco lo capturaba.

## Implementación

### `src/evaluator.zig`

- Tras cada invocación de builtin (spread, stack buffer y heap) en
  `.FunctionCall`, `.NewExpression` y el pipe se comprueba `env.throw_hit` y
  se devuelve `error.Thrown`.

### `src/vm.zig`

- El `catch` de `eval_node` enruta el throw pendiente con
  `deliverBuiltinThrow()` (handler del VM o `error.Thrown` si no hay).

## Efecto colateral

También se propaga correctamente cualquier `throwError` de un builtin usado
como función normal o en pipe (antes se tragaba silenciosamente).

`deref()` sigue devolviendo siempre el target: Lou no tiene GC, limitación
documentada y aceptada por el fixture.
