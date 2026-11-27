# Living Tracker — Compat Specs (Auto-Generated)

## status

Generado por `scripts/compat_tracker.py`; no editar a mano.

| Metrica | Valor |
|---|---|
| Snapshot | 2026-11-27 11:35:09 |
| Commit | `6dc7926` |
| Binario | `zig-out/bin/lou` |
| Fixtures | 86 |
| PASS | 78 |
| FAIL | 7 |
| SKIP | 1 |

## Section 1 — Headline Counts

| Estado | Count |
|---|---|
| Test files total | 86 |
| **PASS** | 78 |
| **FAIL** | 7 |
| SKIP (sin .js) | 1 |
| Specs pendientes | 35 |
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
- Primera divergencia (línea 1, 3 vs 16 líneas):
  - Lou : `undefined`
  - Node: `Hello Alice`

### 4. `iterator-protocol.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 1 vs 10 líneas):
  - Lou : `error: ExpectedColon`
  - Node: `array sum: 6`

### 5. `regex-literal.lou` - FAIL

- exit: Lou 1 / Node 0
- Primera divergencia (línea 1, 1 vs 5 líneas):
  - Lou : `error: UnexpectedToken`
  - Node: `--- regex literal syntax ---`

### 6. `regex-properties.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 1, 19 vs 19 líneas):
  - Lou : `undefined`
  - Node: `hello`

### 7. `weakref.lou` - FAIL

- exit: Lou 0 / Node 0
- Primera divergencia (línea 5, 12 vs 12 líneas):
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
| `date-object-regression.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `date-object` | PASS |
| `error-objects.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `error-objects` | PASS |
| `eval-func.md` | pendiente | `eval-func` | sin test |
| `finalization-registry.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `finalization-registry` | PASS |
| `for-var-no-init.md` | pendiente (coerción resuelta) — reverificado 2026-11-26 (compat: 57 P… | `for-var-no-init` | PASS |
| `function-call-apply-bind.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `call-apply-bind` | FAIL (call-apply-bind) |
| `lexer-regex-literals.md` | pendiente — reverificado 2026-11-26 (compat: 54 PASS / 30 FAIL / 1 SK… | `regex-literal` | FAIL (regex-literal) |
| `object-key-order.md` | pendiente — detectado 2026-11-26 mientras se arreglaba `for-in-order` | — | sin test |
| `object-method-call-edge-function-and-arrow.md` | pendiente | — | sin test |
| `object-method-call-edge-parens-single-arrow.md` | pendiente | — | sin test |
| `object-method-call-edge-zero-arg-arrow.md` | pendiente | — | sin test |
| `object-static-methods.md` | pendiente | — | sin test |
| `optional-chaining.md` | pendiente | `optional-chaining` | sin test |
| `promise-withresolvers.md` | pendiente | `promise-withresolvers` | sin test |
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
