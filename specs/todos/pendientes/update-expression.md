# Update Expressions on MemberAccess/ArrayIndex

## status
pendiente

## Problema
`tests/compat/update-expression-lhs.lou` falla. Output actual:
```
6
5
5
```
(programa termina sin completar)

Output esperado (JS): 11+ líneas con varios casos de `++x`, `x++`, `--obj.x`, `arr[i++]`, etc.
## Contexto

Lou ya implementa `++` y `--` para `Identifier` LHS (los unit tests pasan). El VM bytecode compiler tiene un stub `.UpdateExpression` que delega al AST evaluator (línea ~803), pero el AST evaluator tiene implementación parcial (líneas ~2860-3000):
- Solo retorna `old_value` o `new_value` sin almacenar de vuelta al LHS.
- Falta el store-back para MemberAccess y ArrayIndex.

## Baseline (qué existe ya)
- AST ya tiene `UpdateExpression` (verificar `src/ast.zig`)
- `++`/`--` para Identifier YA funcionan
- Evaluator tiene implementación parcial (`src/evaluator.zig:2860-3000`)
- VM bytecode compiler tiene stub `.UpdateExpression` (`src/vm.zig:803`)
- FALTA: store-back para MemberAccess y ArrayIndex

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
let x = 5;
let y = ++x;
console.log(y, x);
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: "6 5" — esperado: "6 6"
```

## Patrones a seguir
- `src/evaluator.zig:3957` — `evaluateUpdate` (línea aproximada)
- `src/evaluator.zig:2860-3000` — implementación actual (parcial)
- `src/vm.zig:803` — VM bytecode compiler stub
- `src/environment.zig:378-387` — `setInScope` para Identifier
- `src/evaluator.zig` — buscar `MemberAccess` y `ArrayIndex` (cómo hacer set)
- `src/evaluator.zig:2213-2239` — MemberAccess (get, falta set)

## Gotchas
- Cambio localizado: agregar store-back después de calcular `new_value`
- 3 casos de LHS:
  1. `.Identifier` → `env.setInScope(name, new_value)` (puede ya funcionar)
  2. `.MemberAccess` → `obj.js_object.properties.put(prop, new_value)`
  3. `.ArrayIndex` → `arr.array.set(idx, new_value)` o similar
- Cross-check con `increment-decrement.md` — spec duplicado
- Prefix vs postfix: postfix retorna OLD value, prefix retorna NEW value
- Compat test: `tests/compat/update-expression-lhs.lou` debe pasar
- Unit tests existentes en evaluator.zig:3960-4010 — algunos pasan
- NO debe romper tests que ya pasan (Identifier case)

## Código que falla
