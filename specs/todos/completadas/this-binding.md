# `this` binding en llamadas a función

**Estado: implementado** ✅

## Problema (resuelto)

`this` solo se bindeaba en `new Func()` (constructor calls). En llamadas regulares (`Func()`, `obj.method()`), `this` no se asignaba y lanzaba `UndefinedVariable`.

## Implementación

### `invokeFunctionNode` (`src/evaluator.zig`)

- Nuevo parámetro `this_val: ?ast.Value`
- Si es `null`, no hay binding (comportamiento legacy)
- Si tiene valor, se asigna en `func_env` antes de evaluar el body
- Arrow functions NO reciben binding — heredan `this` del scope léxico

### `callFunctionValue`

- Nuevo parámetro `this_val: ?ast.Value`, forward a `invokeFunctionNode`

### Callers actualizados

| Caller | `this` |
|---|---|
| `FunctionCall` (`f(args)`) | `undefined` |
| `NewExpression` (`new f(args)`) | nuevo objeto (refactorizado: ya no se bindea inline en `env.values`) |
| `DirectCall` (`(f)(args)`) | `undefined` |
| `MethodCall` → `.function` (`obj.f()`) | `obj` |
| `MethodCall` → `.js_object` (`obj.f()`) | `obj` (vía `callFunctionValue`) |
| Pipe operator (`x \|> f`) | `undefined` |
| `callFunctionValue` en yield* | el objeto/iterador respectivo |

### Notas

- Lou usa semántica **strict-mode**: `Func()` bindea `this = undefined`, no el global object
- Arrow functions heredan `this` léxicamente (sin binding propio en `invokeFunctionNode`)
- `NewExpression` ya no contamina el environment del caller con `this` temporal

## Pendiente: `this` en clases

Cuando se implementen clases (`class Foo { ... }`), hay que considerar:

- **Constructor**: `new Foo()` → `this` = nueva instancia (ya funciona vía `NewExpression`)
- **Métodos de clase**: `obj.method()` → `this` = la instancia (ya funciona vía `MethodCall`)
- **Métodos estáticos**: `Foo.staticMethod()` → `this` = la clase constructora
- **`super()`** en constructor: llamar al constructor padre con `this` de la clase hija
- **`super.method()`**: resolver método en prototipo padre con `this` de la instancia hija
- **Arrow functions en clases**: mismo comportamiento que ahora (herencia léxica)

Depende de: implementación de `class` como sugar sobre prototipos.

## Referencia

- `src/evaluator.zig` — `invokeFunctionNode`, `FunctionCall`, `MethodCall`, `NewExpression`, `DirectCall`, `callFunctionValue`
- `specs/todos/new-expression.md` — implementación de `new` con `this`
