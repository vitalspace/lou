const std = @import("std");
const TokenType = @import("lexer.zig").TokenType;

pub const BuiltinObject = @import("types/runtime.zig").BuiltinObject;
pub const Value = @import("types/runtime.zig").Value;
pub const ClosureValue = @import("types/runtime.zig").ClosureValue;
pub const ArrayObject = @import("types/runtime.zig").ArrayObject;
pub const ArrayIterator = @import("types/runtime.zig").ArrayIterator;
pub const ObjectValue = @import("types/runtime.zig").ObjectValue;

pub const Property = struct {
    key: []const u8,
    value: *Node,
};

pub const NodeType = enum {
    IntegerLiteral, // Literales enteros como 42
    FloatLiteral, // Literales flotantes como 3.14
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
    ConstantDeclaration,
    VariableDeclaration,
    LetDeclaration,
    BlockStatement,
    ForLoop,
    WhileLoop,
    IfStatement,
    ReturnStatement,
    FunctionDeclaration,
    FunctionCall,
    ArrowFunction,
    MemberAccess, // Nuevo: Para console.log (sin llamada)
    MethodCall, // Nuevo: Para console.log() (con llamada)
    ImportStatement,
    ExportStatement,
};

pub const Node = union(NodeType) {
    IntegerLiteral: struct {
        value: i64,
    },
    FloatLiteral: struct {
        value: f64,
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
    ConstantDeclaration: struct {
        name: []const u8,
        value: *Node,
    },
    VariableDeclaration: struct {
        name: []const u8,
        value: *Node,
    },
    LetDeclaration: struct {
        name: []const u8,
        value: *Node,
    },
    BlockStatement: struct {
        statements: []*Node,
    },
    ForLoop: struct {
        init: ?*Node,
        condition: ?*Node,
        increment: ?*Node,
        body: *Node,
    },
    WhileLoop: struct {
        condition: *Node,
        body: *Node,
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
    },
    FunctionCall: struct {
        name: []const u8,
        arguments: []*Node,
    },
    ArrowFunction: struct {
        parameters: [][]const u8,
        body: *Node,
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
};

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
        
        // Bitwise
        .BitAnd, .BitOr, .BitXor, .LeftShift, .RightShift => .Comparison,
        
        // Comparison
        .Equal, .NotEqual, .StrictEqual, .StrictNotEqual => .Comparison,
        .LessThan, .LessThanOrEqual, .GreaterThan, .GreaterThanOrEqual => .Comparison,
        
        // Logical
        .And, .Or => .Logical,
        
        // Nullish coalescing
        .Nullish => .Logical,
        
        // Pipeline
        .Pipe => .Logical,
        
        // Assignment
        .Assign, .PlusAssign, .MinusAssign, .MultiplyAssign, .DivideAssign, .ModuloAssign => .Assign,
        
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
                try writer.print("Property {d}: key=\"{s}\"\n", .{ i, prop.key });
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
        .ConstantDeclaration => |c| {
            try writer.print("ConstantDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{c.name});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(c.value, depth + 2, writer);
        },
        .VariableDeclaration => |v| {
            try writer.print("VariableDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{v.name});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(v.value, depth + 2, writer);
        },
        .LetDeclaration => |v| {
            try writer.print("LetDeclaration:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{v.name});
            try printIdent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try printAst(v.value, depth + 2, writer);
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
        .WhileLoop => |w| {
            try writer.print("WhileLoop:\n", .{});
            try printIdent(writer, depth + 1);
            try writer.print("Condition:\n", .{});
            try printAst(w.condition, depth + 2, writer);
            try printIdent(writer, depth + 1);
            try writer.print("Body:\n", .{});
            try printAst(w.body, depth + 2, writer);
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
    }
}

pub fn freeAst(allocator: std.mem.Allocator, node: *Node) void {
    switch (node.*) {
        .IntegerLiteral => {},
        .FloatLiteral => {},
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
        .ConstantDeclaration => |c| {
            freeAst(allocator, c.value);
        },
        .VariableDeclaration => |v| {
            freeAst(allocator, v.value);
        },
        .LetDeclaration => |v| {
            freeAst(allocator, v.value);
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
        .WhileLoop => |w| {
            freeAst(allocator, w.condition);
            freeAst(allocator, w.body);
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
        .StringLiteral => {},
        .BooleanLiteral => {},
        .VoidLiteral => {},
        .NullLiteral => {},
        .ImportStatement => |i| {
            if (i.named_bindings) |nb| allocator.free(nb);
        },
        .ExportStatement => |e| freeAst(allocator, e.declaration),
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

    // Check intermediate values are initialized to 0.0
    const val0 = arr.get(0);
    try std.testing.expect(val0 != null);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), val0.?.float, 0.001);

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
    init.VariableDeclaration.value.* = Node{ .IntegerLiteral = .{ .value = 0 } };

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
