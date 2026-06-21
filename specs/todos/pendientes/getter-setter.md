# Getters y Setters

## status
pendiente

## Problema
Los accessors `get` y `set` en objetos literales y clases no están implementados.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Los getters/setters permiten definir propiedades con comportamiento personalizado al leer/escribir.

## Baseline (qué existe ya)
- Lexer NO tiene keywords `get`/`set` contextuales (en JS son contextuales, no reserved words)
- AST `ObjectLiteral` usa `Property` struct simple (`src/ast.zig:15-18`)
- ObjectValue tiene HashMap plano (`src/types/runtime.zig`)
- Property access funciona via `MemberAccess` (`src/evaluator.zig:2213-2239`)
- Faltan: keywords contextuales get/set, AST modification, descriptor storage

## Quick verify (estado actual)
```bash
cat > /tmp/t.lou <<'EOF'
const o = {
    _v: 0,
    get v() { return this._v; },
    set v(x) { this._v = x; }
};
o.v = 42;
console.log(o.v);
EOF
./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (get/set no reconocido como accessor)
```

## Patrones a seguir
- `src/ast.zig:15-18` — `Property` struct (modificar para soportar getter/setter)
- `src/ast.zig:90-92` — `ObjectLiteral` (puede contener accessors)
- `src/parser.zig` — buscar `parseObjectLiteral` o el path de object literal
- `src/types/runtime.zig` — `ObjectValue` (storage para getters/setters)
- `src/evaluator.zig` — `MemberAccess` (check getter al leer)
- ECMAScript 14.3.9 — Property Definition

## Gotchas
- `get` y `set` son CONTEXTUAL keywords — solo son keywords después de `,` o `{` en un object literal
- NO agregarlos a `TokenType` enum — eso los haría reserved words (romperían código válido como `var get = ...`)
- En cambio, en el lexer, cuando se lee `get` o `set` en posición de property name, tratarlos diferente
- O alternativa: agregar tokens `Get`/`Set` y excluir de `isKeyword()` en ciertos contextos
- Property descriptor: extender `Property` o crear `Accessor { kind: get|set, name, body }`
- Storage en ObjectValue: agregar `getters: HashMap([]const u8, *Node)` y `setters: HashMap`
- Si agregás campos a ObjectValue, actualizar init/deinit y todos los allocadores
- Al leer propiedad: si hay getter, ejecutar y retornar resultado
- Al escribir: si hay setter, ejecutar con valor; si solo getter, silenciar (sloppy) o TypeError (strict)
- Cross-check con `classes.md` — getters/setters en clases siguen el mismo patrón
- `this` binding: dentro del getter/setter, `this` apunta al objeto

## Código que falla
```js
const obj = {
    _value: 0,
    get value() { return this._value; },
    set value(v) { this._value = v; }
};
obj.value = 42;
console.log(obj.value); // 42
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keywords: `Get`, `Set` (para uso como property accessors)

### 2. Parser (src/parser.zig)
- En `parseObjectLiteral()`, detectar `get` o `set` seguido de un nombre de propiedad
- `get prop() {}` → accessor de lectura
- `set prop(v) {}` → accessor de escritura

### 3. AST (src/ast.zig)
- Modificar `ObjectLiteral` para distinguir propiedades normales de getters/setters
- Cada propiedad puede tener `kind`: "init", "get", "set"

### 4. VM (src/vm.zig)
- Al leer propiedad con getter: ejecutar la función getter
- Al escribir propiedad con setter: ejecutar la función setter
- Almacenar getters/setters separados de propiedades normales

### 5. Evaluator (src/evaluator.zig)
- Al acceder a propiedad, verificar si tiene getter
- Al asignar propiedad, verificar si tiene setter

## Tests

Añadir un test de compatibilidad en `tests/compat/`. El runner (`tests/compat/run.sh`) compara el output de Lou contra el de Node y solo marca PASS si ambos exit code y stdout normalizado son idénticos.

### Convención de archivos

- `tests/compat/<nombre>.js` — referencia canónica. Debe ejecutarse con `node` y producir el output esperado.
- `tests/compat/<nombre>.lou` — el mismo programa escrito para Lou. Debe producir output idéntico a la versión `.js`.
- Si el spec cubre sintaxis **específica de Lou** (no existente en JS, e.g. `function f() expr` como expression body, `..` range, `match`), omitir el `.js` y dejar solo el `.lou` — el runner marcará SKIP automáticamente.

### Verificación local

```bash
# 1. Lou produce el output esperado
./zig-out/bin/lou run tests/compat/<nombre>.lou

# 2. Node produce el output esperado (si hay .js)
node tests/compat/<nombre>.js

# 3. Diff (debe ser vacío)
diff <(./zig-out/bin/lou run tests/compat/<nombre>.lou 2>&1) \
     <(node tests/compat/<nombre>.js 2>&1)

# 4. Correr toda la suite
bash tests/compat/run.sh
```

### Tests unitarios (parser/lexer/evaluator)

Además del compat test, añadir tests unitarios en el archivo `.zig` correspondiente (`src/parser.zig`, `src/lexer.zig`, `src/evaluator.zig`, etc.) que verifiquen la estructura del AST o el comportamiento del lexer/evaluator para casos individuales. Los unit tests son útiles para casos donde el compat test sería demasiado grande o donde queremos verificar la forma exacta del AST.

## Archivos de referencia
- src/parser.zig — parseObjectLiteral()
- src/ast.zig — ObjectLiteral
- src/vm.zig — get_prop, set_prop

### JS Examples Complejos
```js
// Básico
const temperature = {
    _celsius: 0,
    get fahrenheit() { return this._celsius * 9/5 + 32; },
    set fahrenheit(f) { this._celsius = (f - 32) * 5/9; }
};
temperature.fahrenheit = 212;
console.log(temperature._celsius);    // 100
console.log(temperature.fahrenheit);  // 212

// Getter computado
const circle = {
    radius: 5,
    get area() { return Math.PI * this.radius * this.radius; },
    get circumference() { return 2 * Math.PI * this.radius; }
};
console.log(circle.area);

// Validación en setter
const user = {
    _age: 0,
    set age(value) {
        if (value < 0) throw new Error("Invalid age");
        this._age = value;
    },
    get age() { return this._age; }
};

// Getters en clases
// (requiere classes implementado)
// class Rectangle {
//     constructor(w, h) { this.width = w; this.height = h; }
//     get area() { return this.width * this.height; }
// }

// Solo getter (read-only)
const config = {
    get version() { return "1.0.0"; }
};
console.log(config.version); // "1.0.0"
// config.version = "2.0"; // silent fail o error en strict
```

### Verificacion
- `get prop() {}` se ejecuta al leer la propiedad
- `set prop(v) {}` se ejecuta al asignar la propiedad
- Getters y setters se pueden combinar en la misma propiedad
- `this` dentro de getters/setters apunta al objeto
- Solo getter = propiedad de solo lectura

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/getter-setter.js 2>&1 | od -c
node js/tests/getter-setter.js 2>&1 | od -c

### pendiente
- Implementar keywords, parser, AST, VM y evaluator para get/set

## Edge cases encontrados durante implementación

Listar aquí los bugs, comportamientos inesperados o requisitos descubiertos
mientras se implementaba este spec. Cada edge case debe ser promovido a su
propio spec (usando esta misma plantilla) si requiere cambios de diseño
propios, o documentado inline si es un fix puntual.

Ejemplos de edge cases típicos:
- Comportamiento cuando se mezcla el tipo con primitivos incompatibles
  (TypeError vs coerción silenciosa).
- Formato de impresión / `toString` — sufijo, base, mayúsculas.
- Comparación loose vs strict.
- Conversión a otros tipos (string concat, Number, BigInt).
- División por cero, exponente negativo, overflow.
- Capturabilidad del error por `try/catch` JS (no abortar el proceso).

Plantilla para promover un edge case a spec:
1. Crear `specs/todos/pendientes/<spec>-edge-<caso>.md` siguiendo esta plantilla.
2. Enlazar desde este spec principal con un enlace relativo.
3. Verificar que el test correspondiente cubre el caso.
