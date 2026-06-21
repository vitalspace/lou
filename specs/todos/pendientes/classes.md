# Classes

## status
pendiente

## Problema
No existe soporte para declaraciones de clases (`class`), herencia (`extends`/`super`), métodos estáticos, campos privados (`#`), ni getters/setters en objetos literales.
## Contexto

Lou es un intérprete JavaScript escrito en Zig. Las clases son fundamentales en JS moderno (ES2015+). Actualmente solo existen funciones y objetos literales.

## Baseline (qué existe ya)
- Lexer NO tiene keywords `Class`/`Extends`/`Super`/`Static`/`Get`/`Set`
- AST NO tiene `ClassDeclaration`/`SuperExpression`
- `FunctionDeclaration` ya existe (`src/ast.zig:45`) — útil como template
- `NewExpression` ya existe (`src/ast.zig:56`) — `new X()`
- `MemberAccess` ya existe (`src/ast.zig:48`) — `this.name`
- `prototype-chain.md` y `instanceof-operator.md` están pendientes — base para class semantics
- `getter-setter.md` también pendiente

## Quick verify (estado actual)
```bash
echo 'class A {}' > /tmp/t.lou && ./zig-out/bin/lou run /tmp/t.lou 2>&1
# Actual: parse error (class no es keyword)
```

## Patrones a seguir
- `src/ast.zig:45-47` — `FunctionDeclaration`, `FunctionCall`, `ArrowFunction` (templates)
- `src/ast.zig:56` — `NewExpression`
- `src/ast.zig:48-49` — `MemberAccess`, `MethodCall`
- `src/lexer.zig:74-95` — keywords (agregar Class, Extends, Super, Static)
- `src/environment.zig:228-241` — `setVar` para declaración
- `src/parser.zig:1189` — `parseFunctionDeclaration` como template

## Gotchas
- Feature MUY GRANDE: class body, constructor, methods, static, private fields, getters/setters, extends, super
- IMPLEMENTACIÓN MÍNIMA viable:
  1. Lexer: agregar Class, Extends, Super keywords
  2. AST: `ClassDeclaration { name, superclass, methods }`
  3. Parser: parsear class con métodos simples (sin private, sin static, sin getter/setter)
  4. Evaluator: crear constructor (function) + prototype (object) y asignar a env
- Class body parsing: cada método se convierte en `FunctionDeclaration` con nombre
- `new Class(args)`: llamar al constructor con `this = newObject`, `newObject.__proto__ = Class.prototype`
- `super.method()`: buscar en `Class.superclass.prototype`
- Cross-check con `prototype-chain.md` — usa el mismo mecanismo
- Cross-check con `instanceof-operator.md` — `instanceof Class` debe usar prototype chain
- Privados `#field`: storage separado, NO en el HashMap normal
- Si agregás AST nodes, actualizar freeAst (~line 800), printAst (~line 470), evaluator switch (~line 187)

## Código que falla
```js
class Animal {
    constructor(name) {
        this.name = name;
    }
    speak() {
        return this.name + " makes a noise";
    }
}

class Dog extends Animal {
    speak() {
        return this.name + " barks";
    }
}

const d = new Dog("Rex");
console.log(d.speak()); // "Rex barks"
```

## Implementacion sugerida

### 1. Lexer (src/lexer.zig)
Agregar keywords: `Class`, `Extends`, `Super`, `Static`, `Get`, `Set`
Agregar token: `Hash` (#) para campos privados

### 2. AST (src/ast.zig)
Agregar `NodeType`:
- `ClassDeclaration` — `{ name, superclass, body }`
- `ClassExpression` — `const A = class { ... }`
- `MethodDefinition` — `{ key, value, kind, is_static }`
- `SuperExpression` — `super.method()`
- `PropertyAccessor` — `get foo() {}` / `set foo(v) {}`

### 3. Parser (src/parser.zig)
- `parseClassDeclaration()` — parsear `class Name extends Base { ... }`
- `parseClassBody()` — parsear métodos, campos, getters, setters
- Soporte para `static`, `#field`, `get`/`set`

### 4. VM (src/vm.zig)
- Nuevo opcode `class_` para crear prototipos y cadenas de herencia
- Manejo de `super` con referencia al prototipo padre
- Campos privados con storage separado por instancia

### 5. Evaluator (src/evaluator.zig)
- `evaluateClassDeclaration()` — crear función constructora + prototipo
- Herencia prototipal con `__proto__` linkage

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
- src/ast.zig — NodeType enum
- src/parser.zig — parsePrimary(), parseFunctionDeclaration()
- src/vm.zig — Op enum, compileNode()
- src/evaluator.zig — evaluate()

### JS Examples Complejos
```js
// Herencia multi-nivel
class A { constructor() { this.x = 1; } }
class B extends A { constructor() { super(); this.y = 2; } }
class C extends B { constructor() { super(); this.z = 3; } }

// Métodos estáticos
class Math2 {
    static square(x) { return x * x; }
}

// Campos privados
class Counter {
    #count = 0;
    increment() { this.#count++; }
    get value() { return this.#count; }
}

// Getter/Setter
class Temperature {
    #celsius;
    constructor(c) { this.#celsius = c; }
    get fahrenheit() { return this.#celsius * 9/5 + 32; }
    set fahrenheit(f) { this.#celsius = (f - 32) * 5/9; }
}

// Class expression
const MyClass = class { method() { return 42; } };

// super en métodos
class Base {
    greet() { return "hello"; }
}
class Child extends Base {
    greet() { return super.greet() + " world"; }
}
```

### Verificacion
- `class` y `extends` parsean correctamente
- `new Class()` crea instancias con propiedades
- Herencia funciona con `super()`
- Métodos estáticos accesibles en la clase, no en instancias
- Campos privados `#field` solo accesibles dentro de la clase
- `instanceof` funciona con clases

### Comparar salida raw (sin interpretar ANSI)
./zig-out/bin/lou run js/tests/classes.js 2>&1 | od -c
node js/tests/classes.js 2>&1 | od -c

### pendiente
- Implementar lexer, AST, parser, VM y evaluator para clases

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
