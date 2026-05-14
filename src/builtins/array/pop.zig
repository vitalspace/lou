const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");

pub fn Pop(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;

    if (args.len != 1) {
        return .{ .value = .{ .void = {} } }; // Error: pop necesita exactamente 1 argumento (el array)
    }

    const array_val = args[0];
    if (array_val != .array) {
        return .{ .value = .{ .void = {} } }; // Error: el argumento no es un array
    }

    // Remover y retornar el último elemento del array
    if (array_val.array.elements.items.len == 0) {
        return .{ .value = .{ .void = {} } }; // Array vacío, retornar undefined
    }

    const last_element = array_val.array.elements.pop();
    return .{ .value = last_element.? };
}

test "pop returns last element" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .integer = 2 });
    try array.elements.append(array.allocator, .{ .integer = 3 });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Pop(&args, undefined);
    try std.testing.expect(result == .value and result.value.integer == 3);
}

test "pop reduces length" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .integer = 1 });
    try array.elements.append(array.allocator, .{ .integer = 2 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Pop(&args, undefined);
    try std.testing.expectEqual(@as(usize, 1), array.elements.items.len);
}

test "pop empty array returns undefined" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    var args = [_]Types.Value{.{ .array = array }};
    const result = Pop(&args, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "pop no args returns undefined" {
    const result = Pop(&[_]Types.Value{}, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "pop non-array returns undefined" {
    var args = [_]Types.Value{.{ .float = 42.0 }};
    const result = Pop(&args, undefined);
    try std.testing.expect(result == .value and result.value == .void);
}

test "pop returns string element" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .string = "hello" });
    try array.elements.append(array.allocator, .{ .string = "world" });

    var args = [_]Types.Value{.{ .array = array }};
    const result = Pop(&args, undefined);
    try std.testing.expect(result == .value and result.value == .string);
    try std.testing.expectEqualSlices(u8, "world", result.value.string);
}

test "pop single element makes array empty" {
    const array = try Ast.ArrayObject.init(std.testing.allocator);
    defer array.deinit();

    try array.elements.append(array.allocator, .{ .float = 9.9 });

    var args = [_]Types.Value{.{ .array = array }};
    _ = Pop(&args, undefined);
    try std.testing.expectEqual(@as(usize, 0), array.elements.items.len);
}
