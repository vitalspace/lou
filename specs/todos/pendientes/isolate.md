# Object Literal — Multiple Methods & `this` Binding

## status
pendiente

## Problema
`tests/compat/isolate.lou` falla. Solo imprime `typeof` de las funciones,
no las ejecuta. Output actual (Lou):

```
function
function
```

Output esperado (JS):
```
function
function
1
2
---
99
---
[ 2, 4, 6 ]
```

El programa termina silenciosamente al primer `obj1.a()` (no imprime
`undefined`, no lanza error visible). Probable stack underflow o
excepción tragada por el evaluator.
## Contexto

El test cubre 3 cosas que el título "isolate" resume como casos de
aislamiento/regresión:

1. **Múltiples métodos en un object literal**: ...
2. **`this` binding en métodos de objeto**: ...
3. **`function(x) { return x * 2 }` como callback de `Array.prototype.map`**: ...

## Baseline (qué existe ya)
- `Array.prototype.map` YA implementado (`src/builtins/array/`)
- `completadas/this-binding.md` YA está implementado — `this` binding funciona en teoría
- Object literal con métodos: parser crea Property entries
- Eval/VM: NO detecta que la propiedad es `.function` cuando se invoca
- Ver `object-method-call.md` (spec hermano) para más detalle

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
const o = { f: function() { return 42; } };
console.log(o.f());
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: undefined o terminación silenciosa; esperado: 42
```

## Patrones a seguir
- `src/evaluator.zig:388` — `Identifier` lookup con `.function` vs `.closure`
- `src/evaluator.zig` — `MemberAccess` (path que debería invocar funciones)
- `src/evaluator.zig` — `MethodCall` (path específico para call)
- `src/vm.zig` — buscar opcodes para MemberAccess/MethodCall
- `src/builtins/array/` — patrón de `Array.prototype.map` que SÍ funciona
- `completadas/this-binding.md` — cómo se bindea `this` ya implementado

## Gotchas
- Bug ESPECÍFICO: cuando el LHS es `.function`, no se invoca correctamente
- Cross-check con `object-method-call.md` — MISMO bug, spec duplicado
- Posible causa 1: VM no genera opcode correcto para `obj.prop()` cuando prop es `.function`
- Posible causa 2: evaluator dispatch no maneja el caso
- `Array.prototype.map(fn)` SÍ funciona — el path builtin funciona, el path "user function" no
- Verificar asimetría: arrow functions retornan `.closure`, regular retorna `.function`
- `this` binding: cuando se llama `obj.f()`, debe pasar `obj` como `this`
- Compat test: `tests/compat/isolate.lou` debe pasar
- NO debe romper: `objects.lou`, `control.lou`, `arrow-edge-cases.lou`

## Código que falla
