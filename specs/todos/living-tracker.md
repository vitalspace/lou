# Living Tracker — Compat Specs (Auto-Generated)

## status

Generado por `scripts/compat_tracker.py`; no editar a mano.

| Metrica | Valor |
|---|---|
| Snapshot | 2026-11-26 15:53:54 |
| Commit | `da124c9` |
| Binario | `zig-out/bin/lou` |
| Fixtures | 86 |
| PASS | 68 |
| FAIL | 17 |
| SKIP | 1 |

## Section 1 — Headline Counts

| Estado | Count |
|---|---|
| Test files total | 86 |
| **PASS** | 68 |
| **FAIL** | 17 |
| SKIP (sin .js) | 1 |
| Specs pendientes | 40 |
| Specs hechos | 61 |

## Section 2 — Failing Tests (first divergence)

### 1. `bigint-prototype.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 26, 52 vs 52 líneas):
  - Lou : `+ empty: undefined`
  - Node: `+ empty: 42`

### 2. `boolean.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 20, 48 vs 48 líneas):
  - Lou : `boolean`
  - Node: `object`

### 3. `call-apply-bind.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 9 vs 16 líneas):
  - Lou : `undefined`
  - Node: `Hello Alice`

### 4. `date-object.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 17, 21 vs 21 líneas):
  - Lou : `0`
  - Node: `31536000000`

### 5. `default-parameters.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 15 vs 13 líneas):
  - Lou : `error: ExpectedComma`
  - Node: `0`

### 6. `error-objects.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 5, 14 vs 62 líneas):
  - Lou : `error: Thrown`
  - Node: `instanceof Error: true`

### 7. `finalization-registry.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 9, 18 vs 15 líneas):
  - Lou : `error: Thrown`
  - Node: `register primitive: true`

### 8. `for-var-no-init.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 4, 4 vs 4 líneas):
  - Lou : `const-no-init: [object]`
  - Node: `const-no-init: true`

### 9. `getter-setter.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 25 vs 6 líneas):
  - Lou : `error: ExpectedColon`
  - Node: `42`

### 10. `in-operator.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 10 vs 8 líneas):
  - Lou : `error: Thrown`
  - Node: `true`

### 11. `instanceof-operator.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 2, 11 vs 15 líneas):
  - Lou : `error: Thrown`
  - Node: `true`

### 12. `iterator-protocol.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 25 vs 10 líneas):
  - Lou : `error: ExpectedColon`
  - Node: `array sum: 6`

### 13. `json-parse.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 17, 35 vs 23 líneas):
  - Lou : `error: Thrown`
  - Node: `ok(\x): true / SyntaxError`

### 14. `prototype-chain.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 5, 9 vs 9 líneas):
  - Lou : `object`
  - Node: `function`

### 15. `regex-literal.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 36 vs 5 líneas):
  - Lou : `error: UnexpectedToken`
  - Node: `--- regex literal syntax ---`

### 16. `regex-properties.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 19 vs 19 líneas):
  - Lou : `undefined`
  - Node: `hello`

### 17. `weakref.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 5, 20 vs 12 líneas):
  - Lou : `no throw for number`
  - Node: `TypeError for number: true`

## Section 3 — Specs pendientes

| Spec | Estado declarado | Test | Resultado |
|---|---|---|---|
| `async-await.md` | pendiente | `async-await` | sin test |
| `async-generators.md` | pendiente | `async-generators` | sin test |
| `bigint-prototype-template.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `bigint-prototype` | FAIL (bigint-prototype) |
| `boolean-object.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `boolean` | FAIL (boolean) |
| `builtin-throws.md` | pendiente — detectado 2026-11-26 mientras se arreglaba `map-groupby` | — | sin test |
| `call-apply-bind.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `call-apply-bind` | FAIL (call-apply-bind) |
| `classes.md` | pendiente | `classes` | sin test |
| `date-object-regression.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `date-object` | FAIL (date-object) |
| `date-object.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `date-object` | FAIL (date-object) |
| `default-parameters-compat.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `default-parameters` | FAIL (default-parameters) |
| `default-parameters.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `default-parameters` | FAIL (default-parameters) |
| `error-objects.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `error-objects` | FAIL (error-objects) |
| `eval-func.md` | pendiente | `eval-func` | sin test |
| `finalization-registry.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `finalization-registry` | FAIL (finalization-registry) |
| `for-var-no-init.md` | pendiente (coerción resuelta) — reverificado 2026-11-26 (compat: 57 P… | `for-var-no-init` | FAIL (for-var-no-init) |
| `function-call-apply-bind.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `call-apply-bind` | FAIL (call-apply-bind) |
| `json-parse.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `json-parse` | FAIL (json-parse) |
| `lexer-regex-literals.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `regex-literal` | FAIL (regex-literal) |
| `object-key-order.md` | pendiente — detectado 2026-11-26 mientras se arreglaba `for-in-order` | — | sin test |
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
| `template-literal-interpolation.md` | NOT IMPLEMENTED | `template-literal-interpolation` | sin test |
| `temporal-dead-zone.md` | NOT IMPLEMENTED | `temporal-dead-zone` | sin test |
| `temporal.md` | pendiente | `temporal` | sin test |
| `typed-arrays.md` | pendiente | `typed-arrays` | sin test |
| `weakmap.md` | pendiente | `weakmap` | sin test |
| `weakset.md` | pendiente | `weakset` | sin test |

## Section 4 — Drift: specs en `hechos/` cuyo test sigue FAIL

Ninguno.

## Section 5 — How To Regenerate

```bash
zig build release
python3 scripts/compat_tracker.py
bash tests/compat/run.sh   # vista rápida PASS/FAIL
```
