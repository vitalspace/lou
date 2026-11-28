const std = @import("std");
const Types = @import("../types/types.zig");
const Ast = @import("../ast.zig");
const Environment = @import("../evaluator.zig").Environment;
const callFunctionValue = @import("../evaluator.zig").callFunctionValue;
const throwError = @import("error.zig").throwError;
const numberFormat = @import("number/format.zig");

pub const TYPE_KEY = "@@type";
pub const BUFFER_BYTES_KEY = "@@buffer_bytes";
pub const TYPED_BUFFER_KEY = "@@typed_buffer";
pub const TYPED_OFFSET_KEY = "@@typed_offset";
pub const TYPED_LENGTH_KEY = "@@typed_length";
pub const TYPED_KIND_KEY = "@@typed_kind";
pub const VIEW_BUFFER_KEY = "@@view_buffer";
pub const VIEW_OFFSET_KEY = "@@view_offset";
pub const VIEW_LENGTH_KEY = "@@view_length";

pub const Kind = enum {
    int8,
    uint8,
    uint8clamped,
    int16,
    uint16,
    int32,
    uint32,
    float32,
    float64,
    bigint64,
    biguint64,
};

const KindInfo = struct {
    name: []const u8,
    bpe: usize,
};

fn kindInfo(kind: Kind) KindInfo {
    return switch (kind) {
        .int8 => .{ .name = "Int8Array", .bpe = 1 },
        .uint8 => .{ .name = "Uint8Array", .bpe = 1 },
        .uint8clamped => .{ .name = "Uint8ClampedArray", .bpe = 1 },
        .int16 => .{ .name = "Int16Array", .bpe = 2 },
        .uint16 => .{ .name = "Uint16Array", .bpe = 2 },
        .int32 => .{ .name = "Int32Array", .bpe = 4 },
        .uint32 => .{ .name = "Uint32Array", .bpe = 4 },
        .float32 => .{ .name = "Float32Array", .bpe = 4 },
        .float64 => .{ .name = "Float64Array", .bpe = 8 },
        .bigint64 => .{ .name = "BigInt64Array", .bpe = 8 },
        .biguint64 => .{ .name = "BigUint64Array", .bpe = 8 },
    };
}

pub fn isConstructorName(name: []const u8) bool {
    const names = [_][]const u8{
        "ArrayBuffer",   "SharedArrayBuffer", "DataView",
        "Int8Array",     "Uint8Array",        "Uint8ClampedArray",
        "Int16Array",    "Uint16Array",       "Int32Array",
        "Uint32Array",   "Float32Array",      "Float64Array",
        "BigInt64Array", "BigUint64Array",
    };
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn tagOf(value: Types.Value) ?[]const u8 {
    if (value != .js_object) return null;
    const tag = value.js_object.properties.get(TYPE_KEY) orelse return null;
    if (tag != .string) return null;
    return tag.string;
}

pub fn getTag(value: Types.Value) ?[]const u8 {
    return tagOf(value);
}

pub fn isArrayBuffer(value: Types.Value) bool {
    const tag = tagOf(value) orelse return false;
    return std.mem.eql(u8, tag, "ArrayBuffer") or std.mem.eql(u8, tag, "SharedArrayBuffer");
}

pub fn isTypedArray(value: Types.Value) bool {
    const tag = tagOf(value) orelse return false;
    return std.mem.eql(u8, tag, "TypedArray");
}

pub fn isDataView(value: Types.Value) bool {
    const tag = tagOf(value) orelse return false;
    return std.mem.eql(u8, tag, "DataView");
}

pub fn isManaged(value: Types.Value) bool {
    return isArrayBuffer(value) or isTypedArray(value) or isDataView(value);
}

pub fn getKind(value: Types.Value) ?Kind {
    if (!isTypedArray(value)) return null;
    const raw = value.js_object.properties.get(TYPED_KIND_KEY) orelse return null;
    if (raw != .string) return null;
    const enum_info = @typeInfo(Kind).@"enum";
    inline for (enum_info.field_values) |enum_value| {
        const k: Kind = @fromBackingInt(@intCast(enum_value));
        if (std.mem.eql(u8, kindInfo(k).name, raw.string)) return k;
    }
    return null;
}

pub fn kindName(kind: Kind) []const u8 {
    return kindInfo(kind).name;
}

pub fn getLength(value: Types.Value) usize {
    if (!isTypedArray(value)) return 0;
    const raw = value.js_object.properties.get(TYPED_LENGTH_KEY) orelse return 0;
    if (raw != .integer or raw.integer < 0) return 0;
    return @intCast(raw.integer);
}

fn getOffset(value: Types.Value) usize {
    const raw = value.js_object.properties.get(TYPED_OFFSET_KEY) orelse return 0;
    if (raw != .integer or raw.integer < 0) return 0;
    return @intCast(raw.integer);
}

fn getBytesFromBuffer(buffer: Types.Value) ?[]u8 {
    if (!isArrayBuffer(buffer)) return null;
    const raw = buffer.js_object.properties.get(BUFFER_BYTES_KEY) orelse return null;
    if (raw != .string) return null;
    return @constCast(raw.string);
}

fn bytesOfView(value: Types.Value) ?[]u8 {
    const buffer = value.js_object.properties.get(TYPED_BUFFER_KEY) orelse return null;
    return getBytesFromBuffer(buffer);
}

fn viewBuffer(value: Types.Value) ?Types.Value {
    return value.js_object.properties.get(TYPED_BUFFER_KEY);
}

fn viewByteLength(value: Types.Value) usize {
    if (!isTypedArray(value)) return 0;
    return getLength(value) * kindInfo(getKind(value) orelse return 0).bpe;
}

fn allocateBuffer(env: *Environment, len: usize, shared: bool) !*Types.ObjectValue {
    const bytes = try env.allocator.alloc(u8, len);
    var transferred = false;
    errdefer if (!transferred) env.allocator.free(bytes);
    @memset(bytes, 0);

    const obj = try Types.ObjectValue.init(env.allocator);
    errdefer obj.deinit();

    try obj.properties.put(TYPE_KEY, .{ .string = if (shared) "SharedArrayBuffer" else "ArrayBuffer" });
    try obj.properties.put(BUFFER_BYTES_KEY, .{ .string = bytes });
    try env.owned_strings.append(env.allocator, bytes);
    transferred = true;
    try env.objects.append(env.allocator, obj);
    return obj;
}

fn createView(env: *Environment, kind: Kind, buffer: Types.Value, byte_offset: usize, length: usize) !Types.Value {
    const info = kindInfo(kind);
    const bytes = getBytesFromBuffer(buffer) orelse return error.InvalidBuffer;
    if (byte_offset % info.bpe != 0) return error.InvalidOffset;
    if (byte_offset > bytes.len) return error.InvalidOffset;
    if (length > (bytes.len - byte_offset) / info.bpe) return error.InvalidLength;

    const obj = try Types.ObjectValue.init(env.allocator);
    errdefer obj.deinit();
    try obj.properties.put(TYPE_KEY, .{ .string = "TypedArray" });
    try obj.properties.put(TYPED_KIND_KEY, .{ .string = info.name });
    try obj.properties.put(TYPED_BUFFER_KEY, buffer);
    try obj.properties.put(TYPED_OFFSET_KEY, .{ .integer = @intCast(byte_offset) });
    try obj.properties.put(TYPED_LENGTH_KEY, .{ .integer = @intCast(length) });
    try env.objects.append(env.allocator, obj);
    return .{ .js_object = obj };
}

fn createDataView(env: *Environment, buffer: Types.Value, byte_offset: usize, length: usize) !Types.Value {
    const bytes = getBytesFromBuffer(buffer) orelse return error.InvalidBuffer;
    if (byte_offset > bytes.len or length > bytes.len - byte_offset) return error.InvalidLength;

    const obj = try Types.ObjectValue.init(env.allocator);
    errdefer obj.deinit();
    try obj.properties.put(TYPE_KEY, .{ .string = "DataView" });
    try obj.properties.put(VIEW_BUFFER_KEY, buffer);
    try obj.properties.put(VIEW_OFFSET_KEY, .{ .integer = @intCast(byte_offset) });
    try obj.properties.put(VIEW_LENGTH_KEY, .{ .integer = @intCast(length) });
    try env.objects.append(env.allocator, obj);
    return .{ .js_object = obj };
}

fn toIndex(value: Types.Value) ?usize {
    return switch (value) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| blk: {
            if (std.math.isNan(f) or f < 0 or f > 9007199254740991.0) break :blk null;
            break :blk @intFromFloat(@trunc(f));
        },
        .big_int => |b| blk: {
            const i = b.toI64() orelse break :blk null;
            if (i < 0) break :blk null;
            break :blk @intCast(i);
        },
        .boolean => |b| if (b) 1 else 0,
        .null => 0,
        .void => 0,
        .string => |s| blk: {
            const trimmed = std.mem.trim(u8, s, " \t\n\r");
            if (trimmed.len == 0) break :blk 0;
            const f = std.fmt.parseFloat(f64, trimmed) catch break :blk null;
            if (!std.math.isFinite(f) or f < 0 or f > 9007199254740991.0) break :blk null;
            break :blk @intFromFloat(@trunc(f));
        },
        else => null,
    };
}

fn valueToF64(value: Types.Value) ?f64 {
    return switch (value) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .boolean => |b| if (b) 1.0 else 0.0,
        .null => 0.0,
        .void => std.math.nan(f64),
        .string => |s| blk: {
            const trimmed = std.mem.trim(u8, s, " \t\n\r");
            if (trimmed.len == 0) break :blk 0.0;
            break :blk std.fmt.parseFloat(f64, trimmed) catch std.math.nan(f64);
        },
        else => null,
    };
}

fn f64ToU8(f: f64) u8 {
    if (!std.math.isFinite(f)) return 0;
    return @intFromFloat(@mod(f, 256.0));
}
fn f64ToI8(f: f64) i8 {
    return @bitCast(f64ToU8(f));
}
fn f64ToU16(f: f64) u16 {
    if (!std.math.isFinite(f)) return 0;
    return @intFromFloat(@mod(f, 65536.0));
}
fn f64ToI16(f: f64) i16 {
    return @bitCast(f64ToU16(f));
}
fn f64ToU32(f: f64) u32 {
    if (!std.math.isFinite(f)) return 0;
    return @intFromFloat(@mod(f, 4294967296.0));
}
fn f64ToI32(f: f64) i32 {
    return @bitCast(f64ToU32(f));
}

fn f64ToU8Clamped(f: f64) u8 {
    if (std.math.isNan(f) or f <= 0) return 0;
    if (f >= 255) return 255;
    const floor = @floor(f);
    const frac = f - floor;
    if (frac > 0.5) return @intFromFloat(floor + 1);
    if (frac < 0.5) return @intFromFloat(floor);
    return if (@mod(floor, 2.0) == 0) @intFromFloat(floor) else @intFromFloat(floor + 1);
}

fn f64ToF32(f: f64) f64 {
    return @floatCast(@as(f32, @floatCast(f)));
}

fn bigIntToU64(big: *Ast.BigIntValue, env: *Environment) ?u64 {
    if (big.toI64()) |i| return @bitCast(i);
    const digits = big.toString(env.allocator) catch return null;
    defer env.allocator.free(digits);
    return std.fmt.parseInt(u64, digits, 10) catch null;
}

fn bigIntToI64(big: *Ast.BigIntValue) ?i64 {
    return big.toI64();
}

fn integerToBigInt(env: *Environment, value: u64) Types.Value {
    var buf: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return .{ .void = {} };
    const bi = Ast.BigIntValue.fromString(env.allocator, digits) catch return .{ .void = {} };
    env.bigints.append(env.allocator, bi) catch {};
    return .{ .big_int = bi };
}

fn signedToBigInt(env: *Environment, value: i64) Types.Value {
    var buf: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return .{ .void = {} };
    const bi = Ast.BigIntValue.fromString(env.allocator, digits) catch return .{ .void = {} };
    env.bigints.append(env.allocator, bi) catch {};
    return .{ .big_int = bi };
}

fn readU16(bytes: []u8, off: usize, little: bool) u16 {
    const p: *const [2]u8 = @ptrCast(bytes[off..].ptr);
    return std.mem.readInt(u16, p, if (little) .little else .big);
}
fn readU32(bytes: []u8, off: usize, little: bool) u32 {
    const p: *const [4]u8 = @ptrCast(bytes[off..].ptr);
    return std.mem.readInt(u32, p, if (little) .little else .big);
}
fn readU64(bytes: []u8, off: usize, little: bool) u64 {
    const p: *const [8]u8 = @ptrCast(bytes[off..].ptr);
    return std.mem.readInt(u64, p, if (little) .little else .big);
}
fn writeU16(bytes: []u8, off: usize, value: u16, little: bool) void {
    const p: *[2]u8 = @ptrCast(bytes[off..].ptr);
    std.mem.writeInt(u16, p, value, if (little) .little else .big);
}
fn writeU32(bytes: []u8, off: usize, value: u32, little: bool) void {
    const p: *[4]u8 = @ptrCast(bytes[off..].ptr);
    std.mem.writeInt(u32, p, value, if (little) .little else .big);
}
fn writeU64(bytes: []u8, off: usize, value: u64, little: bool) void {
    const p: *[8]u8 = @ptrCast(bytes[off..].ptr);
    std.mem.writeInt(u64, p, value, if (little) .little else .big);
}

pub fn getElement(value: Types.Value, index: usize, env: *Environment) Types.Value {
    if (!isTypedArray(value)) return .{ .void = {} };
    const len = getLength(value);
    if (index >= len) return .{ .void = {} };
    const kind = getKind(value) orelse return .{ .void = {} };
    const bytes = bytesOfView(value) orelse return .{ .void = {} };
    const off = getOffset(value) + index * kindInfo(kind).bpe;
    return switch (kind) {
        .int8 => .{ .integer = @as(i8, @bitCast(bytes[off])) },
        .uint8 => .{ .integer = bytes[off] },
        .uint8clamped => .{ .integer = bytes[off] },
        .int16 => .{ .integer = @as(i16, @bitCast(readU16(bytes, off, true))) },
        .uint16 => .{ .integer = readU16(bytes, off, true) },
        .int32 => .{ .integer = @as(i32, @bitCast(readU32(bytes, off, true))) },
        .uint32 => .{ .integer = readU32(bytes, off, true) },
        .float32 => .{ .float = @as(f64, @as(f32, @bitCast(readU32(bytes, off, true)))) },
        .float64 => .{ .float = @as(f64, @bitCast(readU64(bytes, off, true))) },
        .bigint64 => signedToBigInt(env, @as(i64, @bitCast(readU64(bytes, off, true)))),
        .biguint64 => integerToBigInt(env, readU64(bytes, off, true)),
    };
}

pub fn writeElement(value: Types.Value, index: usize, new_value: Types.Value, env: *Environment) !void {
    if (!isTypedArray(value)) return error.InvalidReceiver;
    const len = getLength(value);
    if (index >= len) return;
    const kind = getKind(value) orelse return error.InvalidReceiver;
    const bytes = bytesOfView(value) orelse return error.InvalidReceiver;
    const off = getOffset(value) + index * kindInfo(kind).bpe;

    switch (kind) {
        .bigint64, .biguint64 => {
            if (new_value != .big_int) {
                _ = throwError(env, "TypeError", .{ .string = "Cannot convert a non-BigInt value to a BigInt" });
                return error.Thrown;
            }
            const u = bigIntToU64(new_value.big_int, env) orelse {
                _ = throwError(env, "TypeError", .{ .string = "BigInt value is out of range" });
                return error.Thrown;
            };
            writeU64(bytes, off, u, true);
        },
        else => {
            if (new_value == .big_int) {
                _ = throwError(env, "TypeError", .{ .string = "Cannot convert a BigInt value to a number" });
                return error.Thrown;
            }
            const f = valueToF64(new_value) orelse 0.0;
            switch (kind) {
                .int8 => bytes[off] = @bitCast(f64ToI8(f)),
                .uint8 => bytes[off] = f64ToU8(f),
                .uint8clamped => bytes[off] = f64ToU8Clamped(f),
                .int16 => writeU16(bytes, off, @bitCast(f64ToI16(f)), true),
                .uint16 => writeU16(bytes, off, f64ToU16(f), true),
                .int32 => writeU32(bytes, off, @bitCast(f64ToI32(f)), true),
                .uint32 => writeU32(bytes, off, f64ToU32(f), true),
                .float32 => writeU32(bytes, off, @bitCast(@as(f32, @floatCast(f))), true),
                .float64 => writeU64(bytes, off, @bitCast(f), true),
                .bigint64, .biguint64 => unreachable,
            }
        },
    }
}

fn constructFromValues(kind: Kind, values: []const Types.Value, env: *Environment) !Types.Value {
    const info = kindInfo(kind);
    const len = values.len;
    if (len > std.math.maxInt(usize) / info.bpe) return error.InvalidLength;
    const buffer_obj = try allocateBuffer(env, len * info.bpe, false);
    const view = try createView(env, kind, .{ .js_object = buffer_obj }, 0, len);
    for (values, 0..) |item, i| {
        writeElement(view, i, item, env) catch |err| return err;
    }
    return view;
}

fn sourceValues(source: Types.Value, env: *Environment) !std.ArrayList(Types.Value) {
    var values = std.ArrayList(Types.Value).empty;
    errdefer values.deinit(env.allocator);

    if (source == .array) {
        try values.appendSlice(env.allocator, source.array.elements.items);
        return values;
    }
    if (isTypedArray(source)) {
        const len = getLength(source);
        try values.ensureTotalCapacity(env.allocator, len);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            values.appendAssumeCapacity(getElement(source, i, env));
        }
        return values;
    }
    if (source == .js_object) {
        const length_val = source.js_object.properties.get("length") orelse return values;
        const len = toIndex(length_val) orelse return values;
        try values.ensureTotalCapacity(env.allocator, len);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            var buf: [32]u8 = undefined;
            const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return values;
            const item: Types.Value = source.js_object.properties.get(key) orelse .{ .void = {} };
            values.appendAssumeCapacity(item);
        }
    }
    return values;
}

fn constructTypedArray(kind: Kind, args: []const Types.Value, env: *Environment) Types.BuiltinResult {
    const info = kindInfo(kind);
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };

    if (args.len == 0) {
        const view = constructFromValues(kind, &.{}, env) catch return fail;
        return .{ .value = view };
    }

    const source = args[0];
    if (isArrayBuffer(source)) {
        const bytes = getBytesFromBuffer(source) orelse return fail;
        const offset = if (args.len > 1) (toIndex(args[1]) orelse {
            _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
            return fail;
        }) else 0;
        if (offset > bytes.len or offset % info.bpe != 0) {
            _ = throwError(env, "RangeError", .{ .string = "start offset is outside the bounds of the buffer" });
            return fail;
        }
        const max_len = (bytes.len - offset) / info.bpe;
        const length = if (args.len > 2 and args[2] != .void) (toIndex(args[2]) orelse {
            _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
            return fail;
        }) else max_len;
        if (length > max_len) {
            _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
            return fail;
        }
        const view = createView(env, kind, source, offset, length) catch {
            _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
            return fail;
        };
        return .{ .value = view };
    }

    if (isTypedArray(source)) {
        var values = sourceValues(source, env) catch return fail;
        defer values.deinit(env.allocator);
        const view = constructFromValues(kind, values.items, env) catch return fail;
        return .{ .value = view };
    }

    if (source == .array) {
        const view = constructFromValues(kind, source.array.elements.items, env) catch return fail;
        return .{ .value = view };
    }

    if (source == .js_object) {
        var values = sourceValues(source, env) catch return fail;
        defer values.deinit(env.allocator);
        if (values.items.len == 0 and source.js_object.properties.get("length") == null) {
            const len = toIndex(source) orelse 0;
            if (len == 0) {
                const view = constructFromValues(kind, &.{}, env) catch return fail;
                return .{ .value = view };
            }
            if (len > std.math.maxInt(usize) / info.bpe) {
                _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
                return fail;
            }
            const buffer_obj = allocateBuffer(env, len * info.bpe, false) catch return fail;
            const view = createView(env, kind, .{ .js_object = buffer_obj }, 0, len) catch return fail;
            return .{ .value = view };
        }
        const view = constructFromValues(kind, values.items, env) catch return fail;
        return .{ .value = view };
    }

    const len = toIndex(source) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
        return fail;
    };
    if (len > std.math.maxInt(usize) / info.bpe) {
        _ = throwError(env, "RangeError", .{ .string = "Invalid typed array length" });
        return fail;
    }
    const buffer_obj = allocateBuffer(env, len * info.bpe, false) catch return fail;
    const view = createView(env, kind, .{ .js_object = buffer_obj }, 0, len) catch return fail;
    return .{ .value = view };
}

pub fn ArrayBufferConstructor(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    const len = if (args.len == 0) 0 else (toIndex(args[0]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Invalid array buffer length" });
        return fail;
    });
    const obj = allocateBuffer(env, len, false) catch return fail;
    return .{ .value = .{ .js_object = obj } };
}

pub fn SharedArrayBufferConstructor(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    const len = if (args.len == 0) 0 else (toIndex(args[0]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Invalid array buffer length" });
        return fail;
    });
    const obj = allocateBuffer(env, len, true) catch return fail;
    return .{ .value = .{ .js_object = obj } };
}

pub fn DataViewConstructor(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len == 0 or !isArrayBuffer(args[0])) {
        _ = throwError(env, "TypeError", .{ .string = "First argument to DataView constructor must be an ArrayBuffer" });
        return fail;
    }
    const bytes = getBytesFromBuffer(args[0]) orelse return fail;
    const offset = if (args.len > 1) (toIndex(args[1]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Invalid byte offset" });
        return fail;
    }) else 0;
    if (offset > bytes.len) {
        _ = throwError(env, "RangeError", .{ .string = "Invalid byte offset" });
        return fail;
    }
    const length = if (args.len > 2 and args[2] != .void) (toIndex(args[2]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Invalid byte length" });
        return fail;
    }) else bytes.len - offset;
    if (length > bytes.len - offset) {
        _ = throwError(env, "RangeError", .{ .string = "Invalid byte length" });
        return fail;
    }
    const view = createDataView(env, args[0], offset, length) catch return fail;
    return .{ .value = view };
}

fn makeTypedConstructor(comptime kind: Kind) Types.BuiltinFn {
    return struct {
        fn ctor(args: []Types.Value, env: *Environment) Types.BuiltinResult {
            return constructTypedArray(kind, args, env);
        }
    }.ctor;
}

fn makeFrom(comptime kind: Kind) Types.BuiltinFn {
    return struct {
        fn from(args: []Types.Value, env: *Environment) Types.BuiltinResult {
            const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
            if (args.len == 0) {
                const view = constructFromValues(kind, &.{}, env) catch return fail;
                return .{ .value = view };
            }
            var values = sourceValues(args[0], env) catch return fail;
            defer values.deinit(env.allocator);

            if (args.len > 1 and args[1] != .void) {
                var i: usize = 0;
                while (i < values.items.len) : (i += 1) {
                    var cb_args = [_]Types.Value{ values.items[i], .{ .integer = @intCast(i) } };
                    const mapped = callFunctionValue(args[1], cb_args[0..], env, null) catch {
                        return fail;
                    };
                    if (env.throw_hit) return fail;
                    values.items[i] = mapped;
                }
            }
            const view = constructFromValues(kind, values.items, env) catch return fail;
            return .{ .value = view };
        }
    }.from;
}

fn makeOf(comptime kind: Kind) Types.BuiltinFn {
    return struct {
        fn of(args: []Types.Value, env: *Environment) Types.BuiltinResult {
            const view = constructFromValues(kind, args, env) catch return .{ .value = .{ .void = {} } };
            return .{ .value = view };
        }
    }.of;
}

fn makeConstructorObject(comptime kind: Kind) Types.BuiltinObjectImpl {
    const info = kindInfo(kind);
    return .{
        .name = info.name,
        .methods = &[_]Types.BuiltinMethod{
            .{ .name = "from", .func = makeFrom(kind) },
            .{ .name = "of", .func = makeOf(kind) },
        },
        .properties = &[_]Types.BuiltinProperty{
            .{ .name = "BYTES_PER_ELEMENT", .value = .{ .integer = @intCast(info.bpe) } },
            .{ .name = "name", .value = .{ .string = info.name } },
        },
    };
}

fn arrayBufferIsView(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    _ = env;
    const result = args.len > 0 and (isTypedArray(args[0]) or isDataView(args[0]));
    return .{ .value = .{ .boolean = result } };
}

pub const ARRAYBUFFER_OBJECT = Types.BuiltinObjectImpl{
    .name = "ArrayBuffer",
    .methods = &[_]Types.BuiltinMethod{
        .{ .name = "isView", .func = arrayBufferIsView },
    },
    .properties = &[_]Types.BuiltinProperty{
        .{ .name = "name", .value = .{ .string = "ArrayBuffer" } },
    },
};

pub const SHARED_ARRAYBUFFER_OBJECT = Types.BuiltinObjectImpl{
    .name = "SharedArrayBuffer",
    .methods = &[_]Types.BuiltinMethod{},
    .properties = &[_]Types.BuiltinProperty{
        .{ .name = "name", .value = .{ .string = "SharedArrayBuffer" } },
    },
};

pub const DATAVIEW_OBJECT = Types.BuiltinObjectImpl{
    .name = "DataView",
    .methods = &[_]Types.BuiltinMethod{},
    .properties = &[_]Types.BuiltinProperty{
        .{ .name = "name", .value = .{ .string = "DataView" } },
    },
};

pub const INT8ARRAY_OBJECT = makeConstructorObject(.int8);
pub const UINT8ARRAY_OBJECT = makeConstructorObject(.uint8);
pub const UINT8CLAMPEDARRAY_OBJECT = makeConstructorObject(.uint8clamped);
pub const INT16ARRAY_OBJECT = makeConstructorObject(.int16);
pub const UINT16ARRAY_OBJECT = makeConstructorObject(.uint16);
pub const INT32ARRAY_OBJECT = makeConstructorObject(.int32);
pub const UINT32ARRAY_OBJECT = makeConstructorObject(.uint32);
pub const FLOAT32ARRAY_OBJECT = makeConstructorObject(.float32);
pub const FLOAT64ARRAY_OBJECT = makeConstructorObject(.float64);
pub const BIGINT64ARRAY_OBJECT = makeConstructorObject(.bigint64);
pub const BIGUINT64ARRAY_OBJECT = makeConstructorObject(.biguint64);

pub const Int8ArrayConstructor = makeTypedConstructor(.int8);
pub const Uint8ArrayConstructor = makeTypedConstructor(.uint8);
pub const Uint8ClampedArrayConstructor = makeTypedConstructor(.uint8clamped);
pub const Int16ArrayConstructor = makeTypedConstructor(.int16);
pub const Uint16ArrayConstructor = makeTypedConstructor(.uint16);
pub const Int32ArrayConstructor = makeTypedConstructor(.int32);
pub const Uint32ArrayConstructor = makeTypedConstructor(.uint32);
pub const Float32ArrayConstructor = makeTypedConstructor(.float32);
pub const Float64ArrayConstructor = makeTypedConstructor(.float64);
pub const BigInt64ArrayConstructor = makeTypedConstructor(.bigint64);
pub const BigUint64ArrayConstructor = makeTypedConstructor(.biguint64);

fn truthy(value: Types.Value) bool {
    return switch (value) {
        .boolean => |b| b,
        .integer => |i| i != 0,
        .float => |f| f != 0 and !std.math.isNan(f),
        .string => |s| s.len != 0,
        .void, .null => false,
        else => true,
    };
}

fn strictEqual(a: Types.Value, b: Types.Value) bool {
    if (a == .integer and b == .float) return @as(f64, @floatFromInt(a.integer)) == b.float;
    if (a == .float and b == .integer) return a.float == @as(f64, @floatFromInt(b.integer));
    if (@backingInt(a) != @backingInt(b)) return false;
    return switch (a) {
        .integer => |i| i == b.integer,
        .float => |f| f == b.float,
        .string => |s| std.mem.eql(u8, s, b.string),
        .boolean => |v| v == b.boolean,
        .void, .null => true,
        .big_int => |x| Ast.BigIntValue.compare(x, b.big_int) == .eq,
        else => false,
    };
}

fn sameValueZero(a: Types.Value, b: Types.Value) bool {
    if (a == .float and std.math.isNan(a.float) and b == .float and std.math.isNan(b.float)) return true;
    return strictEqual(a, b);
}

fn normalizeIndex(value: Types.Value, len: usize, default: usize) usize {
    if (value == .void) return default;
    const raw: i64 = switch (value) {
        .integer => |i| i,
        .float => |f| if (std.math.isNan(f)) 0 else @intFromFloat(@trunc(f)),
        else => 0,
    };
    if (raw < 0) {
        const adjusted = @as(i64, @intCast(len)) + raw;
        return if (adjusted < 0) 0 else @intCast(adjusted);
    }
    const u: usize = @intCast(raw);
    return @min(u, len);
}

fn appendValueText(env: *Environment, buf: *std.ArrayList(u8), value: Types.Value) !void {
    switch (value) {
        .string => |s| try buf.appendSlice(env.allocator, s),
        .integer => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
            try buf.appendSlice(env.allocator, s);
        },
        .float => |f| {
            if (std.math.isNan(f)) {
                try buf.appendSlice(env.allocator, "NaN");
            } else if (std.math.isPositiveInf(f)) {
                try buf.appendSlice(env.allocator, "Infinity");
            } else if (std.math.isNegativeInf(f)) {
                try buf.appendSlice(env.allocator, "-Infinity");
            } else {
                numberFormat.appendFloat(env.allocator, buf, f);
            }
        },
        .big_int => |b| {
            const digits = try b.toString(env.allocator);
            defer env.allocator.free(digits);
            try buf.appendSlice(env.allocator, digits);
        },
        .boolean => |b| try buf.appendSlice(env.allocator, if (b) "true" else "false"),
        .null, .void => {},
        else => try buf.appendSlice(env.allocator, "[object]"),
    }
}

fn callCallback(cb: Types.Value, args: []Types.Value, this_arg: ?Types.Value, env: *Environment) !Types.Value {
    const result = try callFunctionValue(cb, args, env, this_arg);
    if (env.throw_hit) return error.Thrown;
    return result;
}

fn methodSet(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 1 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const source: Types.Value = if (args.len > 1) args[1] else .{ .void = {} };
    var offset: usize = 0;
    if (args.len > 2 and args[2] != .void) offset = toIndex(args[2]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "offset is out of bounds" });
        return fail;
    };
    var values = sourceValues(source, env) catch {
        _ = throwError(env, "TypeError", .{ .string = "argument must be an array-like object" });
        return fail;
    };
    defer values.deinit(env.allocator);
    if (offset > getLength(target) or values.items.len > getLength(target) - offset) {
        _ = throwError(env, "RangeError", .{ .string = "offset is out of bounds" });
        return fail;
    }
    for (values.items, 0..) |item, i| {
        writeElement(target, offset + i, item, env) catch return fail;
    }
    return .{ .value = .{ .void = {} } };
}

fn methodSubarray(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 1 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    const begin = if (args.len > 1) normalizeIndex(args[1], len, 0) else 0;
    const end = if (args.len > 2) normalizeIndex(args[2], len, len) else len;
    const count = if (end > begin) end - begin else 0;
    const kind = getKind(target) orelse return fail;
    const buffer = viewBuffer(target) orelse return fail;
    const offset = getOffset(target) + begin * kindInfo(kind).bpe;
    const view = createView(env, kind, buffer, offset, count) catch return fail;
    return .{ .value = view };
}

fn methodSlice(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 1 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    const begin = if (args.len > 1) normalizeIndex(args[1], len, 0) else 0;
    const end = if (args.len > 2) normalizeIndex(args[2], len, len) else len;
    const count = if (end > begin) end - begin else 0;
    var values = std.ArrayList(Types.Value).initCapacity(env.allocator, count) catch return fail;
    defer values.deinit(env.allocator);
    var i: usize = 0;
    while (i < count) : (i += 1) values.appendAssumeCapacity(getElement(target, begin + i, env));
    const view = constructFromValues(getKind(target) orelse return fail, values.items, env) catch return fail;
    return .{ .value = view };
}

fn methodFill(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    const begin = if (args.len > 2) normalizeIndex(args[2], len, 0) else 0;
    const end = if (args.len > 3) normalizeIndex(args[3], len, len) else len;
    var i = begin;
    while (i < end) : (i += 1) writeElement(target, i, args[1], env) catch return fail;
    return .{ .value = target };
}

fn methodCopyWithin(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    const to = normalizeIndex(args[1], len, 0);
    const from = if (args.len > 2) normalizeIndex(args[2], len, 0) else 0;
    const final = if (args.len > 3) normalizeIndex(args[3], len, len) else len;
    const count = if (final > from) @min(final - from, len - to) else 0;
    if (count == 0) return .{ .value = target };
    var values = std.ArrayList(Types.Value).initCapacity(env.allocator, count) catch return fail;
    defer values.deinit(env.allocator);
    var i: usize = 0;
    while (i < count) : (i += 1) values.appendAssumeCapacity(getElement(target, from + i, env));
    for (values.items, 0..) |item, j| writeElement(target, to + j, item, env) catch return fail;
    return .{ .value = target };
}

fn methodMap(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    var values = std.ArrayList(Types.Value).initCapacity(env.allocator, len) catch return fail;
    defer values.deinit(env.allocator);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        var cb_args = [_]Types.Value{ getElement(target, i, env), .{ .integer = @intCast(i) }, target };
        const mapped = callCallback(args[1], cb_args[0..], if (args.len > 2) args[2] else null, env) catch return fail;
        values.appendAssumeCapacity(mapped);
    }
    const view = constructFromValues(getKind(target) orelse return fail, values.items, env) catch return fail;
    return .{ .value = view };
}

fn methodFilter(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    var values = std.ArrayList(Types.Value).empty;
    defer values.deinit(env.allocator);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const item = getElement(target, i, env);
        var cb_args = [_]Types.Value{ item, .{ .integer = @intCast(i) }, target };
        const keep = callCallback(args[1], cb_args[0..], if (args.len > 2) args[2] else null, env) catch return fail;
        if (truthy(keep)) values.append(env.allocator, item) catch return fail;
    }
    const view = constructFromValues(getKind(target) orelse return fail, values.items, env) catch return fail;
    return .{ .value = view };
}

fn methodReduce(args: []Types.Value, env: *Environment, right: bool) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    if (len == 0 and args.len < 3) {
        _ = throwError(env, "TypeError", .{ .string = "Reduce of empty array with no initial value" });
        return fail;
    }
    var acc: Types.Value = undefined;
    var start: usize = 0;
    if (args.len > 2) {
        acc = args[2];
    } else if (right) {
        acc = getElement(target, len - 1, env);
        start = 1;
    } else {
        acc = getElement(target, 0, env);
        start = 1;
    }
    var step: usize = start;
    while (step < len) : (step += 1) {
        const idx = if (right) len - 1 - step else step;
        var cb_args = [_]Types.Value{ acc, getElement(target, idx, env), .{ .integer = @intCast(idx) }, target };
        acc = callCallback(args[1], cb_args[0..], null, env) catch return fail;
    }
    return .{ .value = acc };
}

fn methodForEach(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        var cb_args = [_]Types.Value{ getElement(target, i, env), .{ .integer = @intCast(i) }, target };
        _ = callCallback(args[1], cb_args[0..], if (args.len > 2) args[2] else null, env) catch return fail;
    }
    return .{ .value = .{ .void = {} } };
}

fn methodPredicate(args: []Types.Value, env: *Environment, mode: enum { find, find_index, some, every }) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const item = getElement(target, i, env);
        var cb_args = [_]Types.Value{ item, .{ .integer = @intCast(i) }, target };
        const result = callCallback(args[1], cb_args[0..], if (args.len > 2) args[2] else null, env) catch return fail;
        const yes = truthy(result);
        switch (mode) {
            .find => if (yes) return .{ .value = item },
            .find_index => if (yes) return .{ .value = .{ .integer = @intCast(i) } },
            .some => if (yes) return .{ .value = .{ .boolean = true } },
            .every => if (!yes) return .{ .value = .{ .boolean = false } },
        }
    }
    return switch (mode) {
        .find => .{ .value = .{ .void = {} } },
        .find_index => .{ .value = .{ .integer = -1 } },
        .some => .{ .value = .{ .boolean = false } },
        .every => .{ .value = .{ .boolean = true } },
    };
}

fn methodIncludes(args: []Types.Value, env: *Environment, index_of: bool) Types.BuiltinResult {
    if (args.len < 2 or !isTypedArray(args[0])) return .{ .value = .{ .boolean = false } };
    const target = args[0];
    const len = getLength(target);
    var start: usize = 0;
    if (args.len > 2) {
        const raw: i64 = switch (args[2]) {
            .integer => |i| i,
            .float => |f| if (std.math.isNan(f)) 0 else @intFromFloat(@trunc(f)),
            else => 0,
        };
        if (raw < 0) {
            const adjusted = @as(i64, @intCast(len)) + raw;
            if (adjusted < 0) return .{ .value = if (index_of) .{ .integer = -1 } else .{ .boolean = false } };
            start = @intCast(adjusted);
        } else {
            start = @min(@as(usize, @intCast(raw)), len);
        }
    }
    var i = start;
    while (i < len) : (i += 1) {
        const item = getElement(target, i, env);
        const found = if (index_of) strictEqual(item, args[1]) else sameValueZero(item, args[1]);
        if (found) return .{ .value = if (index_of) .{ .integer = @intCast(i) } else .{ .boolean = true } };
    }
    return .{ .value = if (index_of) .{ .integer = -1 } else .{ .boolean = false } };
}

fn methodJoin(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    if (args.len < 1 or !isTypedArray(args[0])) return .{ .value = .{ .void = {} } };
    const target = args[0];
    const len = getLength(target);
    const sep: []const u8 = if (args.len > 1 and args[1] == .string) args[1].string else ",";
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(env.allocator);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (i > 0) buf.appendSlice(env.allocator, sep) catch return .{ .value = .{ .void = {} } };
        appendValueText(env, &buf, getElement(target, i, env)) catch return .{ .value = .{ .void = {} } };
    }
    const owned = buf.toOwnedSlice(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.owned_strings.append(env.allocator, owned) catch {};
    return .{ .value = .{ .string = owned } };
}

fn methodReverse(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    if (args.len < 1 or !isTypedArray(args[0])) return .{ .value = .{ .void = {} } };
    const target = args[0];
    const len = getLength(target);
    var i: usize = 0;
    while (i < len / 2) : (i += 1) {
        const a = getElement(target, i, env);
        const b = getElement(target, len - 1 - i, env);
        writeElement(target, i, b, env) catch return .{ .value = .{ .void = {} } };
        writeElement(target, len - 1 - i, a, env) catch return .{ .value = .{ .void = {} } };
    }
    return .{ .value = target };
}

fn compareNumbers(a: Types.Value, b: Types.Value) i8 {
    if (a == .big_int and b == .big_int) {
        return switch (Ast.BigIntValue.compare(a.big_int, b.big_int)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }
    const af = valueToF64(a) orelse 0;
    const bf = valueToF64(b) orelse 0;
    if (std.math.isNan(af) and std.math.isNan(bf)) return 0;
    if (std.math.isNan(af)) return 1;
    if (std.math.isNan(bf)) return -1;
    if (af < bf) return -1;
    if (af > bf) return 1;
    return 0;
}

fn methodSort(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 1 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    var values = std.ArrayList(Types.Value).initCapacity(env.allocator, len) catch return fail;
    defer values.deinit(env.allocator);
    var i: usize = 0;
    while (i < len) : (i += 1) values.appendAssumeCapacity(getElement(target, i, env));

    var j: usize = 1;
    while (j < len) : (j += 1) {
        var k = j;
        while (k > 0) {
            const order: i8 = if (args.len > 1 and args[1] != .void) blk: {
                var cb_args = [_]Types.Value{ values.items[k - 1], values.items[k] };
                const res = callCallback(args[1], cb_args[0..], null, env) catch return fail;
                const f = valueToF64(res) orelse 0;
                if (f > 0) break :blk 1;
                if (f < 0) break :blk -1;
                break :blk 0;
            } else compareNumbers(values.items[k - 1], values.items[k]);
            if (order <= 0) break;
            const tmp = values.items[k - 1];
            values.items[k - 1] = values.items[k];
            values.items[k] = tmp;
            k -= 1;
        }
    }
    for (values.items, 0..) |item, idx| writeElement(target, idx, item, env) catch return fail;
    return .{ .value = target };
}

fn methodAt(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    if (args.len < 2 or !isTypedArray(args[0])) return .{ .value = .{ .void = {} } };
    const len = getLength(args[0]);
    const raw: i64 = switch (args[1]) {
        .integer => |i| i,
        .float => |f| if (std.math.isNan(f)) 0 else @intFromFloat(@trunc(f)),
        else => 0,
    };
    const idx: i64 = if (raw < 0) @as(i64, @intCast(len)) + raw else raw;
    if (idx < 0 or idx >= @as(i64, @intCast(len))) return .{ .value = .{ .void = {} } };
    return .{ .value = getElement(args[0], @intCast(idx), env) };
}

fn snapshotIterator(args: []Types.Value, env: *Environment, mode: enum { keys, values, entries }) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 1 or !isTypedArray(args[0])) return fail;
    const target = args[0];
    const len = getLength(target);
    const source = Ast.ArrayObject.init(env.allocator) catch return fail;
    env.arrays.append(env.allocator, source) catch {
        source.deinit();
        return fail;
    };
    var i: usize = 0;
    while (i < len) : (i += 1) {
        switch (mode) {
            .keys => source.elements.append(env.allocator, .{ .hole = {} }) catch return fail,
            .values => source.elements.append(env.allocator, getElement(target, i, env)) catch return fail,
            .entries => {
                const pair = Ast.ArrayObject.init(env.allocator) catch return fail;
                env.arrays.append(env.allocator, pair) catch {
                    pair.deinit();
                    return fail;
                };
                pair.elements.append(env.allocator, .{ .integer = @intCast(i) }) catch return fail;
                pair.elements.append(env.allocator, getElement(target, i, env)) catch return fail;
                source.elements.append(env.allocator, .{ .array = pair }) catch return fail;
            },
        }
    }
    const iter = switch (mode) {
        .keys => Ast.ArrayIterator.initKeys(env.allocator, source),
        .values => Ast.ArrayIterator.initValues(env.allocator, source),
        .entries => Ast.ArrayIterator.initValues(env.allocator, source),
    } catch return fail;
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return fail;
    };
    return .{ .value = .{ .iterator = iter } };
}

const MethodOp = enum {
    set,
    subarray,
    slice,
    fill,
    copy_within,
    map,
    filter,
    reduce,
    reduce_right,
    for_each,
    find,
    find_index,
    some,
    every,
    includes,
    index_of,
    join,
    reverse,
    sort,
    at,
    keys,
    values,
    entries,
    to_string,
};

fn typedMethod(comptime op: MethodOp, args: []Types.Value, env: *Environment) Types.BuiltinResult {
    return switch (op) {
        .set => methodSet(args, env),
        .subarray => methodSubarray(args, env),
        .slice => methodSlice(args, env),
        .fill => methodFill(args, env),
        .copy_within => methodCopyWithin(args, env),
        .map => methodMap(args, env),
        .filter => methodFilter(args, env),
        .reduce => methodReduce(args, env, false),
        .reduce_right => methodReduce(args, env, true),
        .for_each => methodForEach(args, env),
        .find => methodPredicate(args, env, .find),
        .find_index => methodPredicate(args, env, .find_index),
        .some => methodPredicate(args, env, .some),
        .every => methodPredicate(args, env, .every),
        .includes => methodIncludes(args, env, false),
        .index_of => methodIncludes(args, env, true),
        .join, .to_string => methodJoin(args, env),
        .reverse => methodReverse(args, env),
        .sort => methodSort(args, env),
        .at => methodAt(args, env),
        .keys => snapshotIterator(args, env, .keys),
        .values => snapshotIterator(args, env, .values),
        .entries => snapshotIterator(args, env, .entries),
    };
}

fn makeTypedMethod(comptime op: MethodOp) Types.BuiltinFn {
    return struct {
        fn method(args: []Types.Value, env: *Environment) Types.BuiltinResult {
            return typedMethod(op, args, env);
        }
    }.method;
}

pub const TYPED_ARRAY_METHODS_OBJECT = Types.BuiltinObjectImpl{
    .name = "TypedArray",
    .methods = &[_]Types.BuiltinMethod{
        .{ .name = "set", .func = makeTypedMethod(.set) },
        .{ .name = "subarray", .func = makeTypedMethod(.subarray) },
        .{ .name = "slice", .func = makeTypedMethod(.slice) },
        .{ .name = "fill", .func = makeTypedMethod(.fill) },
        .{ .name = "copyWithin", .func = makeTypedMethod(.copy_within) },
        .{ .name = "map", .func = makeTypedMethod(.map) },
        .{ .name = "filter", .func = makeTypedMethod(.filter) },
        .{ .name = "reduce", .func = makeTypedMethod(.reduce) },
        .{ .name = "reduceRight", .func = makeTypedMethod(.reduce_right) },
        .{ .name = "forEach", .func = makeTypedMethod(.for_each) },
        .{ .name = "find", .func = makeTypedMethod(.find) },
        .{ .name = "findIndex", .func = makeTypedMethod(.find_index) },
        .{ .name = "some", .func = makeTypedMethod(.some) },
        .{ .name = "every", .func = makeTypedMethod(.every) },
        .{ .name = "includes", .func = makeTypedMethod(.includes) },
        .{ .name = "indexOf", .func = makeTypedMethod(.index_of) },
        .{ .name = "join", .func = makeTypedMethod(.join) },
        .{ .name = "reverse", .func = makeTypedMethod(.reverse) },
        .{ .name = "sort", .func = makeTypedMethod(.sort) },
        .{ .name = "at", .func = makeTypedMethod(.at) },
        .{ .name = "keys", .func = makeTypedMethod(.keys) },
        .{ .name = "values", .func = makeTypedMethod(.values) },
        .{ .name = "entries", .func = makeTypedMethod(.entries) },
        .{ .name = "toString", .func = makeTypedMethod(.to_string) },
        .{ .name = "@@iterator", .func = makeTypedMethod(.values) },
    },
};

fn bufferSlice(args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 1 or !isArrayBuffer(args[0])) return fail;
    const bytes = getBytesFromBuffer(args[0]) orelse return fail;
    const begin = if (args.len > 1) normalizeIndex(args[1], bytes.len, 0) else 0;
    const end = if (args.len > 2) normalizeIndex(args[2], bytes.len, bytes.len) else bytes.len;
    const count = if (end > begin) end - begin else 0;
    const obj = allocateBuffer(env, count, false) catch return fail;
    const out = getBytesFromBuffer(.{ .js_object = obj }) orelse return fail;
    if (count > 0) @memcpy(out[0..count], bytes[begin..end]);
    return .{ .value = .{ .js_object = obj } };
}

pub const BUFFER_METHODS_OBJECT = Types.BuiltinObjectImpl{
    .name = "ArrayBufferPrototype",
    .methods = &[_]Types.BuiltinMethod{
        .{ .name = "slice", .func = bufferSlice },
    },
};

const DvType = enum { int8, uint8, int16, uint16, int32, uint32, float32, float64, bigint64, biguint64 };

fn dvWidth(t: DvType) usize {
    return switch (t) {
        .int8, .uint8 => 1,
        .int16, .uint16 => 2,
        .int32, .uint32, .float32 => 4,
        .float64, .bigint64, .biguint64 => 8,
    };
}

fn dvMethodName(t: DvType, set: bool) []const u8 {
    return switch (t) {
        .int8 => if (set) "setInt8" else "getInt8",
        .uint8 => if (set) "setUint8" else "getUint8",
        .int16 => if (set) "setInt16" else "getInt16",
        .uint16 => if (set) "setUint16" else "getUint16",
        .int32 => if (set) "setInt32" else "getInt32",
        .uint32 => if (set) "setUint32" else "getUint32",
        .float32 => if (set) "setFloat32" else "getFloat32",
        .float64 => if (set) "setFloat64" else "getFloat64",
        .bigint64 => if (set) "setBigInt64" else "getBigInt64",
        .biguint64 => if (set) "setBigUint64" else "getBigUint64",
    };
}

fn dvBytes(value: Types.Value) ?[]u8 {
    if (!isDataView(value)) return null;
    const buffer = value.js_object.properties.get(VIEW_BUFFER_KEY) orelse return null;
    return getBytesFromBuffer(buffer);
}

fn dvOffset(value: Types.Value) usize {
    const raw = value.js_object.properties.get(VIEW_OFFSET_KEY) orelse return 0;
    if (raw != .integer or raw.integer < 0) return 0;
    return @intCast(raw.integer);
}

fn dvLength(value: Types.Value) usize {
    const raw = value.js_object.properties.get(VIEW_LENGTH_KEY) orelse return 0;
    if (raw != .integer or raw.integer < 0) return 0;
    return @intCast(raw.integer);
}

fn dvCheck(value: Types.Value, index: usize, width: usize, env: *Environment) ?usize {
    if (!isDataView(value)) return null;
    if (index > dvLength(value) or width > dvLength(value) - index) {
        _ = throwError(env, "RangeError", .{ .string = "Offset is outside the bounds of the DataView" });
        return null;
    }
    return dvOffset(value) + index;
}

fn dataViewGet(comptime t: DvType, args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 2 or !isDataView(args[0])) {
        _ = throwError(env, "TypeError", .{ .string = "Method DataView.prototype.get called on incompatible receiver" });
        return fail;
    }
    const width = dvWidth(t);
    const index = toIndex(args[1]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Offset is outside the bounds of the DataView" });
        return fail;
    };
    const off = dvCheck(args[0], index, width, env) orelse return fail;
    const bytes = dvBytes(args[0]) orelse return fail;
    const little = args.len > 2 and truthy(args[2]);
    return switch (t) {
        .int8 => .{ .value = .{ .integer = @as(i8, @bitCast(bytes[off])) } },
        .uint8 => .{ .value = .{ .integer = bytes[off] } },
        .int16 => .{ .value = .{ .integer = @as(i16, @bitCast(readU16(bytes, off, little))) } },
        .uint16 => .{ .value = .{ .integer = readU16(bytes, off, little) } },
        .int32 => .{ .value = .{ .integer = @as(i32, @bitCast(readU32(bytes, off, little))) } },
        .uint32 => .{ .value = .{ .integer = readU32(bytes, off, little) } },
        .float32 => .{ .value = .{ .float = @as(f64, @as(f32, @bitCast(readU32(bytes, off, little)))) } },
        .float64 => .{ .value = .{ .float = @as(f64, @bitCast(readU64(bytes, off, little))) } },
        .bigint64 => .{ .value = signedToBigInt(env, @as(i64, @bitCast(readU64(bytes, off, little)))) },
        .biguint64 => .{ .value = integerToBigInt(env, readU64(bytes, off, little)) },
    };
}

fn dataViewSet(comptime t: DvType, args: []Types.Value, env: *Environment) Types.BuiltinResult {
    const fail: Types.BuiltinResult = .{ .value = .{ .void = {} } };
    if (args.len < 3 or !isDataView(args[0])) {
        _ = throwError(env, "TypeError", .{ .string = "Method DataView.prototype.set called on incompatible receiver" });
        return fail;
    }
    const width = dvWidth(t);
    const index = toIndex(args[1]) orelse {
        _ = throwError(env, "RangeError", .{ .string = "Offset is outside the bounds of the DataView" });
        return fail;
    };
    const off = dvCheck(args[0], index, width, env) orelse return fail;
    const bytes = dvBytes(args[0]) orelse return fail;
    const little = args.len > 3 and truthy(args[3]);
    switch (t) {
        .int8 => bytes[off] = @bitCast(f64ToI8(valueToF64(args[2]) orelse 0)),
        .uint8 => bytes[off] = f64ToU8(valueToF64(args[2]) orelse 0),
        .int16 => writeU16(bytes, off, @bitCast(f64ToI16(valueToF64(args[2]) orelse 0)), little),
        .uint16 => writeU16(bytes, off, f64ToU16(valueToF64(args[2]) orelse 0), little),
        .int32 => writeU32(bytes, off, @bitCast(f64ToI32(valueToF64(args[2]) orelse 0)), little),
        .uint32 => writeU32(bytes, off, f64ToU32(valueToF64(args[2]) orelse 0), little),
        .float32 => writeU32(bytes, off, @bitCast(@as(f32, @floatCast(valueToF64(args[2]) orelse 0))), little),
        .float64 => writeU64(bytes, off, @bitCast(valueToF64(args[2]) orelse 0), little),
        .bigint64, .biguint64 => {
            if (args[2] != .big_int) {
                _ = throwError(env, "TypeError", .{ .string = "Cannot convert a non-BigInt value to a BigInt" });
                return fail;
            }
            const u = bigIntToU64(args[2].big_int, env) orelse {
                _ = throwError(env, "RangeError", .{ .string = "BigInt value is out of range" });
                return fail;
            };
            writeU64(bytes, off, u, little);
        },
    }
    return .{ .value = .{ .void = {} } };
}

fn makeDvMethod(comptime t: DvType, comptime set: bool) Types.BuiltinFn {
    return struct {
        fn method(args: []Types.Value, env: *Environment) Types.BuiltinResult {
            return if (set) dataViewSet(t, args, env) else dataViewGet(t, args, env);
        }
    }.method;
}

fn makeDataViewMethods() [20]Types.BuiltinMethod {
    var methods: [20]Types.BuiltinMethod = undefined;
    var i: usize = 0;
    const enum_info = @typeInfo(DvType).@"enum";
    inline for (enum_info.field_values) |value| {
        const t: DvType = @fromBackingInt(@intCast(value));
        methods[i] = .{ .name = dvMethodName(t, false), .func = makeDvMethod(t, false) };
        i += 1;
    }
    inline for (enum_info.field_values) |value| {
        const t: DvType = @fromBackingInt(@intCast(value));
        methods[i] = .{ .name = dvMethodName(t, true), .func = makeDvMethod(t, true) };
        i += 1;
    }
    return methods;
}

const DATAVIEW_METHODS = makeDataViewMethods();

pub const DATAVIEW_METHODS_OBJECT = Types.BuiltinObjectImpl{
    .name = "DataViewPrototype",
    .methods = &DATAVIEW_METHODS,
};

pub fn hasProperty(value: Types.Value, property: []const u8) bool {
    if (isArrayBuffer(value)) {
        if (std.mem.eql(u8, property, "byteLength")) return true;
        return BUFFER_METHODS_OBJECT.getMethod(property) != null or value.js_object.properties.contains(property);
    }
    if (isDataView(value)) {
        if (std.mem.eql(u8, property, "byteLength") or std.mem.eql(u8, property, "byteOffset") or std.mem.eql(u8, property, "buffer")) return true;
        return DATAVIEW_METHODS_OBJECT.getMethod(property) != null or value.js_object.properties.contains(property);
    }
    if (!isTypedArray(value)) return false;
    if (std.mem.eql(u8, property, "length") or std.mem.eql(u8, property, "byteLength") or
        std.mem.eql(u8, property, "byteOffset") or std.mem.eql(u8, property, "buffer") or
        std.mem.eql(u8, property, "BYTES_PER_ELEMENT") or std.mem.eql(u8, property, "@@iterator")) return true;
    if (TYPED_ARRAY_METHODS_OBJECT.getMethod(property) != null) return true;
    if (indexFromKey(property)) |idx| return idx < getLength(value);
    return value.js_object.properties.contains(property);
}

pub fn appendForInKeys(value: Types.Value, env: *Environment, keys_arr: *Ast.ArrayObject) void {
    if (!isTypedArray(value)) return;
    const len = getLength(value);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        var buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
        const owned = env.allocator.dupe(u8, key) catch break;
        env.owned_strings.append(env.allocator, owned) catch {};
        keys_arr.elements.append(keys_arr.allocator, .{ .string = owned }) catch {};
    }
}

pub fn getMember(value: Types.Value, property: []const u8) Types.Value {
    if (isArrayBuffer(value)) {
        const bytes = getBytesFromBuffer(value) orelse return .{ .void = {} };
        if (std.mem.eql(u8, property, "byteLength")) return .{ .integer = @intCast(bytes.len) };
        if (BUFFER_METHODS_OBJECT.getMethod(property) != null) return .{ .object = @ptrCast(&BUFFER_METHODS_OBJECT) };
        return value.js_object.properties.get(property) orelse .{ .void = {} };
    }
    if (isDataView(value)) {
        if (std.mem.eql(u8, property, "byteLength")) return .{ .integer = @intCast(dvLength(value)) };
        if (std.mem.eql(u8, property, "byteOffset")) return .{ .integer = @intCast(dvOffset(value)) };
        if (std.mem.eql(u8, property, "buffer")) return value.js_object.properties.get(VIEW_BUFFER_KEY) orelse .{ .void = {} };
        if (DATAVIEW_METHODS_OBJECT.getMethod(property) != null) return .{ .object = @ptrCast(&DATAVIEW_METHODS_OBJECT) };
        return value.js_object.properties.get(property) orelse .{ .void = {} };
    }
    if (!isTypedArray(value)) return .{ .void = {} };
    const kind = getKind(value) orelse return .{ .void = {} };
    const info = kindInfo(kind);
    if (std.mem.eql(u8, property, "length")) return .{ .integer = @intCast(getLength(value)) };
    if (std.mem.eql(u8, property, "byteLength")) return .{ .integer = @intCast(getLength(value) * info.bpe) };
    if (std.mem.eql(u8, property, "byteOffset")) return .{ .integer = @intCast(getOffset(value)) };
    if (std.mem.eql(u8, property, "buffer")) return value.js_object.properties.get(TYPED_BUFFER_KEY) orelse .{ .void = {} };
    if (std.mem.eql(u8, property, "BYTES_PER_ELEMENT")) return .{ .integer = @intCast(info.bpe) };
    if (TYPED_ARRAY_METHODS_OBJECT.getMethod(property) != null) return .{ .object = @ptrCast(&TYPED_ARRAY_METHODS_OBJECT) };
    return value.js_object.properties.get(property) orelse .{ .void = {} };
}

fn keyFromValue(value: Types.Value, env: *Environment) ?[]const u8 {
    return switch (value) {
        .string => |s| s,
        .integer => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk null;
            const owned = env.allocator.dupe(u8, s) catch break :blk null;
            env.owned_strings.append(env.allocator, owned) catch {};
            break :blk owned;
        },
        .float => |f| blk: {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch break :blk null;
            const owned = env.allocator.dupe(u8, s) catch break :blk null;
            env.owned_strings.append(env.allocator, owned) catch {};
            break :blk owned;
        },
        .symbol => |sym| blk: {
            const s = Ast.symbolPropertyName(env.allocator, sym.description) catch break :blk null;
            env.owned_strings.append(env.allocator, s) catch {};
            break :blk s;
        },
        else => null,
    };
}

fn indexFromKey(key: []const u8) ?usize {
    if (key.len == 0) return null;
    if (key.len > 1 and key[0] == '0') return null;
    for (key) |c| if (c < '0' or c > '9') return null;
    const idx = std.fmt.parseInt(usize, key, 10) catch return null;
    return idx;
}

pub fn getIndex(value: Types.Value, index: Types.Value, env: *Environment) Types.Value {
    if (!isTypedArray(value)) return .{ .void = {} };
    const key = keyFromValue(index, env) orelse return .{ .void = {} };
    if (std.mem.eql(u8, key, "@@iterator")) return .{ .object = @ptrCast(&TYPED_ARRAY_METHODS_OBJECT) };
    const idx = indexFromKey(key) orelse return .{ .void = {} };
    return getElement(value, idx, env);
}

pub fn setIndex(value: Types.Value, index: Types.Value, new_value: Types.Value, env: *Environment) !void {
    if (!isTypedArray(value)) return error.InvalidReceiver;
    const key = keyFromValue(index, env) orelse return;
    const idx = indexFromKey(key) orelse return;
    writeElement(value, idx, new_value, env) catch |err| return err;
}

fn invokeMethodObject(obj: *const Types.BuiltinObjectImpl, receiver: Types.Value, name: []const u8, args: []const Types.Value, env: *Environment) !?Types.Value {
    const method = obj.getMethod(name) orelse return null;
    var list = try std.ArrayList(Types.Value).initCapacity(env.allocator, args.len + 1);
    defer list.deinit(env.allocator);
    try list.append(env.allocator, receiver);
    try list.appendSlice(env.allocator, args);
    const result = method(list.items, env);
    if (env.throw_hit) return error.Thrown;
    return switch (result) {
        .value => |v| v,
        .void => .{ .void = {} },
    };
}

pub fn callMethod(value: Types.Value, name: []const u8, args: []const Types.Value, env: *Environment) !?Types.Value {
    if (isArrayBuffer(value)) return invokeMethodObject(&BUFFER_METHODS_OBJECT, value, name, args, env);
    if (isDataView(value)) return invokeMethodObject(&DATAVIEW_METHODS_OBJECT, value, name, args, env);
    if (isTypedArray(value)) return invokeMethodObject(&TYPED_ARRAY_METHODS_OBJECT, value, name, args, env);
    return null;
}

const testing = std.testing;

test "typed array integer conversion and clamping" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const signed = try constructFromValues(.int8, &.{
        .{ .integer = 127 },
        .{ .integer = 128 },
        .{ .integer = 255 },
        .{ .integer = -129 },
    }, &env);
    try testing.expectEqual(@as(i64, 127), getElement(signed, 0, &env).integer);
    try testing.expectEqual(@as(i64, -128), getElement(signed, 1, &env).integer);
    try testing.expectEqual(@as(i64, -1), getElement(signed, 2, &env).integer);
    try testing.expectEqual(@as(i64, 127), getElement(signed, 3, &env).integer);

    const clamped = try constructFromValues(.uint8clamped, &.{
        .{ .integer = -1 },
        .{ .float = 0.5 },
        .{ .float = 1.5 },
        .{ .float = 2.5 },
        .{ .float = 254.6 },
        .{ .integer = 300 },
    }, &env);
    const expected = [_]i64{ 0, 0, 2, 2, 255, 255 };
    for (expected, 0..) |want, i| {
        try testing.expectEqual(want, getElement(clamped, i, &env).integer);
    }
}

test "typed array float32 rounds to single precision" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const view = try constructFromValues(.float32, &.{
        .{ .float = 1.1 },
        .{ .float = 2.2 },
    }, &env);
    try testing.expectEqual(@as(f64, 1.100000023841858), getElement(view, 0, &env).float);
    try testing.expectEqual(@as(f64, 2.200000047683716), getElement(view, 1, &env).float);
}

test "typed array views share their backing buffer" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const buffer_obj = try allocateBuffer(&env, 4, false);
    const buffer: Types.Value = .{ .js_object = buffer_obj };
    const first = try createView(&env, .uint8, buffer, 0, 4);
    const second = try createView(&env, .uint8, buffer, 0, 4);

    try writeElement(first, 1, .{ .integer = 42 }, &env);
    try testing.expectEqual(@as(i64, 42), getElement(second, 1, &env).integer);

    var sub_args = [_]Types.Value{ first, .{ .integer = 1 }, .{ .integer = 3 } };
    const sub_result = methodSubarray(&sub_args, &env);
    try testing.expect(sub_result == .value);
    const sub = sub_result.value;
    try testing.expectEqual(@as(i64, 42), getElement(sub, 0, &env).integer);
    try testing.expectEqual(@as(i64, 0), getElement(sub, 1, &env).integer);
}

test "typed array slice copies but subarray shares" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const source = try constructFromValues(.uint8, &.{
        .{ .integer = 1 },
        .{ .integer = 2 },
        .{ .integer = 3 },
        .{ .integer = 4 },
    }, &env);

    var slice_args = [_]Types.Value{ source, .{ .integer = 1 }, .{ .integer = 3 } };
    const slice_result = methodSlice(&slice_args, &env);
    try testing.expect(slice_result == .value);
    const slice = slice_result.value;
    try writeElement(slice, 0, .{ .integer = 9 }, &env);
    try testing.expectEqual(@as(i64, 2), getElement(source, 1, &env).integer);

    var sub_args = [_]Types.Value{ source, .{ .integer = 1 }, .{ .integer = 3 } };
    const sub_result = methodSubarray(&sub_args, &env);
    try testing.expect(sub_result == .value);
    const sub = sub_result.value;
    try writeElement(sub, 0, .{ .integer = 7 }, &env);
    try testing.expectEqual(@as(i64, 7), getElement(source, 1, &env).integer);
}

test "DataView reads and writes both endiannesses" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const buffer_obj = try allocateBuffer(&env, 8, false);
    const buffer: Types.Value = .{ .js_object = buffer_obj };
    const view_result = try createDataView(&env, buffer, 0, 8);
    const view = view_result;

    var set_be = [_]Types.Value{ view, .{ .integer = 0 }, .{ .integer = 0x1234 }, .{ .boolean = false } };
    _ = dataViewSet(.uint16, &set_be, &env);
    var set_le = [_]Types.Value{ view, .{ .integer = 2 }, .{ .integer = 0x1234 }, .{ .boolean = true } };
    _ = dataViewSet(.uint16, &set_le, &env);
    const bytes = getBytesFromBuffer(buffer).?;
    try testing.expectEqual(@as(u8, 0x12), bytes[0]);
    try testing.expectEqual(@as(u8, 0x34), bytes[1]);
    try testing.expectEqual(@as(u8, 0x34), bytes[2]);
    try testing.expectEqual(@as(u8, 0x12), bytes[3]);

    var get_be = [_]Types.Value{ view, .{ .integer = 0 }, .{ .boolean = false } };
    const big_endian = dataViewGet(.uint16, &get_be, &env);
    try testing.expect(big_endian == .value);
    try testing.expectEqual(@as(i64, 0x1234), big_endian.value.integer);
    var get_le = [_]Types.Value{ view, .{ .integer = 2 }, .{ .boolean = true } };
    const little_endian = dataViewGet(.uint16, &get_le, &env);
    try testing.expect(little_endian == .value);
    try testing.expectEqual(@as(i64, 0x1234), little_endian.value.integer);
}

test "BigInt typed arrays preserve signed values" {
    var env = try Environment.init(testing.allocator, null);
    defer env.deinit();

    const positive = Ast.BigIntValue.fromString(env.allocator, "1") catch return;
    env.bigints.append(env.allocator, positive) catch {};
    const negative = Ast.BigIntValue.fromString(env.allocator, "-2") catch return;
    env.bigints.append(env.allocator, negative) catch {};

    const view = try constructFromValues(.bigint64, &.{
        .{ .big_int = positive },
        .{ .big_int = negative },
    }, &env);
    const first = getElement(view, 0, &env);
    const second = getElement(view, 1, &env);
    try testing.expect(first == .big_int);
    try testing.expect(second == .big_int);
    const first_text = try first.big_int.toString(env.allocator);
    defer env.allocator.free(first_text);
    const second_text = try second.big_int.toString(env.allocator);
    defer env.allocator.free(second_text);
    try testing.expectEqualStrings("1", first_text);
    try testing.expectEqualStrings("-2", second_text);
}
