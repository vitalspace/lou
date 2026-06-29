// Object.prototype — the singleton prototype shared by all plain object literals.
// Owns stub dispatcher js_objects for: toString, valueOf, hasOwnProperty.
// Each stub is keyed by `@@native = "ObjectProtoMethod"` + `@@name = "<method>"`.
// vm.zig method_call recognizes this marker and dispatches to the right
// native implementation (passing `this` as the receiver).
const std = @import("std");
const runtime = @import("../../types/runtime.zig");
const ObjectValue = runtime.ObjectValue;
const Value = runtime.Value;

const PROTOTYPE_TAG = "ObjectProtoMethod";

/// Build the Object.prototype singleton. Every stub ObjectValue created
/// here is also appended to `objects_list` so the root environment's
/// deinit will free it alongside `proto` itself. Without this tracking,
/// the stubs leak at shutdown (they're not in env.objects otherwise).
pub fn createObjectPrototype(allocator: std.mem.Allocator, objects_list: *std.ArrayList(*ObjectValue)) !*ObjectValue {
    const proto = try ObjectValue.initWithProto(allocator, null);
    try objects_list.append(allocator, proto);

    // toString(): returns "[object Object]" for plain objects.
    {
        const stub = try makeStub(allocator, "toString");
        try objects_list.append(allocator, stub);
        try proto.properties.put("toString", .{ .js_object = stub });
    }
    // valueOf(): returns the receiver (`this`).
    {
        const stub = try makeStub(allocator, "valueOf");
        try objects_list.append(allocator, stub);
        try proto.properties.put("valueOf", .{ .js_object = stub });
    }
    // hasOwnProperty(name): returns true if `name` is a direct property.
    {
        const stub = try makeStub(allocator, "hasOwnProperty");
        try objects_list.append(allocator, stub);
        try proto.properties.put("hasOwnProperty", .{ .js_object = stub });
    }

    return proto;
}

fn makeStub(allocator: std.mem.Allocator, name: []const u8) !*ObjectValue {
    const stub = try ObjectValue.init(allocator);
    try stub.properties.put("@@native", .{ .string = PROTOTYPE_TAG });
    try stub.properties.put("@@name", .{ .string = name });
    return stub;
}

pub fn isObjectPrototypeMethodStub(v: Value) ?[]const u8 {
    if (v != .js_object) return null;
    const obj = v.js_object;
    if (obj.properties.get("@@native")) |tag_val| {
        if (tag_val == .string and std.mem.eql(u8, tag_val.string, PROTOTYPE_TAG)) {
            return obj.properties.get("@@name").?.string;
        }
    }
    return null;
}

pub const TAG = PROTOTYPE_TAG;
