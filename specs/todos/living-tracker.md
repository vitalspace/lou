# Living Tracker — Compat Specs (Auto-Generated)

## status

Generado por `scripts/compat_tracker.py`; no editar a mano.

| Metrica | Valor |
|---|---|
| Snapshot | 2026-11-27 20:53:28 |
| Commit | `7028a9c` |
| Binario | `zig-out/bin/lou` |
| Fixtures | 105 |
| PASS | 105 |
| FAIL | 0 |
| SKIP | 0 |

## Section 1 — Headline Counts

| Estado | Count |
|---|---|
| Test files total | 105 |
| **PASS** | 105 |
| **FAIL** | 0 |
| SKIP (sin .js) | 0 |
| Specs pendientes | 3 |
| Specs hechos | 61 |

## Section 2 — Failing Tests (first divergence)

## Section 3 — Specs pendientes

| Spec | Estado declarado | Test | Resultado |
|---|---|---|---|
| `string-icu.md` | ❌ PENDIENTE | — | sin test |
| `structured-clone.md` | pendiente | `structured-clone` | sin test |
| `temporal.md` | pendiente | `temporal` | sin test |

## Section 4 — Drift: specs en `hechos/` cuyo test sigue FAIL

Ninguno.

## Section 5 — How To Regenerate

```bash
zig build release
python3 scripts/compat_tracker.py
bash tests/compat/run.sh   # vista rápida PASS/FAIL
```
