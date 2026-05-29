const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn IsArray(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 1) return .{ .value = .{ .boolean = false } };
    return .{ .value = .{ .boolean = args[0] == .array } };
}

const testing = std.testing;

test "isArray returns true for array" {
    const allocator = testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    const array = try Ast.ArrayObject.init(allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = IsArray(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(result.value.boolean);
}

test "isArray returns false for non-array" {
    const allocator = testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    var args1 = [_]Types.Value{.{ .integer = 42 }};
    try testing.expect(!IsArray(&args1, &env).value.boolean);

    var args2 = [_]Types.Value{.{ .string = "hello" }};
    try testing.expect(!IsArray(&args2, &env).value.boolean);

    var args3 = [_]Types.Value{.{ .boolean = true }};
    try testing.expect(!IsArray(&args3, &env).value.boolean);

    var args4 = [_]Types.Value{.{ .null = {} }};
    try testing.expect(!IsArray(&args4, &env).value.boolean);

    var args5 = [_]Types.Value{.{ .void = {} }};
    try testing.expect(!IsArray(&args5, &env).value.boolean);

    var args6 = [_]Types.Value{.{ .float = 3.14 }};
    try testing.expect(!IsArray(&args6, &env).value.boolean);
}

test "isArray no args returns false" {
    const allocator = testing.allocator;
    var env = try Types.Environment.init(allocator, null);
    defer env.deinit();

    const result = IsArray(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .boolean);
    try testing.expect(!result.value.boolean);
}
