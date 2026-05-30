const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn HasOwn(args: []Types.Value, _: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .boolean = false } };

    const obj = args[0];
    if (obj != .js_object) return .{ .value = .{ .boolean = false } };

    const key = switch (args[1]) {
        .string => |s| s,
        .integer => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return .{ .value = .{ .boolean = false } };
            break :blk s;
        },
        .float => |f| blk: {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return .{ .value = .{ .boolean = false } };
            break :blk s;
        },
        .symbol => |sym| sym.description,
        else => return .{ .value = .{ .boolean = false } },
    };

    const has_key = obj.js_object.properties.contains(key);
    return .{ .value = .{ .boolean = has_key } };
}

const testing = std.testing;

test "Object.hasOwn - property exists" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = Ast.ObjectValue.init(allocator) catch return;
    defer obj.deinit();
    obj.properties.put("a", Types.Value{ .integer = 1 }) catch {};

    var args = [_]Types.Value{.{ .js_object = obj }, Types.Value{ .string = "a" }};
    const result = HasOwn(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value.boolean == true);
}

test "Object.hasOwn - property does not exist" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = Ast.ObjectValue.init(allocator) catch return;
    defer obj.deinit();
    obj.properties.put("a", Types.Value{ .integer = 1 }) catch {};

    var args = [_]Types.Value{.{ .js_object = obj }, Types.Value{ .string = "b" }};
    const result = HasOwn(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value.boolean == false);
}