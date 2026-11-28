const std = @import("std");
const TokenType = @import("lexer.zig").TokenType;

pub const BuiltinObject = @import("types/runtime.zig").BuiltinObject;
pub const Value = @import("types/runtime.zig").Value;
pub const ClosureValue = @import("types/runtime.zig").ClosureValue;
pub const ArrayObject = @import("types/runtime.zig").ArrayObject;
pub const ArrayIterator = @import("types/runtime.zig").ArrayIterator;
pub const ObjectValue = @import("types/runtime.zig").ObjectValue;
pub const SymbolValue = @import("types/runtime.zig").SymbolValue;
pub const WellKnownSymbol = @import("types/runtime.zig").WellKnownSymbol;
pub const GeneratorObject = @import("types/runtime.zig").GeneratorObject;
pub const BigIntValue = @import("types/runtime.zig").BigIntValue;
pub const RegExpValue = @import("types/runtime.zig").RegExpValue;
pub const symbolPropertyName = @import("types/runtime.zig").symbolPropertyName;

pub const PropertyKind = enum { init, get, set };

pub const Property = struct {
    key: []const u8,
    value: *Node,
    kind: PropertyKind = .init,
    key_expr: ?*Node = null,
};

pub const OptionalLinkKind = enum { property, index, call };

pub const OptionalLink = struct {
    kind: OptionalLinkKind,
    optional: bool = false,
    name: []const u8 = "",
    expr: ?*Node = null,
    arguments: []*Node = &[_]*Node{},
};

pub const NodeType = enum {
    IntegerLiteral, // Literales enteros como 42
    FloatLiteral, // Literales flotantes como 3.14
    BigIntLiteral, // Literales BigInt como 42n
    StringLiteral,
    BooleanLiteral,
    NullLiteral, // null
    VoidLiteral, // undefined
    ArrayLiteral, // Nuevo: Para literales de array como [1, 2, 3]
    ArrayIndex,
    ObjectLiteral,
    PropertySet,
    Identifier,
    BinaryExpression,
    Assignment,
    UpdateExpression,
    ConstantDeclaration,
    VariableDeclaration,
    LetDeclaration,
    UsingDeclaration,
    BlockStatement,
    ForLoop,
    ForOfLoop,
    ForInLoop,
    WhileLoop,
    DoWhileLoop,
    IfStatement,
    ReturnStatement,
    FunctionDeclaration,
    FunctionCall,
    ArrowFunction,
    MemberAccess, // Nuevo: Para console.log (sin llamada)
    MethodCall, // Nuevo: Para console.log() (con llamada)
    OptionalChain, // a?.b, a?.[x], a?.(...), a?.b.c
    ImportStatement,
    ExportStatement,
    GeneratorDeclaration,
    YieldExpression,
    AwaitExpression,
    SpreadExpression,
    Elision,
    NewExpression,
    DirectCall,
    BreakStatement,
    ContinueStatement,
    LabeledStatement,
    CommaExpression,
    ConditionalExpression,
    TryCatchFinally,
    ThrowStatement,
    TypeOfExpression,
    DeleteExpression,
    VoidExpression,
    EmptyStatement,
    SwitchStatement,
    SwitchCase,
    ImportMetaExpression,
    DynamicImportExpression,
    ClassDeclaration,
    ClassExpression,
};

pub const ClassMethodKind = enum { method, constructor, get, set };

pub const ClassMethod = struct {
    name: []const u8,
    function: *Node,
    is_static: bool = false,
    kind: ClassMethodKind = .method,
};

pub const ClassField = struct {
    name: []const u8,
    value: ?*Node = null,
    is_static: bool = false,
};

pub const Node = union(NodeType) {
    IntegerLiteral: struct {
        value: i64,
    },
    FloatLiteral: struct {
        value: f64,
    },
    BigIntLiteral: struct {
        value: []const u8, // digit string without 'n' suffix
    },
    StringLiteral: struct {
        value: []const u8,
    },
    BooleanLiteral: struct {
        value: bool,
    },
    NullLiteral: struct {},
    VoidLiteral: struct {},
    ArrayLiteral: struct {
        elements: []*Node,
    },
    ArrayIndex: struct {
        array: *Node,
        index: *Node,
    },
    ObjectLiteral: struct {
        properties: []Property,
    },
    PropertySet: struct {
        object: *Node,
        key: []const u8,
        value: *Node,
    },
    Identifier: struct {
        name: []const u8,
    },
    BinaryExpression: struct {
        left: *Node,
        operator: TokenType,
        right: *Node,
    },
    Assignment: struct {
        name: []const u8,
        value: *Node,
    },
    UpdateExpression: struct {
        operand: *Node, // Identifier, MemberAccess, or ArrayIndex
        prefix: bool,
        operator: TokenType, // .Increment or .Decrement
    },
    ConstantDeclaration: struct {
        name: []const u8,
        value: ?*Node,
    },
    VariableDeclaration: struct {
        name: []const u8,
        value: ?*Node,
    },
    LetDeclaration: struct {
        name: []const u8,
        value: ?*Node,
    },
    UsingDeclaration: struct {
        name: []const u8,
        value: ?*Node,
    },
    BlockStatement: struct {
        statements: []*Node,
        is_scope: bool = true,
    },
    ForLoop: struct {
        init: ?*Node,
        condition: ?*Node,
        increment: ?*Node,
        body: *Node,
    },
    ForOfLoop: struct {
        kind: ForOfKind,
        variable: []const u8,
        iterable: *Node,
        body: *Node,
        is_await: bool = false,
    },
    ForInLoop: struct {
        kind: ForOfKind,
        variable: []const u8,
        object: *Node,
        body: *Node,
    },
    WhileLoop: struct {
        condition: *Node,
        body: *Node,
    },
    DoWhileLoop: struct {
        body: *Node,
        condition: *Node,
    },
    IfStatement: struct {
        condition: *Node,
        consequence: *Node,
        alternative: ?*Node,
    },
    ReturnStatement: struct {
        value: ?*Node, // null for return; without value
    },
    FunctionDeclaration: struct {
        name: []const u8,
        parameters: [][]const u8,
        body: *Node,
        closure_env: ?*anyopaque = null,
        rest_param: ?[]const u8 = null,
        param_defaults: []?*Node = &[_]?*Node{},
        is_async: bool = false,
    },
    FunctionCall: struct {
        name: []const u8,
        arguments: []*Node,
    },
    ArrowFunction: struct {
        parameters: [][]const u8,
        body: *Node,
        closure_env: ?*anyopaque = null,
        rest_param: ?[]const u8 = null,
        param_defaults: []?*Node = &[_]?*Node{},
        is_async: bool = false,
    },
    MemberAccess: struct {
        object: *Node, // Nodo del objeto (ej: Identifier "console")
        property: []const u8, // Nombre de la propiedad (ej: "log")
    },
    MethodCall: struct {
        object: *Node, // Nodo del objeto
        method: []const u8, // Nombre del método
        arguments: []*Node, // Argumentos de la llamada
    },
    OptionalChain: struct {
        base: *Node,
        links: []OptionalLink,
    },
    ImportStatement: struct {
        module_path: []const u8,
        default_binding: ?[]const u8,
        namespace: ?[]const u8,
        named_bindings: ?[]NamedImport,
        side_effect_only: bool,
    },
    ExportStatement: struct {
        declaration: *Node,
        is_default: bool,
    },
    GeneratorDeclaration: struct {
        name: []const u8,
        parameters: [][]const u8,
        body: *Node,
        closure_env: ?*anyopaque = null,
        rest_param: ?[]const u8 = null,
        param_defaults: []?*Node = &[_]?*Node{},
        is_async: bool = false,
    },
    YieldExpression: struct {
        value: ?*Node, // null for bare yield
        is_star: bool, // true for yield*
    },
    AwaitExpression: struct {
        value: *Node,
    },
    SpreadExpression: struct {
        value: *Node,
    },
    Elision: void,
    NewExpression: struct {
        callee: *Node,
        arguments: []*Node,
    },
    DirectCall: struct {
        callee: *Node,
        arguments: []*Node,
    },
    BreakStatement: struct {
        label: ?[]const u8 = null,
        line: u32 = 0,
    },
    ContinueStatement: struct {
        label: ?[]const u8 = null,
        line: u32 = 0,
    },
    LabeledStatement: struct {
        label: []const u8,
        body: *Node,
    },
    CommaExpression: struct {
        expressions: []*Node,
    },
    ConditionalExpression: struct {
        condition: *Node,
        consequent: *Node,
        alternate: *Node,
    },
    TryCatchFinally: struct {
        body: *Node,
        catch_param: ?[]const u8,
        catch_body: ?*Node,
        finally_body: ?*Node,
    },
    ThrowStatement: struct {
        value: *Node,
    },
    TypeOfExpression: struct {
        operand: *Node,
    },
    DeleteExpression: struct {
        operand: *Node,
    },
    VoidExpression: struct {
        operand: *Node,
    },
    EmptyStatement: void,
    SwitchStatement: struct {
        discriminant: *Node,
        cases: []*Node,
    },
    SwitchCase: struct {
        test_expr: ?*Node,
        consequent: *Node,
    },
    ImportMetaExpression: struct {},
    DynamicImportExpression: struct {
        module_path: []const u8,
    },
    ClassDeclaration: struct {
        name: []const u8,
        superclass: ?*Node = null,
        methods: []ClassMethod = &[_]ClassMethod{},
        fields: []ClassField = &[_]ClassField{},
    },
    ClassExpression: struct {
        name: []const u8 = "",
        superclass: ?*Node = null,
        methods: []ClassMethod = &[_]ClassMethod{},
        fields: []ClassField = &[_]ClassField{},
    },
};

pub const ForOfKind = enum { Const, Var, Let };

pub const NamedImport = struct {
    name: []const u8,
    alias: ?[]const u8,
};

pub const Precedence = enum(u8) {
    lowest,
    Assign,
    Logical,
    Comparison,
    Sum,
    Product,
    Highest,
};

pub fn getTokenPrecedence(token_type: TokenType) Precedence {
    return switch (token_type) {
        // Arithmetic
        .Plus, .Minus => .Sum,
        .Multiply, .Divide, .Modulo => .Product,
        .Exponent => .Highest,

        // Bitwise
        .BitAnd, .BitOr, .BitXor, .LeftShift, .RightShift, .UnsignedRightShift => .Comparison,

        // Comparison
        .Equal, .NotEqual, .StrictEqual, .StrictNotEqual => .Comparison,
        .LessThan, .LessThanOrEqual, .GreaterThan, .GreaterThanOrEqual => .Comparison,
        .In, .InstanceOf => .Comparison,

        // Logical
        .And, .Or => .Logical,

        // Nullish coalescing
        .Nullish => .Logical,

        // Pipeline
        .Pipe => .Logical,

        // Assignment
        .Assign, .PlusAssign, .MinusAssign, .MultiplyAssign, .DivideAssign, .ModuloAssign, .PowerAssign => .Assign,
        .AndAssign, .OrAssign, .NullishAssign => .Assign,
        .LeftShiftAssign, .RightShiftAssign, .UnsignedRightShiftAssign => .Assign,

        else => .lowest,
    };
}

fn printIdent(writer: anytype, depth: usize) !void {
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try writer.writeAll(" ");
    }
}

pub fn printAst(node: *Node, depth: usize, writer: anytype) !void {
    switch (node.*) {
        .IntegerLiteral => |i| try writer.print("Integer: {d}\n", .{i.value}),
        .FloatLiteral => |f| try writer.print("Float: {d}\n", .{f.value}),
        .BigIntLiteral => |b| try writer.print("BigInt: {s}n\n", .{b.value}),
        .BooleanLiteral => |b| try writer.print("Boolean: {}\n", .{b.value}),
        .StringLiteral => |s| try writer.print("String: \"{s}\"\n", .{s.value}),
        .ArrayLiteral => |a| {
            try writer.print("ArrayLiteral:\n", .{});
            for (a.elements, 0..) |elem, i| {
                try printIdent(writer, depth + 1);
                try writer.print("Element {d}:\n", .{i});
                try printAst(elem, depth + 2, writer);
            }
        },
        .ArrayIndex => |a| {
            try writer.print("ArrayIndex:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Array:\n", .{});
            try printAst(a.array, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Index:\n", .{});
            try printAst(a.index, depth + 2, writer);
        },
        .ObjectLiteral => |o| {
            try writer.print("ObjectLiteral:\n", .{});
            for (o.properties, 0..) |prop, i| {
                try printIdent(writer, depth + 1);
                const kind_str = switch (prop.kind) {
                    .init => "",
                    .get => "get ",
                    .set => "set ",
                };
                if (prop.key_expr) |ke| {
                    try writer.print("Property {d}: {s}[computed]\n", .{ i, kind_str });
                    try printAst(ke, depth + 2, writer);
                } else {
                    try writer.print("Property {d}: {s}key=\"{s}\"\n", .{ i, kind_str, prop.key });
                }
                try printAst(prop.value, depth + 2, writer);
            }
        },
        .PropertySet => |p| {
            try writer.print("PropertySet:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Object:\n", .{});
            try printAst(p.object, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Key: {s}\n", .{p.key});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(p.value, depth + 2, writer);
        },
        .Identifier => |i| try writer.print("Identifier: {s}\n", .{i.name}),
        .BinaryExpression => |b| {
            try writer.print("BinaryExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Operator: {}\n", .{b.operator});
            try printIdent(writer, depth + 1);
            try writer.print("Left:\n", .{});
            try printAst(b.left, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Right:\n", .{});
            try printAst(b.right, depth + 2, writer);
        },
        .Assignment => |a| {
            try writer.print("Assignment:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{a.name});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(a.value, depth + 2, writer);
        },
        .UpdateExpression => |u| {
            try writer.print("UpdateExpression: {s}prefix={}\n", .{
                if (u.operator == .Increment) "++" else "--",
                u.prefix,
            });
            try printAst(u.operand, depth + 1, writer);
        },
        .ConstantDeclaration => |c| {
            try writer.print("ConstantDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{c.name});
            if (c.value) |val| {
                try printIdent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try printAst(val, depth + 2, writer);
            } else {
                try printIdent(writer, depth + 1);
                try writer.print("(no initializer)\n", .{});
            }
        },
        .VariableDeclaration => |v| {
            try writer.print("VariableDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{v.name});
            if (v.value) |val| {
                try printIdent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try printAst(val, depth + 2, writer);
            } else {
                try printIdent(writer, depth + 1);
                try writer.print("(no initializer)\n", .{});
            }
        },
        .LetDeclaration => |v| {
            try writer.print("LetDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{v.name});
            if (v.value) |val| {
                try printIdent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try printAst(val, depth + 2, writer);
            } else {
                try printIdent(writer, depth + 1);
                try writer.print("(no initializer)\n", .{});
            }
        },
        .UsingDeclaration => |v| {
            try writer.print("UsingDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{v.name});
            if (v.value) |val| {
                try printIdent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try printAst(val, depth + 2, writer);
            } else {
                try printIdent(writer, depth + 1);
                try writer.print("(no initializer)\n", .{});
            }
        },
        .BlockStatement => |b| {
            try writer.print("BlockStatement:\n", .{});
            for (b.statements) |stmt| {
                try printAst(stmt, depth + 1, writer);
            }
        },
        .ForLoop => |f| {
            try writer.print("ForLoop:\n", .{});
            if (f.init) |init| {
                try printIdent(writer, depth + 1);
                try writer.print("Init:\n", .{});
                try printAst(init, depth + 2, writer);
            }
            if (f.condition) |cond| {
                try printIdent(writer, depth + 1);
                try writer.print("Condition:\n", .{});
                try printAst(cond, depth + 2, writer);
            }
            if (f.increment) |inc| {
                try printIdent(writer, depth + 1);
                try writer.print("Increment:\n", .{});
                try printAst(inc, depth + 2, writer);
            }
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(f.body, depth + 2, writer);
        },
        .ForOfLoop => |f| {
            try writer.print("ForOfLoop:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Kind: {s}\n", .{@tagName(f.kind)});
            if (f.is_await) {
                try printIdent(writer, depth + 1);
                try writer.print("Await: true\n", .{});
            }
            try printIdent(writer, depth + 1);
            try writer.print("Variable: {s}\n", .{f.variable});
            try printIdent(writer, depth + 1);
            try writer.print("Iterable:\n", .{});
            try printAst(f.iterable, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(f.body, depth + 2, writer);
        },
        .ForInLoop => |f| {
            try writer.print("ForInLoop:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Kind: {s}\n", .{@tagName(f.kind)});
            try printIdent(writer, depth + 1);
            try writer.print("Variable: {s}\n", .{f.variable});
            try printIdent(writer, depth + 1);
            try writer.print("Object:\n", .{});
            try printAst(f.object, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(f.body, depth + 2, writer);
        },
        .WhileLoop => |w| {
            try writer.print("WhileLoop:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Condition:\n", .{});
            try printAst(w.condition, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(w.body, depth + 2, writer);
        },
        .DoWhileLoop => |d| {
            try writer.print("DoWhileLoop:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(d.body, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Condition:\n", .{});
            try printAst(d.condition, depth + 2, writer);
        },
        .IfStatement => |i| {
            try writer.print("IfStatement:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Condition:\n", .{});
            try printAst(i.condition, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Consequence:\n", .{});
            try printAst(i.consequence, depth + 2, writer);
            if (i.alternative) |alt| {
                try printIdent(writer, depth + 1);
                try writer.print("Alternative:\n", .{});
                try printAst(alt, depth + 2, writer);
            }
        },
        .ReturnStatement => |r| {
            try writer.print("ReturnStatement:\n", .{});
            if (r.value) |val| {
                try printIdent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try printAst(val, depth + 2, writer);
            } else {
                try printIdent(writer, depth + 1);
                try writer.print("Value: void\n", .{});
            }
        },
        .FunctionDeclaration => |f| {
            try writer.print("FunctionDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{f.name});
            try printIdent(writer, depth + 1);
            try writer.print("Parameters: ", .{});
            for (f.parameters, 0..) |param, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}", .{param});
            }
            if (f.rest_param) |rp| {
                try writer.print("{s}...{s}", .{ if (f.parameters.len > 0) ", " else "", rp });
            }
            try writer.print("\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(f.body, depth + 2, writer);
        },
        .FunctionCall => |f| {
            try writer.print("FunctionCall:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{f.name});
            try printIdent(writer, depth + 1);
            try writer.print("Arguments:\n", .{});
            for (f.arguments) |arg| {
                try printAst(arg, depth + 2, writer);
            }
        },
        .ArrowFunction => |f| {
            try writer.print("ArrowFunction:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Parameters: ", .{});
            for (f.parameters, 0..) |param, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}", .{param});
            }
            if (f.rest_param) |rp| {
                try writer.print("{s}...{s}", .{ if (f.parameters.len > 0) ", " else "", rp });
            }
            try writer.print("\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(f.body, depth + 2, writer);
        },
        .MemberAccess => |m| {
            try writer.print("MemberAccess:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Object:\n", .{});
            try printAst(m.object, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Property: {s}\n", .{m.property});
        },
        .MethodCall => |m| {
            try writer.print("MethodCall:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Object:\n", .{});
            try printAst(m.object, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Method: {s}\n", .{m.method});
            try printIdent(writer, depth + 1);
            try writer.print("Arguments:\n", .{});
            for (m.arguments) |arg| {
                try printAst(arg, depth + 2, writer);
            }
        },
        .VoidLiteral => try writer.print("VoidLiteral: undefined\n", .{}),
        .NullLiteral => try writer.print("NullLiteral: null\n", .{}),
        .ImportStatement => |i| {
            try writer.print("ImportStatement:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Module: {s}\n", .{i.module_path});
            if (i.default_binding) |db| {
                try printIdent(writer, depth + 1);
                try writer.print("Default: {s}\n", .{db});
            }
            if (i.namespace) |ns| {
                try printIdent(writer, depth + 1);
                try writer.print("Namespace: {s}\n", .{ns});
            }
            if (i.named_bindings) |nb| {
                try printIdent(writer, depth + 1);
                try writer.print("Named:\n", .{});
                for (nb) |n| {
                    try printIdent(writer, depth + 2);
                    try writer.print("{s}", .{n.name});
                    if (n.alias) |a| try writer.print(" as {s}", .{a});
                    try writer.print("\n", .{});
                }
            }
            if (i.side_effect_only) {
                try printIdent(writer, depth + 1);
                try writer.print("Side effect only: true\n", .{});
            }
        },
        .ExportStatement => |e| {
            try writer.print("ExportStatement:\n", .{});
            if (e.is_default) {
                try printIdent(writer, depth + 1);
                try writer.print("Default: true\n", .{});
            }
            try printIdent(writer, depth + 1);
            try writer.print("Declaration:\n", .{});
            try printAst(e.declaration, depth + 2, writer);
        },
        .GeneratorDeclaration => |g| {
            try writer.print("GeneratorDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{g.name});
            try printIdent(writer, depth + 1);
            try writer.print("Async: {s}\n", .{if (g.is_async) "true" else "false"});
            try printIdent(writer, depth + 1);
            try writer.print("Parameters: ", .{});
            for (g.parameters, 0..) |param, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}", .{param});
            }
            if (g.rest_param) |rp| {
                try writer.print("{s}...{s}", .{ if (g.parameters.len > 0) ", " else "", rp });
            }
            try writer.print("\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(g.body, depth + 2, writer);
        },
        .YieldExpression => |y| {
            if (y.is_star) {
                try writer.print("YieldStarExpression:\n", .{});
            } else {
                try writer.print("YieldExpression:\n", .{});
            }
            if (y.value) |val| {
                try printIdent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try printAst(val, depth + 2, writer);
            }
        },
        .AwaitExpression => |a| {
            try writer.print("AwaitExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(a.value, depth + 2, writer);
        },
        .SpreadExpression => |s| {
            try writer.print("SpreadExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(s.value, depth + 2, writer);
        },
        .NewExpression => |ne| {
            try writer.print("NewExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Callee:\n", .{});
            try printAst(ne.callee, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Arguments:\n", .{});
            for (ne.arguments) |arg| {
                try printAst(arg, depth + 2, writer);
            }
        },
        .DirectCall => |dc| {
            try writer.print("DirectCall:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Callee:\n", .{});
            try printAst(dc.callee, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Arguments:\n", .{});
            for (dc.arguments) |arg| {
                try printAst(arg, depth + 2, writer);
            }
        },
        .BreakStatement => |bs| {
            if (bs.label) |lbl| {
                try writer.print("BreakStatement(label: {s})\n", .{lbl});
            } else {
                try writer.print("BreakStatement\n", .{});
            }
        },
        .ContinueStatement => |cs| {
            if (cs.label) |lbl| {
                try writer.print("ContinueStatement(label: {s})\n", .{lbl});
            } else {
                try writer.print("ContinueStatement\n", .{});
            }
        },
        .LabeledStatement => |ls| {
            try writer.print("LabeledStatement(label: {s}):\n", .{ls.label});
            try printAst(ls.body, depth + 1, writer);
        },
        .CommaExpression => |c| {
            try writer.print("CommaExpression:\n", .{});
            for (c.expressions) |e| {
                try printAst(e, depth + 1, writer);
            }
        },
        .ConditionalExpression => |c| {
            try writer.print("ConditionalExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Condition:\n", .{});
            try printAst(c.condition, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Consequent:\n", .{});
            try printAst(c.consequent, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Alternate:\n", .{});
            try printAst(c.alternate, depth + 2, writer);
        },
        .TryCatchFinally => |tc| {
            try writer.print("TryCatchFinally:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(tc.body, depth + 2, writer);
            if (tc.catch_body) |cb| {
                try printIdent(writer, depth + 1);
                try writer.print("Catch({s}):\n", .{tc.catch_param orelse ""});
                try printAst(cb, depth + 2, writer);
            }
            if (tc.finally_body) |fb| {
                try printIdent(writer, depth + 1);
                try writer.print("Finally:\n", .{});
                try printAst(fb, depth + 2, writer);
            }
        },
        .ThrowStatement => |ts| {
            try writer.print("ThrowStatement:\n", .{});
            try printIdent(writer, depth + 1);
            try printAst(ts.value, depth + 2, writer);
        },
        .TypeOfExpression => |t| {
            try writer.print("TypeOfExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Operand:\n", .{});
            try printAst(t.operand, depth + 2, writer);
        },
        .DeleteExpression => |d| {
            try writer.print("DeleteExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Operand:\n", .{});
            try printAst(d.operand, depth + 2, writer);
        },
        .VoidExpression => |v| {
            try writer.print("VoidExpression:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Operand:\n", .{});
            try printAst(v.operand, depth + 2, writer);
        },
        .EmptyStatement => try writer.print("EmptyStatement\n", .{}),
        .Elision => {
            try writer.print("Elision\n", .{});
        },
        .SwitchStatement => |s| {
            try writer.print("SwitchStatement:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Discriminant:\n", .{});
            try printAst(s.discriminant, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Cases:\n", .{});
            for (s.cases) |c| {
                try printAst(c, depth + 2, writer);
            }
        },
        .SwitchCase => |sc| {
            if (sc.test_expr) |t| {
                try printIdent(writer, depth);
                try writer.print("Case:\n", .{});
                try printIdent(writer, depth + 1);
                try writer.print("Test:\n", .{});
                try printAst(t, depth + 2, writer);
            } else {
                try printIdent(writer, depth);
                try writer.print("Default:\n", .{});
            }
            try printIdent(writer, depth + 1);
            try writer.print("Consequent:\n", .{});
            try printAst(sc.consequent, depth + 2, writer);
        },
        .OptionalChain => |oc| {
            try writer.print("OptionalChain:\n", .{});
            try printAst(oc.base, depth + 1, writer);
            for (oc.links) |link| {
                try printIdent(writer, depth + 1);
                try writer.print("Link {s} optional={}\n", .{ @tagName(link.kind), link.optional });
                if (link.expr) |expr| try printAst(expr, depth + 2, writer);
                for (link.arguments) |arg| try printAst(arg, depth + 2, writer);
            }
        },
        .ImportMetaExpression => try writer.print("ImportMetaExpression\n", .{}),
        .DynamicImportExpression => |di| try writer.print("DynamicImportExpression: {s}\n", .{di.module_path}),
        .ClassDeclaration => |c| {
            try writer.print("ClassDeclaration: {s}\n", .{c.name});
            if (c.superclass) |s| try printAst(s, depth + 1, writer);
            for (c.methods) |m| try printAst(m.function, depth + 1, writer);
        },
        .ClassExpression => |c| {
            try writer.print("ClassExpression: {s}\n", .{c.name});
            if (c.superclass) |s| try printAst(s, depth + 1, writer);
            for (c.methods) |m| try printAst(m.function, depth + 1, writer);
        },
    }
}

/// True when `node` or any descendant is a function/generator literal.
/// Evaluating such a node creates a closure that captures the current
/// scope, so loops whose body contains one need fresh per-iteration
/// bindings and the enclosing call scope must stay alive.
pub fn containsClosure(node: *const Node) bool {
    return switch (node.*) {
        .ArrowFunction, .FunctionDeclaration, .GeneratorDeclaration => true,
        .ArrayLiteral => |a| nodesContainClosure(a.elements),
        .ArrayIndex => |a| containsClosure(a.array) or containsClosure(a.index),
        .ObjectLiteral => |o| blk: {
            for (o.properties) |prop| {
                if (containsClosure(prop.value)) break :blk true;
                if (prop.key_expr) |ke| {
                    if (containsClosure(ke)) break :blk true;
                }
            }
            break :blk false;
        },
        .OptionalChain => |oc| blk: {
            if (containsClosure(oc.base)) break :blk true;
            for (oc.links) |link| {
                if (link.expr) |expr| {
                    if (containsClosure(expr)) break :blk true;
                }
                for (link.arguments) |arg| {
                    if (containsClosure(arg)) break :blk true;
                }
            }
            break :blk false;
        },
        .PropertySet => |p| containsClosure(p.object) or containsClosure(p.value),
        .BinaryExpression => |b| containsClosure(b.left) or containsClosure(b.right),
        .Assignment => |a| containsClosure(a.value),
        .UpdateExpression => |u| containsClosure(u.operand),
        .ConstantDeclaration => |c| if (c.value) |v| containsClosure(v) else false,
        .VariableDeclaration => |v| if (v.value) |v2| containsClosure(v2) else false,
        .LetDeclaration => |v| if (v.value) |v2| containsClosure(v2) else false,
        .UsingDeclaration => |v| if (v.value) |v2| containsClosure(v2) else false,
        .BlockStatement => |b| nodesContainClosure(b.statements),
        .ForLoop => |f| blk: {
            if (f.init) |init| {
                if (containsClosure(init)) break :blk true;
            }
            if (f.condition) |cond| {
                if (containsClosure(cond)) break :blk true;
            }
            if (f.increment) |inc| {
                if (containsClosure(inc)) break :blk true;
            }
            break :blk containsClosure(f.body);
        },
        .ForOfLoop => |f| containsClosure(f.iterable) or containsClosure(f.body),
        .ForInLoop => |f| containsClosure(f.object) or containsClosure(f.body),
        .WhileLoop => |w| containsClosure(w.condition) or containsClosure(w.body),
        .DoWhileLoop => |d| containsClosure(d.body) or containsClosure(d.condition),
        .IfStatement => |i| containsClosure(i.condition) or containsClosure(i.consequence) or
            (if (i.alternative) |alt| containsClosure(alt) else false),
        .ReturnStatement => |r| if (r.value) |v| containsClosure(v) else false,
        .FunctionCall => |f| nodesContainClosure(f.arguments),
        .MethodCall => |m| containsClosure(m.object) or nodesContainClosure(m.arguments),
        .MemberAccess => |m| containsClosure(m.object),
        .ExportStatement => |e| containsClosure(e.declaration),
        .YieldExpression => |y| if (y.value) |v| containsClosure(v) else false,
        .AwaitExpression => |a| containsClosure(a.value),
        .SpreadExpression => |s| containsClosure(s.value),
        .NewExpression => |ne| containsClosure(ne.callee) or nodesContainClosure(ne.arguments),
        .DirectCall => |dc| containsClosure(dc.callee) or nodesContainClosure(dc.arguments),
        .LabeledStatement => |ls| containsClosure(ls.body),
        .CommaExpression => |c| nodesContainClosure(c.expressions),
        .ConditionalExpression => |c| containsClosure(c.condition) or
            containsClosure(c.consequent) or containsClosure(c.alternate),
        .TryCatchFinally => |t| blk: {
            if (containsClosure(t.body)) break :blk true;
            if (t.catch_body) |cb| {
                if (containsClosure(cb)) break :blk true;
            }
            if (t.finally_body) |fb| {
                if (containsClosure(fb)) break :blk true;
            }
            break :blk false;
        },
        .ThrowStatement => |t| containsClosure(t.value),
        .TypeOfExpression => |t| containsClosure(t.operand),
        .DeleteExpression => |d| containsClosure(d.operand),
        .VoidExpression => |v| containsClosure(v.operand),
        .SwitchStatement => |s| blk: {
            if (containsClosure(s.discriminant)) break :blk true;
            break :blk nodesContainClosure(s.cases);
        },
        .SwitchCase => |sc| blk: {
            if (sc.test_expr) |te| {
                if (containsClosure(te)) break :blk true;
            }
            break :blk containsClosure(sc.consequent);
        },
        else => false,
    };
}

fn nodesContainClosure(nodes: []*Node) bool {
    for (nodes) |n| {
        if (containsClosure(n)) return true;
    }
    return false;
}

pub fn freeAst(allocator: std.mem.Allocator, node: *Node) void {
    switch (node.*) {
        .IntegerLiteral => {},
        .FloatLiteral => {},
        .BigIntLiteral => {}, // digit string is owned by the node's allocator; freed elsewhere
        .ArrayLiteral => |a| {
            for (a.elements) |elem| {
                freeAst(allocator, elem);
            }
            allocator.free(a.elements);
        },
        .ArrayIndex => |a| {
            freeAst(allocator, a.array);
            freeAst(allocator, a.index);
        },
        .ObjectLiteral => |o| {
            for (o.properties) |prop| {
                freeAst(allocator, prop.value);
                if (prop.key_expr) |ke| freeAst(allocator, ke);
            }
            allocator.free(o.properties);
        },
        .PropertySet => |p| {
            freeAst(allocator, p.object);
            freeAst(allocator, p.value);
        },
        .Identifier => {},
        .BinaryExpression => |b| {
            freeAst(allocator, b.left);
            freeAst(allocator, b.right);
        },
        .Assignment => |a| {
            freeAst(allocator, a.value);
        },
        .UpdateExpression => |u| {
            freeAst(allocator, u.operand);
        },
        .ConstantDeclaration => |c| {
            if (c.value) |val| freeAst(allocator, val);
        },
        .VariableDeclaration => |v| {
            if (v.value) |val| freeAst(allocator, val);
        },
        .LetDeclaration => |v| {
            if (v.value) |val| freeAst(allocator, val);
        },
        .UsingDeclaration => |v| {
            if (v.value) |val| freeAst(allocator, val);
        },
        .BlockStatement => |b| {
            for (b.statements) |stmt| {
                freeAst(allocator, stmt);
            }
            allocator.free(b.statements);
        },
        .ForLoop => |f| {
            if (f.init) |init| {
                freeAst(allocator, init);
            }
            if (f.condition) |cond| {
                freeAst(allocator, cond);
            }
            if (f.increment) |inc| {
                freeAst(allocator, inc);
            }
            freeAst(allocator, f.body);
        },
        .ForOfLoop => |f| {
            freeAst(allocator, f.iterable);
            freeAst(allocator, f.body);
        },
        .ForInLoop => |f| {
            freeAst(allocator, f.object);
            freeAst(allocator, f.body);
        },
        .WhileLoop => |w| {
            freeAst(allocator, w.condition);
            freeAst(allocator, w.body);
        },
        .DoWhileLoop => |d| {
            freeAst(allocator, d.body);
            freeAst(allocator, d.condition);
        },
        .IfStatement => |i| {
            freeAst(allocator, i.condition);
            freeAst(allocator, i.consequence);
            if (i.alternative) |alt| {
                freeAst(allocator, alt);
            }
        },
        .ReturnStatement => |r| {
            if (r.value) |val| {
                freeAst(allocator, val);
            }
        },
        .FunctionDeclaration => |f| {
            allocator.free(f.parameters);
            freeAst(allocator, f.body);
        },
        .FunctionCall => |f| {
            for (f.arguments) |arg| {
                freeAst(allocator, arg);
            }
            allocator.free(f.arguments);
        },
        .ArrowFunction => |f| {
            allocator.free(f.parameters);
            freeAst(allocator, f.body);
        },
        .MemberAccess => |m| {
            freeAst(allocator, m.object);
        },
        .MethodCall => |m| {
            freeAst(allocator, m.object);
            for (m.arguments) |arg| {
                freeAst(allocator, arg);
            }
            allocator.free(m.arguments);
        },
        .OptionalChain => |oc| {
            freeAst(allocator, oc.base);
            for (oc.links) |link| {
                if (link.expr) |expr| freeAst(allocator, expr);
                for (link.arguments) |arg| freeAst(allocator, arg);
                allocator.free(link.arguments);
            }
            allocator.free(oc.links);
        },
        .StringLiteral => {},
        .BooleanLiteral => {},
        .VoidLiteral => {},
        .NullLiteral => {},
        .ImportStatement => |i| {
            if (i.named_bindings) |nb| allocator.free(nb);
        },
        .ExportStatement => |e| freeAst(allocator, e.declaration),
        .GeneratorDeclaration => |g| {
            allocator.free(g.parameters);
            freeAst(allocator, g.body);
        },
        .YieldExpression => |y| {
            if (y.value) |val| {
                freeAst(allocator, val);
            }
        },
        .AwaitExpression => |a| freeAst(allocator, a.value),
        .SpreadExpression => |s| {
            freeAst(allocator, s.value);
        },
        .NewExpression => |ne| {
            freeAst(allocator, ne.callee);
            for (ne.arguments) |arg| {
                freeAst(allocator, arg);
            }
            allocator.free(ne.arguments);
        },
        .DirectCall => |dc| {
            freeAst(allocator, dc.callee);
            for (dc.arguments) |arg| {
                freeAst(allocator, arg);
            }
            allocator.free(dc.arguments);
        },
        .BreakStatement => {},
        .ContinueStatement => {},
        .LabeledStatement => |ls| {
            freeAst(allocator, ls.body);
        },
        .Elision => {},
        .CommaExpression => |c| {
            for (c.expressions) |e| {
                freeAst(allocator, e);
            }
            allocator.free(c.expressions);
        },
        .ConditionalExpression => |c| {
            freeAst(allocator, c.condition);
            freeAst(allocator, c.consequent);
            freeAst(allocator, c.alternate);
        },
        .TryCatchFinally => |tc| {
            freeAst(allocator, tc.body);
            if (tc.catch_body) |cb| freeAst(allocator, cb);
            if (tc.finally_body) |fb| freeAst(allocator, fb);
        },
        .ThrowStatement => |ts| {
            freeAst(allocator, ts.value);
        },
        .TypeOfExpression => |t| {
            freeAst(allocator, t.operand);
        },
        .DeleteExpression => |d| {
            freeAst(allocator, d.operand);
        },
        .VoidExpression => |v| {
            freeAst(allocator, v.operand);
        },
        .EmptyStatement => {},
        .SwitchStatement => |s| {
            freeAst(allocator, s.discriminant);
            for (s.cases) |c| {
                freeAst(allocator, c);
            }
            allocator.free(s.cases);
        },
        .SwitchCase => |sc| {
            if (sc.test_expr) |t| freeAst(allocator, t);
            freeAst(allocator, sc.consequent);
        },
        .ImportMetaExpression => {},
        .DynamicImportExpression => {},
        .ClassDeclaration => |c| {
            if (c.superclass) |s| freeAst(allocator, s);
            for (c.methods) |m| freeAst(allocator, m.function);
            allocator.free(c.methods);
            for (c.fields) |f| if (f.value) |v| freeAst(allocator, v);
            allocator.free(c.fields);
        },
        .ClassExpression => |c| {
            if (c.superclass) |s| freeAst(allocator, s);
            for (c.methods) |m| freeAst(allocator, m.function);
            allocator.free(c.methods);
            for (c.fields) |f| if (f.value) |v| freeAst(allocator, v);
            allocator.free(c.fields);
        },
    }
    allocator.destroy(node);
}

// ============================================================================
// Tests
// ============================================================================

test "Value union - integer" {
    const val = Value{ .integer = 42 };
    try std.testing.expectEqual(@as(i64, 42), val.integer);
}

test "Value union - float" {
    const val = Value{ .float = 3.14 };
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), val.float, 0.001);
}

test "Value union - string" {
    const val = Value{ .string = "hello" };
    try std.testing.expectEqualStrings("hello", val.string);
}

test "Value union - boolean" {
    const val = Value{ .boolean = true };
    try std.testing.expectEqual(true, val.boolean);
}

test "ArrayObject - init and deinit" {
    const allocator = std.testing.allocator;
    const arr = try ArrayObject.init(allocator);
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 0), arr.elements.items.len);
}

test "ArrayObject - set and get" {
    const allocator = std.testing.allocator;
    const arr = try ArrayObject.init(allocator);
    defer arr.deinit();

    // Set value at index 0
    try arr.set(0, Value{ .integer = 42 });
    try std.testing.expectEqual(@as(usize, 1), arr.elements.items.len);

    const val = arr.get(0);
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), val.?.integer);
}

test "ArrayObject - get out of bounds returns null" {
    const allocator = std.testing.allocator;
    const arr = try ArrayObject.init(allocator);
    defer arr.deinit();

    const val = arr.get(0);
    try std.testing.expect(val == null);
}

test "ArrayObject - set expands array" {
    const allocator = std.testing.allocator;
    const arr = try ArrayObject.init(allocator);
    defer arr.deinit();

    // Set value at index 3 (should expand array)
    try arr.set(3, Value{ .integer = 100 });
    try std.testing.expectEqual(@as(usize, 4), arr.elements.items.len);

    // Check intermediate values are holes
    const val0 = arr.get(0);
    try std.testing.expect(val0 != null);
    try std.testing.expect(val0.? == .hole);

    // Check set value
    const val3 = arr.get(3);
    try std.testing.expect(val3 != null);
    try std.testing.expectEqual(@as(i64, 100), val3.?.integer);
}

test "getTokenPrecedence - operators" {
    try std.testing.expectEqual(Precedence.Sum, getTokenPrecedence(.Plus));
    try std.testing.expectEqual(Precedence.Sum, getTokenPrecedence(.Minus));
    try std.testing.expectEqual(Precedence.Product, getTokenPrecedence(.Multiply));
    try std.testing.expectEqual(Precedence.Product, getTokenPrecedence(.Divide));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.Equal));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.NotEqual));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.StrictEqual));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.StrictNotEqual));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.LessThan));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.LessThanOrEqual));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.GreaterThan));
    try std.testing.expectEqual(Precedence.Comparison, getTokenPrecedence(.GreaterThanOrEqual));
    try std.testing.expectEqual(Precedence.Assign, getTokenPrecedence(.Assign));
    try std.testing.expectEqual(Precedence.lowest, getTokenPrecedence(.Integer));
}

test "freeAst - IntegerLiteral" {
    const allocator = std.testing.allocator;
    const node = try allocator.create(Node);
    node.* = Node{ .IntegerLiteral = .{ .value = 42 } };

    freeAst(allocator, node);
    // Should not leak - verified by test allocator
}

test "freeAst - FloatLiteral" {
    const allocator = std.testing.allocator;
    const node = try allocator.create(Node);
    node.* = Node{ .FloatLiteral = .{ .value = 3.14 } };

    freeAst(allocator, node);
}

test "freeAst - StringLiteral" {
    const allocator = std.testing.allocator;
    const node = try allocator.create(Node);
    node.* = Node{ .StringLiteral = .{ .value = "hello" } };

    freeAst(allocator, node);
}

test "freeAst - BooleanLiteral" {
    const allocator = std.testing.allocator;
    const node = try allocator.create(Node);
    node.* = Node{ .BooleanLiteral = .{ .value = true } };

    freeAst(allocator, node);
}

test "freeAst - Identifier" {
    const allocator = std.testing.allocator;
    const node = try allocator.create(Node);
    node.* = Node{ .Identifier = .{ .name = "foo" } };

    freeAst(allocator, node);
}

test "freeAst - BinaryExpression" {
    const allocator = std.testing.allocator;

    const left = try allocator.create(Node);
    left.* = Node{ .IntegerLiteral = .{ .value = 1 } };

    const right = try allocator.create(Node);
    right.* = Node{ .IntegerLiteral = .{ .value = 2 } };

    const node = try allocator.create(Node);
    node.* = Node{ .BinaryExpression = .{
        .left = left,
        .operator = .Plus,
        .right = right,
    } };

    freeAst(allocator, node);
}

test "freeAst - Assignment" {
    const allocator = std.testing.allocator;

    const value = try allocator.create(Node);
    value.* = Node{ .IntegerLiteral = .{ .value = 42 } };

    const node = try allocator.create(Node);
    node.* = Node{ .Assignment = .{
        .name = "x",
        .value = value,
    } };

    freeAst(allocator, node);
}

test "freeAst - ConstantDeclaration" {
    const allocator = std.testing.allocator;

    const value = try allocator.create(Node);
    value.* = Node{ .IntegerLiteral = .{ .value = 42 } };

    const node = try allocator.create(Node);
    node.* = Node{ .ConstantDeclaration = .{
        .name = "PI",
        .value = value,
    } };

    freeAst(allocator, node);
}

test "freeAst - VariableDeclaration" {
    const allocator = std.testing.allocator;

    const value = try allocator.create(Node);
    value.* = Node{ .IntegerLiteral = .{ .value = 0 } };

    const node = try allocator.create(Node);
    node.* = Node{ .VariableDeclaration = .{
        .name = "count",
        .value = value,
    } };

    freeAst(allocator, node);
}

test "freeAst - VariableDeclaration without initializer" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .VariableDeclaration = .{
        .name = "i",
        .value = null,
    } };

    freeAst(allocator, node);
}

test "freeAst - BlockStatement" {
    const allocator = std.testing.allocator;

    const stmt = try allocator.create(Node);
    stmt.* = Node{ .IntegerLiteral = .{ .value = 1 } };

    const stmts = try allocator.alloc(*Node, 1);
    stmts[0] = stmt;

    const node = try allocator.create(Node);
    node.* = Node{ .BlockStatement = .{ .statements = stmts } };

    freeAst(allocator, node);
}

test "freeAst - ReturnStatement with value" {
    const allocator = std.testing.allocator;

    const value = try allocator.create(Node);
    value.* = Node{ .IntegerLiteral = .{ .value = 42 } };

    const node = try allocator.create(Node);
    node.* = Node{ .ReturnStatement = .{ .value = value } };

    freeAst(allocator, node);
}

test "freeAst - ReturnStatement without value" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .ReturnStatement = .{ .value = null } };

    freeAst(allocator, node);
}

test "freeAst - FunctionDeclaration" {
    const allocator = std.testing.allocator;

    const body = try allocator.create(Node);
    body.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const params = try allocator.alloc([]const u8, 2);
    params[0] = "a";
    params[1] = "b";

    const node = try allocator.create(Node);
    node.* = Node{ .FunctionDeclaration = .{
        .name = "add",
        .parameters = params,
        .body = body,
    } };

    freeAst(allocator, node);
}

test "freeAst - FunctionCall" {
    const allocator = std.testing.allocator;

    const arg = try allocator.create(Node);
    arg.* = Node{ .IntegerLiteral = .{ .value = 42 } };

    const args = try allocator.alloc(*Node, 1);
    args[0] = arg;

    const node = try allocator.create(Node);
    node.* = Node{ .FunctionCall = .{
        .name = "foo",
        .arguments = args,
    } };

    freeAst(allocator, node);
}

test "freeAst - ArrowFunction" {
    const allocator = std.testing.allocator;

    const body = try allocator.create(Node);
    body.* = Node{ .IntegerLiteral = .{ .value = 42 } };

    const params = try allocator.alloc([]const u8, 1);
    params[0] = "x";

    const node = try allocator.create(Node);
    node.* = Node{ .ArrowFunction = .{
        .parameters = params,
        .body = body,
    } };

    freeAst(allocator, node);
}

test "freeAst - WhileLoop" {
    const allocator = std.testing.allocator;

    const condition = try allocator.create(Node);
    condition.* = Node{ .BooleanLiteral = .{ .value = true } };

    const body = try allocator.create(Node);
    body.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const node = try allocator.create(Node);
    node.* = Node{ .WhileLoop = .{
        .condition = condition,
        .body = body,
    } };

    freeAst(allocator, node);
}

test "freeAst - IfStatement without alternative" {
    const allocator = std.testing.allocator;

    const condition = try allocator.create(Node);
    condition.* = Node{ .BooleanLiteral = .{ .value = true } };

    const consequence = try allocator.create(Node);
    consequence.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const node = try allocator.create(Node);
    node.* = Node{ .IfStatement = .{
        .condition = condition,
        .consequence = consequence,
        .alternative = null,
    } };

    freeAst(allocator, node);
}

test "freeAst - IfStatement with alternative" {
    const allocator = std.testing.allocator;

    const condition = try allocator.create(Node);
    condition.* = Node{ .BooleanLiteral = .{ .value = true } };

    const consequence = try allocator.create(Node);
    consequence.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const alternative = try allocator.create(Node);
    alternative.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const node = try allocator.create(Node);
    node.* = Node{ .IfStatement = .{
        .condition = condition,
        .consequence = consequence,
        .alternative = alternative,
    } };

    freeAst(allocator, node);
}

test "freeAst - ForLoop" {
    const allocator = std.testing.allocator;

    const init = try allocator.create(Node);
    init.* = Node{ .VariableDeclaration = .{ .name = "i", .value = try allocator.create(Node) } };
    init.VariableDeclaration.value.?.* = Node{ .IntegerLiteral = .{ .value = 0 } };

    const condition = try allocator.create(Node);
    condition.* = Node{ .BooleanLiteral = .{ .value = true } };

    const increment = try allocator.create(Node);
    increment.* = Node{ .Assignment = .{ .name = "i", .value = try allocator.create(Node) } };
    increment.Assignment.value.* = Node{ .IntegerLiteral = .{ .value = 1 } };

    const body = try allocator.create(Node);
    body.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const node = try allocator.create(Node);
    node.* = Node{ .ForLoop = .{
        .init = init,
        .condition = condition,
        .increment = increment,
        .body = body,
    } };

    freeAst(allocator, node);
}

test "freeAst - ForLoop with null fields" {
    const allocator = std.testing.allocator;

    const body = try allocator.create(Node);
    body.* = Node{ .BlockStatement = .{ .statements = try allocator.alloc(*Node, 0) } };

    const node = try allocator.create(Node);
    node.* = Node{ .ForLoop = .{
        .init = null,
        .condition = null,
        .increment = null,
        .body = body,
    } };

    freeAst(allocator, node);
}

test "freeAst - ArrayLiteral" {
    const allocator = std.testing.allocator;

    const elem = try allocator.create(Node);
    elem.* = Node{ .IntegerLiteral = .{ .value = 1 } };

    const elements = try allocator.alloc(*Node, 1);
    elements[0] = elem;

    const node = try allocator.create(Node);
    node.* = Node{ .ArrayLiteral = .{ .elements = elements } };

    freeAst(allocator, node);
}

test "freeAst - ArrayIndex" {
    const allocator = std.testing.allocator;

    const array = try allocator.create(Node);
    array.* = Node{ .Identifier = .{ .name = "arr" } };

    const index = try allocator.create(Node);
    index.* = Node{ .IntegerLiteral = .{ .value = 0 } };

    const node = try allocator.create(Node);
    node.* = Node{ .ArrayIndex = .{
        .array = array,
        .index = index,
    } };

    freeAst(allocator, node);
}

test "freeAst - MemberAccess" {
    const allocator = std.testing.allocator;

    const object = try allocator.create(Node);
    object.* = Node{ .Identifier = .{ .name = "console" } };

    const node = try allocator.create(Node);
    node.* = Node{ .MemberAccess = .{
        .object = object,
        .property = "log",
    } };

    freeAst(allocator, node);
}

test "freeAst - MethodCall" {
    const allocator = std.testing.allocator;

    const object = try allocator.create(Node);
    object.* = Node{ .Identifier = .{ .name = "console" } };

    const arg = try allocator.create(Node);
    arg.* = Node{ .StringLiteral = .{ .value = "hello" } };

    const args = try allocator.alloc(*Node, 1);
    args[0] = arg;

    const node = try allocator.create(Node);
    node.* = Node{ .MethodCall = .{
        .object = object,
        .method = "log",
        .arguments = args,
    } };

    freeAst(allocator, node);
}

test "printAst - IntegerLiteral" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .IntegerLiteral = .{ .value = 42 } };
    defer freeAst(allocator, node);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printAst(node, 0, &writer);
    try std.testing.expectEqualStrings("Integer: 42\n", writer.buffered());
}

test "printAst - FloatLiteral" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .FloatLiteral = .{ .value = 3.14 } };
    defer freeAst(allocator, node);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printAst(node, 0, &writer);
    try std.testing.expectEqualStrings("Float: 3.14\n", writer.buffered());
}

test "printAst - BooleanLiteral" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .BooleanLiteral = .{ .value = true } };
    defer freeAst(allocator, node);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printAst(node, 0, &writer);
    try std.testing.expectEqualStrings("Boolean: true\n", writer.buffered());
}

test "printAst - StringLiteral" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .StringLiteral = .{ .value = "hello" } };
    defer freeAst(allocator, node);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printAst(node, 0, &writer);
    try std.testing.expectEqualStrings("String: \"hello\"\n", writer.buffered());
}

test "printAst - Identifier" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(Node);
    node.* = Node{ .Identifier = .{ .name = "foo" } };
    defer freeAst(allocator, node);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printAst(node, 0, &writer);
    try std.testing.expectEqualStrings("Identifier: foo\n", writer.buffered());
}

test "printAst - BlockStatement" {
    const allocator = std.testing.allocator;

    const stmts = try allocator.alloc(*Node, 0);

    const node = try allocator.create(Node);
    node.* = Node{ .BlockStatement = .{ .statements = stmts } };
    defer freeAst(allocator, node);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printAst(node, 0, &writer);
    try std.testing.expectEqualStrings("BlockStatement:\n", writer.buffered());
}

test "containsClosure - plain nodes report false" {
    const allocator = std.testing.allocator;

    const body = try allocator.create(Node);
    body.* = Node{ .IntegerLiteral = .{ .value = 1 } };

    const stmts = try allocator.alloc(*Node, 1);
    stmts[0] = body;
    const block = try allocator.create(Node);
    block.* = Node{ .BlockStatement = .{ .statements = stmts } };
    defer freeAst(allocator, block);

    try std.testing.expect(!containsClosure(body));
    try std.testing.expect(!containsClosure(block));
}

test "containsClosure - arrow nested in a block reports true" {
    const allocator = std.testing.allocator;

    const inner = try allocator.create(Node);
    inner.* = Node{ .IntegerLiteral = .{ .value = 2 } };

    const arrow = try allocator.create(Node);
    arrow.* = Node{ .ArrowFunction = .{ .parameters = &.{}, .body = inner } };

    const stmts = try allocator.alloc(*Node, 1);
    stmts[0] = arrow;
    const block = try allocator.create(Node);
    block.* = Node{ .BlockStatement = .{ .statements = stmts } };
    defer freeAst(allocator, block);

    try std.testing.expect(containsClosure(block));
}
