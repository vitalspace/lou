const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Assign(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        const obj = Ast.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
        env.objects.append(env.allocator, obj) catch {
            obj.deinit();
            return .{ .value = .{ .void = {} } };
        };
        return .{ .value = .{ .js_object = obj } };
    }

    const target = args[0];
    if (target != .js_object) {
        return .{ .value = .{ .void = {} } };
    }

    // Create a new object that's a copy of the target
    const result = Ast.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, result) catch {
        result.deinit();
        return .{ .value = .{ .void = {} } };
    };

    var it = target.js_object.properties.iterator();
    while (it.next()) |entry| {
        result.properties.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
    }

    // Copy properties from all source objects
    for (args[1..]) |source| {
        if (source != .js_object) continue;
        
        var src_it = source.js_object.properties.iterator();
        while (src_it.next()) |entry| {
            // Skip internal @@type keys
            if (entry.key_ptr.*.len > 2 and std.mem.eql(u8, entry.key_ptr.*[0..2], "@@")) continue;
            result.properties.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
    }

    return .{ .value = .{ .js_object = result } };
}

const testing = std.testing;

test "Object.assign - empty args" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const result = Assign(&[_]Types.Value{}, &env);
    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
}

test "Object.assign - copy source to target" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    // Create source object via environment to avoid double-free
    const src = Ast.ObjectValue.init(allocator) catch return;
    defer src.deinit();
    src.properties.put("a", Types.Value{ .integer = 1 }) catch {};
    
    var args = [_]Types.Value{ Types.Value{ .js_object = src } };
    const result = Assign(&args, &env);
    
    try testing.expect(result.value == .js_object);
    try testing.expect(result.value.js_object.properties.get("a") != null);
}