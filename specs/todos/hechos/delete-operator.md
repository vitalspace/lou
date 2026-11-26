# Operador delete

## status

**implementado (semántica)** — `delete obj.prop`, `delete arr[i]` y `delete obj[k]` ya se comportan
como Node; se añadieron `DeleteExpression` (AST), parser, evaluador y VM.

El fixture `tests/compat/delete-operator.lou` sigue **FAIL**, pero por otro motivo: el formato de
huecos del array en `console.log`.

```text
Lou : [1,<empty>,3,4]
Node: [1,<1 empty item>,3,4]
```

Eso se trackea aparte en `pendientes/console-array-holes.md`.

