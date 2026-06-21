# Type System Implementation Spec

> **Assessment Date**: 2026-05-29
> **Status**: Feasibility & Design Analysis
> **Current State**: Dynamic type system (runtime `union(enum)`)
> **Goal**: Add optional type annotations and static type checking

---

## 1. Current State Analysis

### 1.1 Runtime Value System (`src/types/runtime.zig`)

The interpreter currently has a **purely dynamic type system** via a Zig `union(enum)`:

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

**Key observation**: `Value` already encodes runtime type tags. The evaluator does runtime dispatch via `switch (value)` — this IS a form of type checking, but completely dynamic.

### 1.2 What's Missing

| Feature | Status | Impact |
|---------|--------|--------|
| **Type annotations** in source | ❌ None | Cannot write `const x: number = 42` |
| **Type AST** | ❌ None | No `Type` union/struct exists |
| **Type checker pass** | ❌ None | No static analysis layer |
| **Lexer type keywords** | ❌ None | `number`, `string`, `boolean` parse as identifiers |
| **Parser type grammar** | ❌ None | Colon syntax not recognized |
| **Function return types** | ❌ None | e.g. `fn add(a, b): number` |
| **Type inference** | ❌ None | All types must be explicitly declared |
| **Generic types** | ❌ None | `Array<number>`, `Map<string, number>` |
| **Compile-time errors** | ❌ None | Type mismatches only caught at runtime |

### 1.3 What Already Helps

| Asset | Details |
|-------|---------|
| **Strict Zig compiler** | Zig's type system can model our type checker cleanly |
| **Arena allocator** | Types can be allocated in the parser arena (no separate cleanup) |
| **Tagged Value union** | The runtime already distinguishes types — static checker maps to same tags |
| **Existing errors** | `error.TypeMismatch`, `error.UndefinedVariable` pattern exists |
| **Monolithic evaluator** | A single `evaluate()` function — type checker can follow same structure |

---

## 2. Difficulty Assessment

### Overall: **Medium-Hard** (~2-4 weeks for a competent implementation)

| Subsystem | Difficulty | Effort | Rationale |
|-----------|------------|--------|-----------|
| **Lexer changes** | 🟢 Easy | 1 day | Add ~10 keywords + `:` already exists |
| **Parser changes** | 🟡 Medium | 2-3 days | Colon syntax, parameter types, return types |
| **Type AST design** | 🟡 Medium | 1-2 days | Type union + equality + subtyping |
| **Type checker (basic)** | 🟡 Medium | 3-5 days | Literals, expressions, assignments |
| **Type checker (functions)** | 🔴 Hard | 3-5 days | Parameter/return checking, closures, `this` |
| **Type checker (objects)** | 🔴 Hard | 3-5 days | Structural typing, optional fields |
| **Compound/generic types** | 🔴 Hard | 5-10 days | `Array<T>`, generics, type params |
| **Inference** | 🔴 Hard | 5-10 days | Flow-based inference, unification |
| **Error messages** | 🟡 Medium | 2-3 days | Human-readable type errors |
| **Interop w/ dynamic code** | 🔴 Hard | 3-5 days | Untyped → typed boundaries |

### Risk Factors

1. **Arena vs. long-lived types**: Types parsed in a file may need to outlive the parser arena (for imported module types). Requires careful memory management.
2. **Gradual typing boundary**: If we support both typed and untyped code, the boundary logic is complex (runtime checks vs. static guarantees).
3. **Recursive types**: Objects containing themselves, or mutually recursive types, complicate the type representation.
4. **Existing codebase coupling**: The evaluator, parser, and lexer are tightly coupled. Adding types touches every layer.

---

## 3. Proposed Architecture

### 3.1 Type Representation (`src/types/type_checker.zig` — NEW)

```zig
/// Static type representation (used by the type checker)
pub const Type = union(enum) {
    // Primitives
    number: void,
    string: void,
    boolean: void,
    void: void,       // undefined
    null_val: void,   // null
    any: void,        // dynamic/any — skip type checking
    
    // Never and unknown (for future use)
    never: void,
    unknown: void,
    
    // Compound
    array: *Type,           // Array<element_type>
    object: ObjectType,     // { field: Type, ... }
    function: FunctionType, // (params...) => return_type
    union: UnionType,       // A | B
    
    // Named (for recursive types)
    named: struct { name: []const u8, resolved: ?*Type },
    
    // Type variable (for generics)
    variable: struct { id: u64, constraint: ?*Type },
};
```

### 3.2 AST Changes (`src/ast.zig`)

Every node that introduces a binding or returns a value needs an optional type:

```zig
// FunctionDeclaration gains optional return type + typed params
FunctionDeclaration: struct {
    name: []const u8,
    parameters: []ParamDecl,   // NEW: typed params
    return_type: ?*TypeNode,   // NEW
    body: *Node,
},

// ParamDecl replaces []const u8
pub const ParamDecl = struct {
    name: []const u8,
    type: ?*TypeNode,  // NEW: e.g. `x: number`
};

// Declarations gain optional type
ConstantDeclaration: struct {
    name: []const u8,
    type: ?*TypeNode,  // NEW: const x: number = 42
    value: *Node,
},

// Plus: VariableDeclaration, LetDeclaration, ArrowFunction, GeneratorDeclaration
```

### 3.3 Type Syntax (Grammar)

```
type        = union_type | primary_type
union_type  = primary_type ("|" primary_type)+
primary_type = "number" | "string" | "boolean" 
             | "void" | "null" | "any" | "never" | "unknown"
             | "Array" "<" type ">"
             | "{" (key ":" type ("," key ":" type)*)? "}"
             | "(" (param ("," param)*)? ")" "=>" type
             | identifier                    // named type reference
             | "(" type ")"
param       = identifier ":" type
```

### 3.4 Type Checker Pass

A new module `src/type_checker.zig` that:

1. **Walks the AST** before evaluation
2. **Infers types** of literals and expressions
3. **Checks type annotations** against inferred types
4. **Reports errors** without halting (collects all errors)
5. **Attaches resolved types** to AST nodes (optional, for tooling)

```zig
pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(TypeError),
    scopes: std.ArrayList(std.StringHashMap(*Type)),
    // ...
    
    pub fn check(node: *ast.Node) !?*Type {
        // Walk and check
    }
};
```

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Week 1)

**1.1 Lexer: Add type keywords**
- Add tokens: `TypeNumber`, `TypeString`, `TypeBoolean`, `TypeVoid`, `TypeNull`, `TypeAny`, `TypeNever`, `TypeUnknown`, `TypeArray`
- These are reserved words, not identifiers
- ✅ Difficulty: Easy. Lexer already has keyword map.

**1.2 Type AST**
- Create `src/types/type_checker.zig` with `Type` union and `TypeNode` AST
- Type equality function: `typesEqual(a: *Type, b: *Type) bool`
- Subtyping: `isSubtypeOf(child: *Type, parent: *Type) bool`
- Debug printer for types
- ✅ Difficulty: Medium.

**1.3 Parser: Type annotations**
- Add `parseTypeAnnotation()` function
- Modify `parseFunctionDeclaration`, `parseConstantDeclaration`, etc. to consume `: Type` after names
- Handle parameter type annotations
- ✅ Difficulty: Medium. Parser is straightforward — follow existing patterns.

### Phase 2: Basic Type Checking (Week 2)

**2.1 Literal & expression checking**
- Integer literal → `number`
- Float literal → `number`
- String literal → `string`
- Boolean literal → `boolean`
- Binary expressions: check operand types match
- Comparison operators: both sides must be compatible
- ✅ Difficulty: Medium.

**2.2 Declaration checking**
- `const x: T = expr`: check that expr's type is subtype of T
- `let x: T = expr`: same
- `var x: T = expr`: same
- If no annotation, infer from expression
- ✅ Difficulty: Medium.

**2.3 Block & control flow**
- If-else: both branches must have compatible types
- Blocks: type is last expression's type
- For/while loops: condition must be `boolean`
- ✅ Difficulty: Medium.

### Phase 3: Functions (Week 2-3)

**3.1 Function type representation**
- `(param_types...) return_type`
- Store in a function type table
- ✅ Difficulty: Medium.

**3.2 Function call checking**
- Check argument types match parameter types
- Check return type matches annotation
- Arrow functions: infer return type from body
- ✅ Difficulty: Hard.

**3.3 Closure and scope**
- Functions capture scope types
- Recursive function checking needs fix-point
- ✅ Difficulty: Hard.

### Phase 4: Compound Types (Week 3)

**4.1 Array types**
- `Array<number>`, `Array<string>`, etc.
- Inline syntax: `number[]`
- Index access type checking
- ✅ Difficulty: Medium.

**4.2 Object types**
- Structural typing: `{x: number, y: number}`
- Excess property checking
- Optional fields: `{x?: number}`
- ✅ Difficulty: Hard.

### Phase 5: Advanced (Week 4+)

**5.1 Union types**
- `number | string`, `T | null`
- Type narrowing in if-blocks
- ✅ Difficulty: Hard.

**5.2 Type inference**
- Return type inference for functions
- Contextual typing (e.g. array literals)
- Flow-based narrowing
- ✅ Difficulty: Very Hard.

**5.3 Generics**
- `fn identity<T>(x: T): T`
- `Array<T>`
- Monomorphization or type-erased
- ✅ Difficulty: Very Hard.

---

## 5. Integration Points

### 5.1 How Types Flow Through the System

```
Source Code
    │
    ▼
  Lexer ──► Tokens (NEW: TypeNumber, TypeString, ...)
    │
    ▼
  Parser ──► AST (NEW: TypeNode fields on declarations)
    │           │
    │           ▼
    │      Optional Phase
    │           │
    │      Type Checker ──► Errors / Warnings
    │           │
    ▼           ▼
  Evaluator ──► Runtime Value (unchanged)
```

### 5.2 Gradual Typing Strategy

The safest approach: **type annotations are OPTIONAL**. Unannotated code skips type checking (or uses `any` implicitly).

```zig
// All valid:
const x = 42                    // untyped — no checks
const y: number = 42            // typed — checked
const z: string = 42            // TYPE ERROR: number ≠ string
```

This means:
- Existing Lou scripts continue to work unchanged
- New scripts can add types incrementally
- The type checker only reports errors for **explicitly typed** code
- In a future phase, infer types for unannotated code and check consistency

### 5.3 Error Handling

Type checker errors must NOT crash the interpreter (unlike parser errors). Strategy:

1. Type checker runs as a **separate pass**
2. Collects ALL errors into a list
3. If errors exist, print them and **STOP** before evaluation
4. No partial evaluation with type errors

```zig
pub const TypeError = struct {
    location: SourceLocation,
    message: []const u8,
    expected: ?*Type,
    got: ?*Type,
};
```

---

## 6. Memory Management

This is the trickiest part. Types created during parsing live in the parser arena, which is freed after parsing. But the type checker needs types to survive.

**Option A**: Type checker runs INSIDE the parser arena
- ✅ Simple — types allocated in arena, freed after checking
- ❌ Types not available during evaluation (but we don't need them at runtime)

**Option B**: Separate type arena
- ✅ Types survive for tooling, IDE support
- ❌ More complex memory management

**Recommendation**: Option A for Phase 1-2. Types are a compile-time concept only.

---

## 7. Specific Code Changes Needed

### 7.1 lexer.zig

Add ~10-12 new `TokenType` variants:
```zig
pub const TokenType = enum {
    // ... existing ...
    
    // Type keywords
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

Add to `getKeywordType()`:
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

**Impact**: ~30 lines. No existing tests break.

### 7.2 ast.zig

Add `TypeNode` union and update affected variants:

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
    identifier: []const u8,  // user-defined/named types
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

Update existing AST nodes:
```zig
ConstantDeclaration: struct {
    name: []const u8,
    type_annotation: ?*TypeNode,  // NEW
    value: *Node,
},

FunctionDeclaration: struct {
    name: []const u8,
    parameters: []ParamDecl,  // CHANGE: was [][]const u8
    return_type: ?*TypeNode,  // NEW
    body: *Node,
},
```

**Impact**: ~200 lines. Breaks all `parameters` access in evaluator. Touches `invokeFunctionNode`, `evaluateGeneratorNext`, etc.

### 7.3 parser.zig

Add `parseTypeAnnotation()`:
```zig
fn parseTypeAnnotation(this: *Parser) !?*ast.TypeNode {
    if (this.current_token.type != .Colon) return null;
    this.nextToken(); // consume ':'
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

Update declaration parsing (example for `parseConstantDeclaration`):
```zig
fn parseConstantDeclaration(this: *Parser) !*ast.Node {
    this.nextToken(); // consume 'const'
    const name = this.current_token.literal;
    this.nextToken(); // consume identifier
    const type_annotation = try this.parseTypeAnnotation(); // NEW
    if (this.current_token.type == .Semicolon) {
        // No initializer — valid with annotation
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
    this.nextToken(); // consume '='
    const value = try this.parseExpression();
    // ... rest
}
```

**Impact**: ~300 lines. Parser grows ~15% in size.

### 7.4 evaluator.zig

Minimal changes needed if type checking is a separate pass. The evaluator only needs updating if:
1. `ParameterDecl` replaces plain `[]const u8` in function declarations
2. We want runtime type guards (optional)

Essential change (function parameter handling):
```zig
// In invokeFunctionNode:
for (func.parameters, 0..) |param, idx| {
    try func_env.set(param.name, if (idx < args.len) args[idx] else .{ .void = {} });
}
```

**Impact**: ~50 lines changing `param` to `param.name`.

### 7.5 NEW: src/type_checker.zig

Complete new module (~1000-2000 lines depending on feature set).

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

## 8. Summary: Yes, It's Feasible

| Factor | Verdict |
|--------|---------|
| **Technical feasibility** | ✅ Very feasible. The interpreter's architecture (AST → evaluate) cleanly supports an intermediate type-checking pass. |
| **Difficulty** | 🟡 Medium-Hard. The complexity is in the type checker itself, not integration. |
| **Time estimate** | 2-3 weeks for basic types (number/string/boolean on variables + functions). 4-6 weeks for compound types + generics. |
| **Risk of breaking existing code** | 🟢 Low. Gradual typing means existing scripts work unchanged. Parser changes are backwards compatible (optional types). |
| **Largest code change** | Parser (~300 lines new) + new Type Checker module (~1000-2000 lines). |
| **Most complex subsystem** | Type checker: type equality, subtyping, error reporting. |
| **Memory challenge** | Types must survive parser arena or use a separate arena. |
| **Recommended first step** | Add `TypeNode` to AST + parser for type annotations on `const` declarations. No checker yet — just parse and ignore. |

### Recommended Phasing

| Phase | Scope | Timeline | Value |
|-------|-------|----------|-------|
| **P0** | TypeNode AST + parser annotations (parse only, no checking) | 2-3 days | Foundation, unblocks everything |
| **P1** | Basic type checker (primitives, vars, binary exprs) | +3-4 days | Catches simple mistakes |
| **P2** | Function types | +3-5 days | Most valuable for API contracts |
| **P3** | Array/Object types | +3-5 days | Covers majority of real errors |
| **P4** | Generics + inference | +5-10 days | Full TypeScript-like experience |

### Bottom Line

> **The interpreter is ready for types.** The AST and evaluator are mature enough that adding a type annotation layer is architecturally straightforward. The real work is building a correct type checker — but that's a compiler engineering problem, not an integration problem.
>
> **Start with Phase 0**: parse type annotations and store them in the AST, even if we don't check them yet. This immediately surfaces all integration points and creates a foundation for incremental checking.