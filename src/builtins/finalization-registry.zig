const std = @import("std");
const Types = @import("../types/types.zig");

/// `new FinalizationRegistry(callback)` constructor.
/// Creates a `.js_object` with `@@type="FinalizationRegistry"` and stores
/// the callback. Since Lou has no GC, callbacks will never fire.
/// The internal `_registrations` array stores `{target, heldValue, unregisterToken}`
/// entries as js_objects so `unregister` can look them up by token.
pub fn FinalizationRegistryConstructor(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    const alloc = env.allocator;

    const obj = Types.ObjectValue.init(alloc) catch return .{ .value = .{ .void = {} } };
    env.objects.append(alloc, obj) catch {
        obj.deinit();
        return .{ .value = .{ .void = {} } };
    };

    obj.properties.put("@@type", .{ .string = "FinalizationRegistry" }) catch {};

    // Store the callback (first argument) if provided
    if (args.len > 0 and (args[0] == .function or args[0] == .closure)) {
        obj.properties.put("_callback", args[0]) catch {};
    }

    return .{ .value = .{ .js_object = obj } };
}

/// `FinalizationRegistry.prototype.register(target, heldValue, unregisterToken?)`
/// Registers an object to be watched. Target must be an object (js_object, array, function).
/// Throws TypeError if target is not an object.
pub fn Register(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2) return .{ .value = .{ .void = {} } };

    const this_val = args[0];
    if (this_val != .js_object) return .{ .value = .{ .void = {} } };
    const this_obj = this_val.js_object;

    // Verify @@type
    const type_tag = this_obj.properties.get("@@type");
    if (type_tag == null or type_tag.? != .string or !std.mem.eql(u8, type_tag.?.string, "FinalizationRegistry")) {
        return .{ .value = .{ .void = {} } };
    }

    const target = args[1];
    // Target must be an object (non-primitive)
    if (target != .js_object and target != .object and target != .array and
        target != .function and target != .closure and target != .generator)
    {
        _ = @import("error.zig").throwError(env, "TypeError", .{ .string = "FinalizationRegistry.prototype.register: target must be an object" });
        return .{ .value = .{ .void = {} } };
    }

    const held_value = args[2];
    const unregister_token: Types.Value = if (args.len > 3) args[3] else .{ .void = {} };

    // Create a registration entry as a js_object
    const alloc = env.allocator;
    const entry = Types.ObjectValue.init(alloc) catch return .{ .value = .{ .void = {} } };
    env.objects.append(alloc, entry) catch {
        entry.deinit();
        return .{ .value = .{ .void = {} } };
    };
    entry.properties.put("target", target) catch {};
    entry.properties.put("heldValue", held_value) catch {};
    entry.properties.put("token", unregister_token) catch {};

    // Store in the registry's _registrations array
    const regs_arr = blk: {
        if (this_obj.properties.get("_registrations")) |r| {
            if (r == .array) break :blk r.array;
        }
        // Create the array lazily
        const arr = @import("../ast.zig").ArrayObject.init(alloc) catch return .{ .value = .{ .void = {} } };
        env.arrays.append(alloc, arr) catch {
            arr.deinit();
            return .{ .value = .{ .void = {} } };
        };
        this_obj.properties.put("_registrations", .{ .array = arr }) catch {
            return .{ .value = .{ .void = {} } };
        };
        break :blk arr;
    };

    regs_arr.elements.append(alloc, .{ .js_object = entry }) catch {};

    return .{ .value = .{ .void = {} } };
}

/// `FinalizationRegistry.prototype.unregister(unregisterToken)`
/// Cancels a registration by its unregister token.
/// Returns true if a registration was found and removed, false otherwise.
pub fn Unregister(args: []Types.Value, _env: *Types.Environment) Types.BuiltinResult {
    _ = _env; // Unused parameter

    if (args.len < 2) return .{ .value = .{ .boolean = false } };

    const this_val = args[0];
    if (this_val != .js_object) return .{ .value = .{ .boolean = false } };
    const this_obj = this_val.js_object;

    // Verify @@type
    const type_tag = this_obj.properties.get("@@type");
    if (type_tag == null or type_tag.? != .string or !std.mem.eql(u8, type_tag.?.string, "FinalizationRegistry")) {
        return .{ .value = .{ .boolean = false } };
    }

    const token = args[1];

    const regs_arr = blk: {
        if (this_obj.properties.get("_registrations")) |r| {
            if (r == .array) break :blk r.array;
        }
        return .{ .value = .{ .boolean = false } };
    };

    // Search for a registration with matching token
    // Use the same loose equality as JS's SameValueZero
    for (regs_arr.elements.items, 0..) |item, i| {
        if (item == .js_object) {
            if (item.js_object.properties.get("token")) |tok| {
                if (valuesEqual(tok, token)) {
                    // Remove by swapping with last element and popping
                    const last = regs_arr.elements.pop() orelse return .{ .value = .{ .boolean = true } };
                    if (i < regs_arr.elements.items.len) {
                        regs_arr.elements.items[i] = last;
                    }
                    return .{ .value = .{ .boolean = true } };
                }
            }
        }
    }

    return .{ .value = .{ .boolean = false } };
}

fn valuesEqual(left: Types.Value, right: Types.Value) bool {
    return switch (left) {
        .integer => |li| switch (right) {
            .integer => |ri| li == ri,
            else => false,
        },
        .float => |lf| switch (right) {
            .float => |rf| lf == rf,
            else => false,
        },
        .string => |ls| switch (right) {
            .string => |rs| std.mem.eql(u8, ls, rs),
            else => false,
        },
        .boolean => |lb| switch (right) {
            .boolean => |rb| lb == rb,
            else => false,
        },
        .void => std.meta.activeTag(right) == .void,
        .null => std.meta.activeTag(right) == .null,
        .js_object => |lo| switch (right) {
            .js_object => |ro| lo == ro,
            else => false,
        },
        .array => |la| switch (right) {
            .array => |ra| la == ra,
            else => false,
        },
        .function => |lf| switch (right) {
            .function => |rf| lf == rf,
            else => false,
        },
        .closure => |lc| switch (right) {
            .closure => |rc| lc == rc,
            else => false,
        },
        .generator => |lg| switch (right) {
            .generator => |rg| lg == rg,
            else => false,
        },
        .object => |lo| switch (right) {
            .object => |ro| lo == ro,
            else => false,
        },
        .symbol => |ls| switch (right) {
            .symbol => |rs| ls.id == rs.id,
            else => false,
        },
        else => false,
    };
}

/// Instance methods on `FinalizationRegistry.prototype`.
pub const FINALIZATION_REGISTRY_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "register", .func = Register },
    .{ .name = "unregister", .func = Unregister },
};

pub const FINALIZATION_REGISTRY_OBJECT = Types.BuiltinObjectImpl{
    .name = "FinalizationRegistry",
    .methods = &FINALIZATION_REGISTRY_METHODS,
};
