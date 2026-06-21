const std = @import("std");
const Types = @import("../types/types.zig");
const map_props = @import("./map/properties.zig");
const set_props = @import("./set/properties.zig");

/// Try to resolve a data property on a js_object by routing through the
/// appropriate type-specific properties module, decided by the `@@type`
/// discriminator stored in `ObjectValue.properties`.
///
/// Returns null when:
///   - the object has no `@@type` tag (plain object literal)
///   - the `@@type` is not a string
///   - the type is recognized but the property is not defined
///   - the type is not handled by any properties module yet
///
/// When this returns null the caller should fall through to the generic
/// `ObjectValue.properties.get(name)` lookup, and finally to method lookup
/// (`getMethod`) before yielding void.
pub fn tryResolveJsObjectProperty(prop_name: []const u8, obj: *const Types.ObjectValue) ?Types.Value {
    const type_tag = obj.properties.get("@@type") orelse return null;
    if (type_tag != .string) return null;
    if (std.mem.eql(u8, type_tag.string, "Set")) {
        return set_props.resolveProperty(prop_name, obj);
    }
    if (std.mem.eql(u8, type_tag.string, "Map")) {
        return map_props.resolveProperty(prop_name, obj);
    }
    return null;
}
