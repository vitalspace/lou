const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const Environment = @import("../../evaluator.zig").Environment;

pub fn Create(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    // Object.create(proto[, propertiesObject])
    // Creates a new object with the specified prototype and properties
    
    const obj = Ast.ObjectValue.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.objects.append(env.allocator, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    // If first arg is null, we create an object with null prototype
    if (args.len > 0 and args[0] == .null) {
        // Object with null prototype - no @@proto property needed
        // The object already has no prototype by default
    } else if (args.len > 0 and args[0] == .js_object) {
        // Set the prototype by adding a @@proto marker
        obj.properties.put("@@proto", args[0]) catch {};
    }

    // If second arg is provided and is an object, copy its properties
    if (args.len > 1 and args[1] == .js_object) {
        var it = args[1].js_object.properties.iterator();
        while (it.next()) |entry| {
            // Skip internal @@ properties
            if (entry.key_ptr.*.len > 2 and std.mem.eql(u8, entry.key_ptr.*[0..2], "@@")) continue;
            obj.properties.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
    }

    return .{ .value = .{ .js_object = obj } };
}

const testing = std.testing;

test "Object.create - null prototype" {
    const allocator = testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    var args = [_]Types.Value{Types.Value{ .null = {} }};
    const result = Create(&args, &env);

    try testing.expect(result == .value);
    try testing.expect(result.value == .js_object);
}