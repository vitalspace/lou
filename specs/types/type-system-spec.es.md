# Especificación del Sistema de Tipos

> **Fecha de evaluación**: 2026-05-29
> **Estado**: Análisis de viabilidad y diseño
> **Estado actual**: Sistema de tipos dinámico (runtime `union(enum)`)
> **Objetivo**: Agregar anotaciones de tipo opcionales y verificación estática

---

## 1. Análisis del Estado Actual

### 1.1 Sistema de Valores en Tiempo de Ejecución (`src/types/runtime.zig`)

El intérprete actualmente tiene un **sistema de tipos puramente dinámico** mediante un `union(enum)` de Zig:

```zig
pub const Value = union(enum) {
    float: f64,
    integer: i64,
    string: []const u8,
    boolean: bool,
    array: *ArrayObject,
    object: *const BuiltinObject,
    closure: *ClosureValue,
    iterator: *ArrayIterator,
    js_object: *ObjectValue,
    function: *AstNode,
    generator: *GeneratorObject,
    symbol: *SymbolValue,
    void: void,
    null: void,
};
```

**Observación clave**: `Value` ya codifica etiquetas de tipo en tiempo de ejecución. El evaluador hace dispatch en runtime mediante `switch (value)` — esto ES una forma de verificación de tipos, pero completamente dinámica.

### 1.2 Lo Que Falta

| Característica | Estado | Impacto |
|--------|--------|---------|
| **Anotaciones de tipo** en código fuente | ❌ Ninguna | No se puede escribir `const x: number = 42` |
| **AST de tipos** | ❌ Ninguno | No existe un `Type` union/struct |
| **Pasada de verificación de tipos** | ❌ Ninguna | Sin capa de análisis estático |
| **Keywords de tipo en el lexer** | ❌ Ninguna | `number`, `string`, `boolean` se parsean como identificadores |
| **Gramática de tipos en el parser** | ❌ Ninguna | Sintaxis de dos puntos no reconocida |
| **Tipos de retorno en funciones** | ❌ Ninguno | Ej. `fn add(a, b): number` |
| **Inferencia de tipos** | ❌ Ninguna | Todos los tipos deben declararse explícitamente |
| **Tipos genéricos** | ❌ Ninguno | `Array<number>`, `Map<string, number>` |
| **Errores en tiempo de compilación** | ❌ Ninguno | Las incoherencias de tipo solo se detectan en runtime |

### 1.3 Lo Que Ya Ayuda

| Activo | Detalles |
|--------|---------|
| **Compilador Zig estricto** | El sistema de tipos de Zig puede modelar nuestro verificador limpiamente |
| **Asignador Arena** | Los tipos pueden asignarse en el arena del parser (sin limpieza separada) |
| **Unión Value con etiquetas** | El runtime ya distingue tipos — el verificador estático mapea a las mismas etiquetas |
| **Errores existentes** | Ya existe el patrón `error.TypeMismatch`, `error.UndefinedVariable` |
| **Evaluador monolítico** | Una sola función `evaluate()` — el verificador puede seguir la misma estructura |

---

## 2. Evaluación de Dificultad

### General: **Media-Alta** (~2-4 semanas para una implementación competente)

| Subsistema | Dificultad | Esfuerzo | Justificación |
|-----------|------------|----------|---------------|
| **Cambios en el Lexer** | 🟢 Fácil | 1 día | Agregar ~10 keywords + `:` ya existe |
| **Cambios en el Parser** | 🟡 Media | 2-3 días | Sintaxis de dos puntos, tipos en parámetros, tipo de retorno |
| **Diseño del AST de tipos** | 🟡 Media | 1-2 días | Unión Type + igualdad + subtipado |
| **Verificador básico** | 🟡 Media | 3-5 días | Literales, expresiones, asignaciones |
| **Verificador de funciones** | 🔴 Difícil | 3-5 días | Parámetros/retorno, clausuras, `this` |
| **Verificador de objetos** | 🔴 Difícil | 3-5 días | Tipado estructural, campos opcionales |
| **Tipos compuestos/genéricos** | 🔴 Difícil | 5-10 días | `Array<T>`, genéricos, parámetros de tipo |
| **Inferencia** | 🔴 Difícil | 5-10 días | Inferencia por flujo, unificación |
| **Mensajes de error** | 🟡 Media | 2-3 días | Errores de tipo legibles |
| **Interop con código dinámico** | 🔴 Difícil | 3-5 días | Límites entre código tipado y no tipado |

### Factores de Riesgo

1. **Arena vs. tipos de larga duración**: Los tipos parseados en un archivo pueden necesitar sobrevivir al arena del parser (para tipos de módulos importados). Requiere gestión de memoria cuidadosa.
2. **Límite de tipado gradual**: Si soportamos código tipado y no tipado, la lógica del límite es compleja (checks en runtime vs. garantías estáticas).
3. **Tipos recursivos**: Objetos que se contienen a sí mismos, o tipos mutuamente recursivos, complican la representación de tipos.
4. **Acoplamiento del código existente**: El evaluador, parser y lexer están fuertemente acoplados. Agregar tipos toca todas las capas.

---

## 3. Arquitectura Propuesta

### 3.1 Representación de Tipos (`src/types/type_checker.zig` — NUEVO)

```zig
/// Representación estática de tipos (usada por el verificador)
pub const Type = union(enum) {
    // Primitivos
    number: void,
    string: void,
    boolean: void,
    void: void,       // undefined
    null_val: void,   // null
    any: void,        // dinámico/cualquiera — salta verificación
    
    // Never y unknown (para uso futuro)
    never: void,
    unknown: void,
    
    // Compuestos
    array: *Type,           // Array<element_type>
    object: ObjectType,     // { field: Type, ... }
    function: FunctionType, // (params...) => return_type
    union: UnionType,       // A | B
    
    // Nombrado (para tipos recursivos)
    named: struct { name: []const u8, resolved: ?*Type },
    
    // Variable de tipo (para genéricos)
    variable: struct { id: u64, constraint: ?*Type },
};
```

### 3.2 Cambios en el AST (`src/ast.zig`)

Cada nodo que introduce un binding o devuelve un valor necesita un tipo opcional:

```zig
// FunctionDeclaration gana tipo de retorno opcional + parámetros tipados
FunctionDeclaration: struct {
    name: []const u8,
    parameters: []ParamDecl,   // NUEVO: params tipados
    return_type: ?*TypeNode,   // NUEVO
    body: *Node,
},

// ParamDecl reemplaza []const u8
pub const ParamDecl = struct {
    name: []const u8,
    type: ?*TypeNode,  // NUEVO: ej. `x: number`
};

// Las declaraciones ganan tipo opcional
ConstantDeclaration: struct {
    name: []const u8,
    type: ?*TypeNode,  // NUEVO: const x: number = 42
    value: *Node,
},

// Más: VariableDeclaration, LetDeclaration, ArrowFunction, GeneratorDeclaration
```

### 3.3 Sintaxis de Tipos (Gramática)

```
type        = union_type | primary_type
union_type  = primary_type ("|" primary_type)+
primary_type = "number" | "string" | "boolean" 
             | "void" | "null" | "any" | "never" | "unknown"
             | "Array" "<" type ">"
             | "{" (key ":" type ("," key ":" type)*)? "}"
             | "(" (param ("," param)*)? ")" "=>" type
             | identifier                    // ref. a tipo nombrado
             | "(" type ")"
param       = identifier ":" type
```

### 3.4 Pasada del Verificador de Tipos

Un nuevo módulo `src/type_checker.zig` que:

1. **Recorre el AST** antes de la evaluación
2. **Infiera tipos** de literales y expresiones
3. **Verifique anotaciones de tipo** contra tipos inferidos
4. **Reporte errores** sin detenerse (colecciona todos los errores)
5. **Adjunte tipos resueltos** a los nodos del AST (opcional, para herramientas)

```zig
pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(TypeError),
    scopes: std.ArrayList(std.StringHashMap(*Type)),
    // ...
    
    pub fn check(node: *ast.Node) !?*Type {
        // Recorrer y verificar
    }
};
```

---

## 4. Hoja de Ruta de Implementación

### Fase 1: Fundamentos (Semana 1)

**1.1 Lexer: Agregar keywords de tipo**
- Agregar tokens: `TypeNumber`, `TypeString`, `TypeBoolean`, `TypeVoid`, `TypeNull`, `TypeAny`, `TypeNever`, `TypeUnknown`, `TypeArray`
- Estas son palabras reservadas, no identificadores
- ✅ Dificultad: Fácil. El lexer ya tiene un mapa de keywords.

**1.2 AST de tipos**
- Crear `src/types/type_checker.zig` con la unión `Type` y el AST `TypeNode`
- Función de igualdad de tipos: `typesEqual(a: *Type, b: *Type) bool`
- Subtipado: `isSubtypeOf(child: *Type, parent: *Type) bool`
- Impresor de depuración para tipos
- ✅ Dificultad: Media.

**1.3 Parser: Anotaciones de tipo**
- Agregar función `parseTypeAnnotation()`
- Modificar `parseFunctionDeclaration`, `parseConstantDeclaration`, etc. para consumir `: Type` después de los nombres
- Manejar anotaciones de tipo en parámetros
- ✅ Dificultad: Media. El parser es directo — seguir patrones existentes.

### Fase 2: Verificación Básica de Tipos (Semana 2)

**2.1 Verificación de literales y expresiones**
- Entero literal → `number`
- Flotante literal → `number`
- String literal → `string`
- Booleano literal → `boolean`
- Expresiones binarias: verificar que los tipos de operandos coincidan
- Operadores de comparación: ambos lados deben ser compatibles
- ✅ Dificultad: Media.

**2.2 Verificación de declaraciones**
- `const x: T = expr`: verificar que el tipo de expr sea subtipo de T
- `let x: T = expr`: igual
- `var x: T = expr`: igual
- Sin anotación, inferir de la expresión
- ✅ Dificultad: Media.

**2.3 Bloques y flujo de control**
- If-else: ambas ramas deben tener tipos compatibles
- Bloques: el tipo es el tipo de la última expresión
- For/while loops: la condición debe ser `boolean`
- ✅ Dificultad: Media.

### Fase 3: Funciones (Semana 2-3)

**3.1 Representación de tipos de función**
- `(tipos_param...) tipo_retorno`
- Almacenar en una tabla de tipos de función
- ✅ Dificultad: Media.

**3.2 Verificación de llamadas a función**
- Verificar que los tipos de argumentos coincidan con los tipos de parámetros
- Verificar que el tipo de retorno coincida con la anotación
- Arrow functions: inferir tipo de retorno del cuerpo
- ✅ Dificultad: Difícil.

**3.3 Clausura y ámbito**
- Las funciones capturan tipos del ámbito
- La verificación de funciones recursivas necesita punto fijo
- ✅ Dificultad: Difícil.

### Fase 4: Tipos Compuestos (Semana 3)

**4.1 Tipos Array**
- `Array<number>`, `Array<string>`, etc.
- Sintaxis inline: `number[]`
- Verificación de tipo en acceso por índice
- ✅ Dificultad: Media.

**4.2 Tipos Objeto**
- Tipado estructural: `{x: number, y: number}`
- Verificación de propiedades en exceso
- Campos opcionales: `{x?: number}`
- ✅ Dificultad: Difícil.

### Fase 5: Avanzado (Semana 4+)

**5.1 Tipos unión**
- `number | string`, `T | null`
- Estrechamiento de tipos en bloques if
- ✅ Dificultad: Difícil.

**5.2 Inferencia de tipos**
- Inferencia de tipo de retorno para funciones
- Tipado contextual (ej. literales de array)
- Estrechamiento basado en flujo
- ✅ Dificultad: Muy Difícil.

**5.3 Genéricos**
- `fn identity<T>(x: T): T`
- `Array<T>`
- Monomorfización o borrado de tipos
- ✅ Dificultad: Muy Difícil.

---

## 5. Puntos de Integración

### 5.1 Cómo Fluyen los Tipos a Través del Sistema

```
Código Fuente
    │
    ▼
  Lexer ──► Tokens (NUEVO: TypeNumber, TypeString, ...)
    │
    ▼
  Parser ──► AST (NUEVO: campos TypeNode en declaraciones)
    │           │
    │           ▼
    │      Fase Opcional
    │           │
    │      Verificador de Tipos ──► Errores / Advertencias
    │           │
    ▼           ▼
  Evaluador ──► Valor en Runtime (sin cambios)
```

### 5.2 Estrategia de Tipado Gradual

El enfoque más seguro: **las anotaciones de tipo son OPCIONALES**. El código sin anotaciones salta la verificación de tipos (o usa `any` implícitamente).

```zig
// Todos válidos:
const x = 42                    // sin tipo — sin verificación
const y: number = 42            // con tipo — verificado
const z: string = 42            // ERROR DE TIPO: number ≠ string
```

Esto significa:
- Los scripts Lou existentes siguen funcionando sin cambios
- Los scripts nuevos pueden agregar tipos incrementalmente
- El verificador solo reporta errores para código **explícitamente tipado**
- En una fase futura, inferir tipos para código sin anotaciones y verificar consistencia

### 5.3 Manejo de Errores

Los errores del verificador de tipos NO deben crashear el intérprete (a diferencia de los errores del parser). Estrategia:

1. El verificador se ejecuta como una **pasada separada**
2. Colecciona TODOS los errores en una lista
3. Si hay errores, imprimirlos y **DETENERSE** antes de la evaluación
4. Sin evaluación parcial con errores de tipo

```zig
pub const TypeError = struct {
    location: SourceLocation,
    message: []const u8,
    expected: ?*Type,
    got: ?*Type,
};
```

---

## 6. Gestión de Memoria

Esta es la parte más delicada. Los tipos creados durante el parsing viven en el arena del parser, que se libera después del parsing. Pero el verificador necesita que los tipos sobrevivan.

**Opción A**: El verificador se ejecuta DENTRO del arena del parser
- ✅ Simple — tipos asignados en arena, liberados después de verificar
- ❌ Tipos no disponibles durante la evaluación (pero no los necesitamos en runtime)

**Opción B**: Arena de tipos separado
- ✅ Los tipos sobreviven para herramientas, soporte IDE
- ❌ Gestión de memoria más compleja

**Recomendación**: Opción A para Fase 1-2. Los tipos son un concepto de tiempo de compilación solamente.

---

## 7. Cambios de Código Específicos Necesarios

### 7.1 lexer.zig

Agregar ~10-12 nuevas variantes de `TokenType`:
```zig
pub const TokenType = enum {
    // ... existente ...
    
    // Keywords de tipo
    TypeNumber,
    TypeString,
    TypeBoolean,
    TypeVoid,
    TypeNull,
    TypeAny,
    TypeNever,
    TypeUnknown,
    TypeArray,
};
```

Agregar a `getKeywordType()`:
```zig
.{ "number", .TypeNumber },
.{ "string", .TypeString },
.{ "boolean", .TypeBoolean },
.{ "void", .TypeVoid },
.{ "any", .TypeAny },
.{ "never", .TypeNever },
.{ "unknown", .TypeUnknown },
.{ "Array", .TypeArray },
```

**Impacto**: ~30 líneas. Ningún test existente se rompe.

### 7.2 ast.zig

Agregar la unión `TypeNode` y actualizar las variantes afectadas:

```zig
pub const TypeNode = union(enum) {
    number: void,
    string: void,
    boolean: void,
    void_val: void,
    null_val: void,
    any: void,
    never: void,
    unknown: void,
    array: *TypeNode,
    object: []TypeProperty,
    function: FunctionTypeNode,
    identifier: []const u8,  // tipos definidos por usuario/nombrados
};

pub const TypeProperty = struct {
    name: []const u8,
    typ: *TypeNode,
    optional: bool,
};

pub const FunctionTypeNode = struct {
    param_types: []*TypeNode,
    return_type: *TypeNode,
};
```

Actualizar nodos AST existentes:
```zig
ConstantDeclaration: struct {
    name: []const u8,
    type_annotation: ?*TypeNode,  // NUEVO
    value: *Node,
},

FunctionDeclaration: struct {
    name: []const u8,
    parameters: []ParamDecl,  // CAMBIO: era [][]const u8
    return_type: ?*TypeNode,  // NUEVO
    body: *Node,
},
```

**Impacto**: ~200 líneas. Rompe todo acceso a `parameters` en el evaluador. Toca `invokeFunctionNode`, `evaluateGeneratorNext`, etc.

### 7.3 parser.zig

Agregar `parseTypeAnnotation()`:
```zig
fn parseTypeAnnotation(this: *Parser) !?*ast.TypeNode {
    if (this.current_token.type != .Colon) return null;
    this.nextToken(); // consumir ':'
    return try this.parseType();
}

fn parseType(this: *Parser) !*ast.TypeNode {
    switch (this.current_token.type) {
        .TypeNumber => { this.nextToken(); return createType(.number); },
        .TypeString => { this.nextToken(); return createType(.string); },
        // ... etc
    }
}
```

Actualizar el parsing de declaraciones (ejemplo para `parseConstantDeclaration`):
```zig
fn parseConstantDeclaration(this: *Parser) !*ast.Node {
    this.nextToken(); // consumir 'const'
    const name = this.current_token.literal;
    this.nextToken(); // consumir identifier
    const type_annotation = try this.parseTypeAnnotation(); // NUEVO
    if (this.current_token.type == .Semicolon) {
        // Sin inicializador — válido con anotación
        this.nextToken();
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ConstantDeclaration = .{
            .name = name,
            .type_annotation = type_annotation,
            .value = try this.allocator.create(ast.Node), // dummy
        } };
        node.ConstantDeclaration.value.* = .{ .VoidLiteral = .{} };
        return node;
    }
    this.nextToken(); // consumir '='
    const value = try this.parseExpression();
    // ... resto
}
```

**Impacto**: ~300 líneas. El parser crece ~15% en tamaño.

### 7.4 evaluator.zig

Cambios mínimos necesarios si la verificación de tipos es una pasada separada. El evaluador solo necesita actualizarse si:
1. `ParameterDecl` reemplaza `[]const u8` plano en las declaraciones de función
2. Queremos guardas de tipo en runtime (opcional)

Cambio esencial (manejo de parámetros de función):
```zig
// En invokeFunctionNode:
for (func.parameters, 0..) |param, idx| {
    try func_env.set(param.name, if (idx < args.len) args[idx] else .{ .void = {} });
}
```

**Impacto**: ~50 líneas cambiando `param` a `param.name`.

### 7.5 NUEVO: src/type_checker.zig

Módulo nuevo completo (~1000-2000 líneas dependiendo del conjunto de características).

```zig
pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(TypeError),
    
    pub fn check(self: *TypeChecker, node: *ast.Node) !?*Type {
        switch (node.*) {
            .IntegerLiteral => return &Type{ .number = {} },
            .FloatLiteral => return &Type{ .number = {} },
            .StringLiteral => return &Type{ .string = {} },
            .BooleanLiteral => return &Type{ .boolean = {} },
            .NullLiteral => return &Type{ .null_val = {} },
            .VoidLiteral => return &Type{ .void = {} },
            .BinaryExpression => return self.checkBinaryExpr(node.BinaryExpression),
            // ...
        }
    }
};
```

---

## 8. Resumen: Sí, Es Factible

| Factor | Veredicto |
|--------|-----------|
| **Viabilidad técnica** | ✅ Muy factible. La arquitectura del intérprete (AST → evaluate) soporta limpiamente una pasada intermedia de verificación de tipos. |
| **Dificultad** | 🟡 Media-Alta. La complejidad está en el verificador mismo, no en la integración. |
| **Tiempo estimado** | 2-3 semanas para tipos básicos (number/string/boolean en variables + funciones). 4-6 semanas para tipos compuestos + genéricos. |
| **Riesgo de romper código existente** | 🟢 Bajo. El tipado gradual significa que los scripts existentes funcionan sin cambios. Los cambios en el parser son compatibles hacia atrás (tipos opcionales). |
| **Cambio de código más grande** | Parser (~300 líneas nuevas) + nuevo módulo Verificador (~1000-2000 líneas). |
| **Subsistema más complejo** | Verificador de tipos: igualdad de tipos, subtipado, reporte de errores. |
| **Desafío de memoria** | Los tipos deben sobrevivir al arena del parser o usar un arena separado. |
| **Primer paso recomendado** | Agregar `TypeNode` al AST + parser para anotaciones de tipo en declaraciones `const`. Sin verificador aún — solo parsear e ignorar. |

### Fases Recomendadas

| Fase | Alcance | Tiempo | Valor |
|-------|---------|--------|-------|
| **P0** | TypeNode AST + anotaciones en parser (solo parsear, sin verificar) | 2-3 días | Fundación, desbloquea todo |
| **P1** | Verificador básico (primitivos, vars, expr binarias) | +3-4 días | Atrapa errores simples |
| **P2** | Tipos de función | +3-5 días | Más valioso para contratos de API |
| **P3** | Tipos Array/Objeto | +3-5 días | Cubre mayoría de errores reales |
| **P4** | Genéricos + inferencia | +5-10 días | Experiencia completa tipo TypeScript |

### Conclusión

> **El intérprete está listo para tipos.** El AST y el evaluador son lo suficientemente maduros como para que agregar una capa de anotaciones de tipo sea arquitectónicamente directo. El trabajo real es construir un verificador de tipos correcto — pero eso es un problema de ingeniería de compiladores, no un problema de integración.
>
> **Comienza con la Fase 0**: parsear anotaciones de tipo y almacenarlas en el AST, incluso si no las verificamos aún. Esto inmediatamente expone todos los puntos de integración y crea una base para la verificación incremental.