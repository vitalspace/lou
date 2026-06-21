# Closures Over let/const

## status
implementado

## Problema
`tests/compat/closure-capture.lou` falla con `error: UndefinedVariable` cuando una closure intenta acceder a una variable capturada de un scope exterior:

```js
function makeCounter() {
    let count = 0;
    return function() {
        count = count + 1;
        return count;
    };
}
const c = makeCounter();
console.log(c());
```

Output actual:
```
10
error: UndefinedVariable
/src/evaluator.zig:394:17 in evaluate
```

Output esperado:
```
10
1
2
3
15
hello
200
```

## Contexto
Lou ya soporta closures parcialmente. El primer caso simple (`function read() { return x }`) funciona porque `x` está en el env top-level. Pero las closures sobre `let`/`var` en scopes anidados fallan porque:

1. El env del bloque donde se declara `let count = 0` se deinita al salir del bloque.
2. La función capturada (`function() { count = count + 1 }`) tiene `function_lexical_envs` apuntando al env deiniciado.
3. Cuando la closure intenta leer/escribir `count`, accede a un env ya deiniciado.

## Código que falla
```js
function makeCounter() {
    let count = 0;
    return function() {
        count = count + 1;
        return count;
    };
}
const c = makeCounter();
console.log(c());
```

## Implementacion sugerida
1. Investigar `Environment.deinit` en `src/environment.zig:283`. Cuando un env tiene entradas en `function_lexical_envs`, no debe liberar sus values/functions/etc. porque las closures aún los referencian.
2. Verificar que `function_lexical_envs` se popule correctamente para closures que escapan (no solo para top-level function declarations).
3. Verificar que el `setVar`/`set`/`get` recursivo atraviese correctamente las cadenas de env (incluyendo el lexical env del closure).
4. Para el caso de `count = count + 1`, la asignación debe modificar el `count` del lexical env, no crear uno nuevo en el scope actual.

## Tests
- Unit test: closure capturando `let count` que sobrevive al deinit del block.
- Unit test: closure que muta una variable capturada.
- `tests/compat/closure-capture.lou` debe pasar.

## Verificación
```bash
./zig-out/bin/lou run tests/compat/closure-capture.lou
diff <(./zig-out/bin/lou run tests/compat/closure-capture.lou) \
     <(node tests/compat/closure-capture.js)
```

## pendiente
- ~~Implementar y verificar persistencia de closures sobre variables de block scope.~~

## Solución
La causa raíz: el env donde se crea la closure está en el stack del caller y
se deinita cuando retorna. Sin un lugar persistente donde guardar el env
capturado, la closure queda con un puntero colgando.

### Cambios

**`src/environment.zig`**:
- `cloneToHeap()`: heap-aloja una copia del env (con `parent = self.outer`,
  no `self`) y duplica el HashMap `values`. El tracking de objetos
  heap-allocated (arrays, objects, etc.) se queda en el env original y se
  promueve al outer via el deinit existente — el clon sólo necesita el
  binding del identificador.
- `getFunctionLexicalEnv(node)`: lookup del env capturado recorriendo la
  cadena `outer` (la entrada se promueve hacia arriba en cada deinit).
- `deinit()`: promueve `function_lexical_envs` y `captures` al outer para
  que los clones sobrevivan al deinit del scope que los creó. En el root
  env, los destruye explícitamente con `deinit + destroy`.

**`src/evaluator.zig`**:
- `captureEnvForClosure(env, node)`: helper que llama `cloneToHeap` y
  registra el clon en `env.function_lexical_envs[node]`.
- Las ramas `FunctionDeclaration`, `ArrowFunction`, `GeneratorDeclaration`
  en `evaluate` ahora invocan `captureEnvForClosure(env, node)` antes de
  retornar el valor `.function`.
- `invokeFunctionNode` (FunctionDeclaration y ArrowFunction cases):
  `const parent = env.getFunctionLexicalEnv(func_node) orelse env;` —
  el nuevo func_env se crea con el env capturado como padre, no con
  el env del caller.

**`src/vm.zig`**:
- `expr()` para `FunctionDeclaration` y `ArrowFunction` ahora emite
  `eval_node` en vez de `emitC` con la función como constante, para que
  la captura del env ocurra en runtime (el lexical env sólo existe
  cuando la función literal es evaluada, no cuando se compila).
- `callFuncNode` (ambos paths: compiled chunk y AST fallback): igual
  que en el evaluator, usa `getFunctionLexicalEnv` para resolver el
  parent del func_env.

### Limitaciones conocidas
- `o.m()` con cero args sigue retornando `void` (pre-existente: el
  branch `if (ac > 0)` salta la dispatch entera). La rama else del
  handler `method_call` no invoca métodos user-defined para evitar
  el bug de alignment en `isConstant` que se activa al pasar `obj`
  como `this_val` por ese path. Fuera de scope.
- `outer()()()` (chained call) tiene un bug de alignment pre-existente
  en `isConstant` cuando hay closures anidadas. Fuera de scope.

### Resultados
- `tests/compat/closure-capture.lou` → PASS (diff limpio vs `node`).
- 9/27 compat tests PASS (sin regresiones vs baseline pre-fix).
