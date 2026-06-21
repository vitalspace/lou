# Default Parameters in Compat Test File

## status
pendiente (parcial — unit tests pasan)

## Problema
`tests/compat/default-parameters.lou` falla con `error: UndefinedVariable`, aunque los unit tests de `default-parameters` pasan:

Output actual (Lou): `error: UndefinedVariable` en `vm.zig:1100`.
Output esperado (JS): output completo del test.
## Contexto

El spec `specs/todos/pendientes/default-parameters.md` ya documenta la implementación de default parameters (status: implementado). Los unit tests en `src/evaluator.zig` (líneas ~5400-5500) y `src/parser.zig` (líneas ~2250-2350) pasan.

Pero el archivo compat `tests/compat/default-parameters.lou` falla. La sintaxis del archivo usa:
- `const multiply = (a = 1, b = 1) => a * b;` (arrow con defaults)
- `function build(first, second = first * 2, third = second * 2) { ... }` (defaults que referencian params anteriores)
- `let count = 0;` dentro de bloque (que activa block scoping)

El error `UndefinedVariable` sugiere que el VM bytecode compiler no maneja alguno de estos patrones (probablemente block-scoping con `let` en arrow function o reference-to-previous-param).

## Baseline (qué existe ya)
- Default parameters YA implementado (spec hermano `default-parameters.md`)
- Unit tests pasan (`src/evaluator.zig:5400-5500`, `src/parser.zig:2250-2350`)
- Block scoping con `let` implementado (BlockStatement + initBlock)
- Arrow functions YA existen
- FALLA: el caso específico del archivo compat

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
function build(first, second = first * 2, third = second * 2) {
    return [first, second, third];
}
console.log(build(1));
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
echo "---"
node /tmp/t.lou 2>&1
# Actual: "UndefinedVariable"; esperado: "1 2 4"
```

## Patrones a seguir
- `src/parser.zig:2250-2350` — unit tests de default params
- `src/evaluator.zig:5400-5500` — unit tests de default params
- `src/environment.zig:125` — `initBlock` para block scoping
- `src/evaluator.zig` — buscar `resolveArgumentIn` o similar (cómo evalúa defaults)
- `src/parser.zig:1189` — `parseFunctionDeclaration` (parsing de defaults)

## Gotchas
- 3 hipótesis del bug:
  1. `let` en block scope dentro de arrow function — verificar `initBlock` se llama correctamente
  2. Default param referencia a param anterior — verificar eval en func_env (no caller_env)
  3. Arrow con defaults combinado con `let` — verificar ambos features funcionan juntos
- DIAGNÓSTICO: agregar print antes del error en vm.zig:1100 para ver qué variable falta
- Cross-check con `temporal-dead-zone.md` — el `let count = 0` puede tener TDZ si se accede antes
- `const multiply = (a = 1, b = 1) => a * b;` — arrow con defaults + const
- Compat test: `tests/compat/default-parameters.lou` debe pasar
- NO debe romper: unit tests existentes
- Cambiar `resolveArgumentIn` para evaluar default en func_env (no caller)

## Código que falla
