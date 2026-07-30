# Object Literal — Multiple Methods & `this` Binding

## status
completado (2026-06-26)

## Problema (RESUELTO)
`tests/compat/isolate.lou` ahora pasa. Output idéntico a Node.js:

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

La causa raíz era que `parsePrimary` trataba `function` como un identificador
plano en contexto de expresión. Así, `function() { return 1; }` se parseaba
como `Identifier("function")` → `()` call → `{ return 1; }` sobrante causaba
`ExpectedCommaOrRBrace` en `parseObjectLiteral`.

**Fix**: `parsePrimary` ahora intenta `parseFunctionDeclaration()` primero
cuando ve `.Fn` (function/fn). Si falla (e.g. `function + 1`), restaura el
estado del lexer y trata como identificador. `parseFunctionDeclaration` ya
soportaba funciones anónimas (`function(){}`), así que no se necesitó código
nuevo.
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


## Estado del test (auto 2026-06-22)

- Compat test match: `isolate.lou` (EXACT)
- Test status: `FAIL`

- Diff excerpt:

```
1,25c1,8
< error: ExpectedCommaOrRBrace
< /home/lou/src/parser.zig:958:17: 0x13f3cdc in parseObjectLiteral (main.zig)
<                 return error.ExpectedCommaOrRBrace;
<                 ^
< /home/lou/src/parser.zig:399:24: 0x13ecede in parsePrimary (main.zig)
<                 base = try this.parseObjectLiteral();
<                        ^
```

- Disposition: stays in pendientes/ — exact test currently FAILS, see diff excerpt below.

