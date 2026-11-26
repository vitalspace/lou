# Operador delete

## status

**COMPLETADO** — verificado 2026-11-26 (compat: 59 PASS / 26 FAIL / 1 SKIP)

`delete obj.prop`, `delete arr[i]` y `delete obj[k]` se comportan como Node (`DeleteExpression`
en AST, parser, evaluador y VM). `tests/compat/delete-operator.lou` pasa byte-identical: el
formato de huecos (`[1, <1 empty item>, 3, 4]`) se completó en `completadas/console-array-holes.md`.

