# Prototype chain

## status

**completado** — 2026-11-26 (compat: 75 PASS / 10 FAIL / 1 SKIP)

`tests/compat/prototype-chain.{js,lou}` produce salida byte-idéntica a Node.

## Problema

La primera divergencia era `typeof obj.toString`: Lou devolvía `"object"` y
Node `"function"`. Los métodos de `Object.prototype` son `js_object` stubs
(despachados por `@@native`), así que `typeof` los clasificaba como objetos.
Además, el evaluador AST solo buscaba propiedades propias en `MemberAccess`,
aunque el VM ya recorría la cadena.

## Implementación

- `src/builtins/object/prototype.zig`: singleton con stubs de `toString`,
  `valueOf` y `hasOwnProperty`; `isObjectPrototypeMethodStub` los identifica.
- `src/types/runtime.zig`: `ObjectValue.prototype` (ya existente) enlaza el
  siguiente eslabón; los literales de objeto del evaluador ahora asignan
  `env.object_prototype`, igual que `make_object` en el VM.
- `typeof` en VM y evaluador: un stub de `Object.prototype` se reporta como
  `"function"`.
- `MemberAccess` del evaluador: recorre `prototype` hasta encontrar la
  propiedad; antes devolvía `undefined` si no era propia.
- `in` recorre la cadena y `instanceof` usa los nombres de constructor
  (ver specs de operadores).

## Verificación

```bash
diff <(./zig-out/bin/lou run tests/compat/prototype-chain.lou) \
     <(node tests/compat/prototype-chain.js)
# sin diferencias
```

El fixture cubre `toString`, `valueOf`, `hasOwnProperty` (propio y heredado),
`typeof obj.toString`, y el retorno de `valueOf() === obj`.

Test unitario en `src/evaluator.zig`: `typeof Object.prototype method is
function` (crea el prototipo y verifica `typeof ({}).toString`).

## Limitaciones

- No existen `constructor`, `isPrototypeOf` ni `propertyIsEnumerable`.
- `Object.create`/`Object.setPrototypeOf` no se ejercitan en el fixture; la
  cadena funciona para literales y objetos creados con `make_object`.
- Los métodos de arrays siguen despachándose por el builtin `Array`, no por
  un `Array.prototype` real.

## Referencias

- `src/builtins/object/prototype.zig`
- `src/evaluator.zig` (`MemberAccess`, `TypeOfExpression`, literales de objeto)
- `src/vm.zig` (`get_prop`, `typeof_op`)
- `specs/todos/hechos/in-operator.md`, `instanceof-operator.md`