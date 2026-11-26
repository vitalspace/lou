# Living Tracker — Compat Specs (Auto-Generated)

## status

Generado por `scripts/compat_tracker.py`; no editar a mano.

| Metrica | Valor |
|---|---|
| Snapshot | 2026-11-26 12:53:34 |
| Commit | `6da6572` |
| Binario | `zig-out/bin/lou` |
| Fixtures | 85 |
| PASS | 54 |
| FAIL | 30 |
| SKIP | 1 |

## Section 1 — Headline Counts

| Estado | Count |
|---|---|
| Test files total | 85 |
| **PASS** | 54 |
| **FAIL** | 30 |
| SKIP (sin .js) | 1 |
| Specs pendientes | 49 |
| Specs hechos | 62 |

## Section 2 — Failing Tests (first divergence)

### 1. `bigint-loose-eq.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 13, 75 vs 75 líneas):
  - Lou : `false`
  - Node: `true`

### 2. `bigint-prototype.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 19, 48 vs 52 líneas):
  - Lou : `--- Distinción toString vs console.log ---`
  - Node: `caught: toString() radix argument must be between 2 and 36`

### 3. `boolean.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 20, 48 vs 48 líneas):
  - Lou : `boolean`
  - Node: `object`

### 4. `call-apply-bind.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 9 vs 16 líneas):
  - Lou : `undefined`
  - Node: `Hello Alice`

### 5. `closure-capture.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 2, 23 vs 7 líneas):
  - Lou : `error: UndefinedVariable`
  - Node: `1`

### 6. `date-object.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 17, 21 vs 21 líneas):
  - Lou : `0`
  - Node: `31536000000`

### 7. `default-parameters.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 15 vs 13 líneas):
  - Lou : `error: ExpectedComma`
  - Node: `0`

### 8. `delete-operator.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 2, 15 vs 15 líneas):
  - Lou : `[1,<empty>,3,4]`
  - Node: `[1,<1 empty item>,3,4]`

### 9. `destructuring-nested-rest.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 12 vs 12 líneas):
  - Lou : `1`
  - Node: `NaN`

### 10. `destructuring.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 11, 13 vs 13 líneas):
  - Lou : `0`
  - Node: `NaN`

### 11. `equality-coercion.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 29 vs 29 líneas):
  - Lou : `0=='' false`
  - Node: `0=='' true`

### 12. `error-objects.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 5, 14 vs 62 líneas):
  - Lou : `error: Thrown`
  - Node: `instanceof Error: true`

### 13. `finalization-registry.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 9, 21 vs 15 líneas):
  - Lou : `register primitive: no error`
  - Node: `register primitive: true`

### 14. `for-in-order.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 5 vs 5 líneas):
  - Lou : `b,0,a`
  - Node: `0,b,a`

### 15. `for-var-no-init.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 11 vs 4 líneas):
  - Lou : `var-no-init: undefined`
  - Node: `let-no-init: undefined`

### 16. `getter-setter.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 25 vs 6 líneas):
  - Lou : `error: ExpectedColon`
  - Node: `42`

### 17. `globalThis.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 2, 10 vs 6 líneas):
  - Lou : `self_ref: false`
  - Node: `self_ref: true`

### 18. `in-operator.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 10 vs 8 líneas):
  - Lou : `error: Thrown`
  - Node: `true`

### 19. `instanceof-operator.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 2, 11 vs 15 líneas):
  - Lou : `error: Thrown`
  - Node: `true`

### 20. `iterator-protocol.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 25 vs 10 líneas):
  - Lou : `error: ExpectedColon`
  - Node: `array sum: 6`

### 21. `json-parse.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 17, 23 vs 23 líneas):
  - Lou : `FAIL(\x): no throw`
  - Node: `ok(\x): true / SyntaxError`

### 22. `let-per-iteration.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 4 vs 4 líneas):
  - Lou : `3 3 3`
  - Node: `0 1 2`

### 23. `map-groupby.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 19, 19 vs 20 líneas):
  - Lou : `---Throw did not propagate---`
  - Node: `---Throw propagated---`

### 24. `nan-comparison.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 17 vs 17 líneas):
  - Lou : `true`
  - Node: `false`

### 25. `prototype-chain.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 4, 9 vs 9 líneas):
  - Lou : `false`
  - Node: `true`

### 26. `regex-literal.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 36 vs 5 líneas):
  - Lou : `error: UnexpectedToken`
  - Node: `--- regex literal syntax ---`

### 27. `regex-properties.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 19 vs 19 líneas):
  - Lou : `undefined`
  - Node: `hello`

### 28. `switch-case.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 17 vs 9 líneas):
  - Lou : `error: UnexpectedToken`
  - Node: `two`

### 29. `typeof-undeclared.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 7 vs 8 líneas):
  - Lou : `error: UndefinedVariable`
  - Node: `undefined`

### 30. `weakref.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 5, 20 vs 12 líneas):
  - Lou : `no throw for number`
  - Node: `TypeError for number: true`

## Section 3 — Specs pendientes

| Spec | Estado declarado | Test | Resultado |
|---|---|---|---|
| `async-await.md` | pendiente | `async-await` | sin test |
| `async-generators.md` | pendiente | `async-generators` | sin test |
| `bigint-loose-equality.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `bigint-loose-eq` | FAIL (bigint-loose-eq) |
| `bigint-prototype-template.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `bigint-prototype` | FAIL (bigint-prototype) |
| `boolean-object.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `boolean` | FAIL (boolean) |
| `call-apply-bind.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `call-apply-bind` | FAIL (call-apply-bind) |
| `classes.md` | pendiente | `classes` | sin test |
| `console-array-holes.md` | pendiente — detectado 2026-11-26 por el barrido `./bench.sh compat`. | `array-holes`, `delete-operator` | FAIL (delete-operator) |
| `date-object-regression.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `date-object` | FAIL (date-object) |
| `date-object.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `date-object` | FAIL (date-object) |
| `default-parameters-compat.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `default-parameters` | FAIL (default-parameters) |
| `default-parameters.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `default-parameters` | FAIL (default-parameters) |
| `destructuring.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `destructuring`, `destructuring-array`, `destructuring-assign` | FAIL (destructuring, destructuring-nested-rest) |
| `equality-coercion.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `equality-coercion` | FAIL (equality-coercion) |
| `error-objects.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `error-objects` | FAIL (error-objects) |
| `eval-func.md` | pendiente | `eval-func` | sin test |
| `finalization-registry.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `finalization-registry` | FAIL (finalization-registry) |
| `for-in-order.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `for-in-order` | FAIL (for-in-order) |
| `for-var-no-init.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `for-var-no-init` | FAIL (for-var-no-init) |
| `function-call-apply-bind.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `call-apply-bind` | FAIL (call-apply-bind) |
| `globalThis.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `globalThis` | FAIL (globalThis) |
| `json-parse.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `json-parse` | FAIL (json-parse) |
| `let-per-iteration.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `let-per-iteration` | FAIL (let-per-iteration) |
| `lexer-regex-literals.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `regex-literal` | FAIL (regex-literal) |
| `map-groupby.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `map-groupby` | FAIL (map-groupby) |
| `nan-comparison.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `nan-comparison` | FAIL (nan-comparison) |
| `object-method-call-edge-function-and-arrow.md` | pendiente | — | sin test |
| `object-method-call-edge-parens-single-arrow.md` | pendiente | — | sin test |
| `object-method-call-edge-zero-arg-arrow.md` | pendiente | — | sin test |
| `object-static-methods.md` | pendiente | — | sin test |
| `optional-chaining.md` | pendiente | `optional-chaining` | sin test |
| `promise-withresolvers.md` | pendiente | `promise-withresolvers` | sin test |
| `prototype-chain.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `prototype-chain` | FAIL (prototype-chain) |
| `proxy.md` | pendiente | `proxy` | sin test |
| `reflect.md` | pendiente | `reflect` | sin test |
| `regex-properties.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `regex-properties` | FAIL (regex-properties) |
| `regex-v-flag.md` | pendiente | — | sin test |
| `string-constructor-bigint.md` | pendiente | `string-constructor` | sin test |
| `string-icu.md` | ❌ PENDIENTE | — | sin test |
| `string-unicode-case.md` | ❌ PENDIENTE | — | sin test |
| `structured-clone.md` | pendiente | `structured-clone` | sin test |
| `switch-case.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `switch-case` | FAIL (switch-case) |
| `template-literal-interpolation.md` | NOT IMPLEMENTED | `template-literal-interpolation` | sin test |
| `temporal-dead-zone.md` | NOT IMPLEMENTED | `temporal-dead-zone` | sin test |
| `temporal.md` | pendiente | `temporal` | sin test |
| `typed-arrays.md` | pendiente | `typed-arrays` | sin test |
| `typeof-undeclared.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `typeof-undeclared` | FAIL (typeof-undeclared) |
| `weakmap.md` | pendiente | `weakmap` | sin test |
| `weakset.md` | pendiente | `weakset` | sin test |

## Section 4 — Drift: specs en `hechos/` cuyo test sigue FAIL

| Spec | Estado declarado | Test | Resultado |
|---|---|---|---|
| `delete-operator.md` | implementado (semántica) — `delete obj.prop`, `delete arr[i]` y `dele… | `delete-operator` | FAIL (delete-operator) |

## Section 5 — How To Regenerate

```bash
zig build release
python3 scripts/compat_tracker.py
bash tests/compat/run.sh   # vista rápida PASS/FAIL
```
