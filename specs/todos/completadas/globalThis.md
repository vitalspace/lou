# globalThis

## status

**completado** — 2026-11-26 (compat: 68 PASS / 17 FAIL / 1 SKIP)

`tests/compat/globalThis.{js,lou}` produce output byte-idéntico a Node.

```bash
diff <(./zig-out/bin/lou run tests/compat/globalThis.lou) <(node tests/compat/globalThis.js)
# sin diferencias
```

## Problema original

`globalThis` no existía: `typeof globalThis` daba `"undefined"` y
`globalThis.x = 1` abortaba con `UndefinedVariable`. El campo
`Environment.global_this` y la creación del objeto en `main.zig` ya estaban
presentes, pero faltaba el puente entre el objeto y el entorno: escribir una
propiedad no creaba el binding y `testVar` no se resolvía.

## Implementación

### Entorno (`src/environment.zig`)

- `globalObject()` devuelve el `globalThis` del entorno raíz.
- `setGlobalProperty(name, value)` escribe la propiedad en el objeto global y
  además la expone como binding en `root.values` (salvo nombres constantes).
- `removeGlobalProperty(name)` elimina ambas vistas para `delete globalThis.x`.
- `syncExistingGlobalProperty` mantiene alineados los bindings creados vía
  `globalThis`: si la propiedad ya existe, una asignación posterior al nombre
  actualiza también la propiedad. Las declaraciones nuevas (`var`/`let`/`const`)
  **no** se publican automáticamente, igual que en un módulo de Node.

### VM (`src/vm.zig`)

- `get_global`: si el nombre no está en valores/funciones/builtins, busca en
  `globalThis.properties`.
- `set_prop`: si el objeto es el `globalThis` raíz, sincroniza el binding con
  `setGlobalProperty`.
- `delete` se delega al evaluador (`eval_node`), que ya elimina ambas vistas.

### Evaluador (`src/evaluator.zig`)

- El lookup de `Identifier` cae a `globalThis.properties` si el nombre no está
  en el entorno.
- `PropertySet`, asignación a miembro y asignación indexada sincronizan el
  binding cuando el objeto es `globalThis`.
- `delete obj.prop` / `delete obj[key]` eliminan el binding global si el objeto
  es `globalThis`.

### `src/main.zig`

Además de la propiedad autorreferente `globalThis.globalThis`, el objeto global
incluye `NaN`, `Infinity` y `undefined`, como en JS.

## Tests

- `tests/compat/globalThis.{js,lou}`: `typeof`, autorreferencia, escritura y
  lectura por propiedad y por identificador, y comparación entre ambos caminos.
- Casos extra verificados contra Node:
  - `globalThis["z"] = 7; z` y asignación posterior a un binding global;
  - `typeof globalThis.NaN/undefined` e `Infinity`;
  - `delete globalThis.x` deja `typeof x === "undefined"`;
  - `var`/`let`/`const` de nivel superior no aparecen en `globalThis`;
  - `typeof globalThis.fn === "undefined"` para declaraciones de función.
- `src/environment.zig`: test unitario de `setGlobalProperty`/
  `removeGlobalProperty` (binding y propiedad sincronizados).

## Limitaciones conocidas

- Los builtins (`console`, `Array`, `Object`, …) y las funciones declaradas no
  se publican como propiedades de `globalThis`.
- No hay `window`/`self`/`global`; solo `globalThis`.
- Asignar a un identificador no declarado (`x = 1` sin `var` ni propiedad
  global) sigue dando `UndefinedVariable`; JS en modo no estricto crearía una
  propiedad global. Es un comportamiento independiente de `globalThis`.

## Referencias

- `src/environment.zig` (`globalObject`, `setGlobalProperty`,
  `removeGlobalProperty`)
- `src/vm.zig` (`get_global`, `set_prop`)
- `src/evaluator.zig` (`Identifier`, `PropertySet`, `DeleteExpression`)
- `src/main.zig` (creación del objeto global)