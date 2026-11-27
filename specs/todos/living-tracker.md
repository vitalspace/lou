# Living Tracker — Compat Specs (Auto-Generated)

## status

Generado por `scripts/compat_tracker.py`; no editar a mano.

| Metrica | Valor |
|---|---|
| Snapshot | 2026-11-27 17:00:21 |
| Commit | `32556f6` |
| Binario | `zig-out/bin/lou` |
| Fixtures | 97 |
| PASS | 96 |
| FAIL | 1 |
| SKIP | 0 |

## Section 1 — Headline Counts

| Estado | Count |
|---|---|
| Test files total | 97 |
| **PASS** | 96 |
| **FAIL** | 1 |
| SKIP (sin .js) | 0 |
| Specs pendientes | 14 |
| Specs hechos | 61 |

## Section 2 — Failing Tests (first divergence)

### 1. `iterator-protocol.lou` - FAIL

- exit: Lou -6 / Node 0
- Primera divergencia (línea 11, 41 vs 10 líneas):
  - Lou : `error(DebugAllocator): memory address 0x7fd1c21c0480 leaked: `
  - Node: `<EOF>`

## Section 3 — Specs pendientes

| Spec | Estado declarado | Test | Resultado |
|---|---|---|---|
| `async-await.md` | pendiente | `async-await` | sin test |
| `async-generators.md` | pendiente | `async-generators` | sin test |
| `classes.md` | pendiente | `classes` | sin test |
| `eval-func.md` | pendiente | `eval-func` | sin test |
| `object-method-call-edge-function-and-arrow.md` | pendiente | — | sin test |
| `object-method-call-edge-parens-single-arrow.md` | pendiente | — | sin test |
| `object-method-call-edge-zero-arg-arrow.md` | pendiente | — | sin test |
| `promise-withresolvers.md` | pendiente | `promise-withresolvers` | sin test |
| `proxy.md` | pendiente | `proxy` | sin test |
| `string-icu.md` | ❌ PENDIENTE | — | sin test |
| `structured-clone.md` | pendiente | `structured-clone` | sin test |
| `temporal-dead-zone.md` | NOT IMPLEMENTED | `temporal-dead-zone` | sin test |
| `temporal.md` | pendiente | `temporal` | sin test |
| `typed-arrays.md` | pendiente | `typed-arrays` | sin test |

## Section 4 — Drift: specs en `hechos/` cuyo test sigue FAIL

Ninguno.

## Section 5 — How To Regenerate

```bash
zig build release
python3 scripts/compat_tracker.py
bash tests/compat/run.sh   # vista rápida PASS/FAIL
```
