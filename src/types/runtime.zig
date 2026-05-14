const std = @import("std");

pub const BuiltinObject = opaque {};

pub const ArrayObject = struct {
    allocator: std.mem.Allocator,
    elements: std.ArrayListAligned(Value, null),

    pub fn init(allocator: std.mem.Allocator) !*ArrayObject {
        const obj = try allocator.create(ArrayObject);
        obj.* = .{ .elements = .empty, .allocator = allocator };
        return obj;
    }

    pub fn deinit(this: *ArrayObject) void {
        if (this.elements.capacity > 0) this.allocator.free(this.elements.allocatedSlice());
        this.allocator.destroy(this);
    }

    pub fn get(this: *ArrayObject, index: usize) ?Value {
        if (index >= this.elements.items.len) return null;
        return this.elements.items[index];
    }

    pub fn set(this: *ArrayObject, index: usize, value: Value) !void {
        if (index >= this.elements.items.len) {
            while (this.elements.items.len <= index) {
                try this.elements.append(this.allocator, .{ .float = 0.0 });
            }
        }
        this.elements.items[index] = value;
    }
};

pub const ObjectValue = struct {
    allocator: std.mem.Allocator,
    properties: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) !*ObjectValue {
        const obj = try allocator.create(ObjectValue);
        obj.* = .{ .allocator = allocator, .properties = std.StringHashMap(Value).init(allocator) };
        return obj;
    }

    pub fn deinit(this: *ObjectValue) void {
        this.properties.deinit();
        this.allocator.destroy(this);
    }
};

pub const ClosureValue = struct {
    chunk_ptr: *ChunkType,
    param_count: u8,
    allocator: std.mem.Allocator,

    pub const ChunkType = struct {
        code: std.ArrayList(u8),
        constants: std.ArrayList(Value),
        lines: std.ArrayList(u32),
        allocator: std.mem.Allocator,
    };

    pub fn init(allocator: std.mem.Allocator, param_count: u8) !*ClosureValue {
        const obj = try allocator.create(ClosureValue);
        const chunk = try allocator.create(ChunkType);
        chunk.* = .{
            .code = try std.ArrayList(u8).initCapacity(allocator, 256),
            .constants = try std.ArrayList(Value).initCapacity(allocator, 64),
            .lines = try std.ArrayList(u32).initCapacity(allocator, 256),
            .allocator = allocator,
        };
        obj.* = .{ .chunk_ptr = chunk, .param_count = param_count, .allocator = allocator };
        return obj;
    }

    pub fn deinit(this: *ClosureValue) void {
        this.chunk_ptr.code.deinit(this.allocator);
        this.chunk_ptr.constants.deinit(this.allocator);
        this.chunk_ptr.lines.deinit(this.allocator);
        this.allocator.destroy(this.chunk_ptr);
        this.allocator.destroy(this);
    }
};

pub const ArrayIterator = struct {
    allocator: std.mem.Allocator,
    source: *ArrayObject,
    index: usize,

    pub fn init(allocator: std.mem.Allocator, source: *ArrayObject) !*ArrayIterator {
        const obj = try allocator.create(ArrayIterator);
        obj.* = .{ .allocator = allocator, .source = source, .index = 0 };
        return obj;
    }

    pub fn deinit(this: *ArrayIterator) void {
        this.allocator.destroy(this);
    }

    pub fn next(this: *ArrayIterator, allocator: std.mem.Allocator, arrays: *std.ArrayList(*ArrayObject), objects: *std.ArrayList(*ObjectValue)) Value {
        var result = ObjectValue.init(allocator) catch return .{ .void = {} };
        errdefer result.deinit();

        if (this.index >= this.source.elements.items.len) {
            result.properties.put("value", .{ .void = {} }) catch {};
            result.properties.put("done", .{ .boolean = true }) catch {};
            objects.append(allocator, result) catch { result.deinit(); return .{ .void = {} }; };
            return .{ .js_object = result };
        }

        var pair = ArrayObject.init(allocator) catch return .{ .void = {} };
        pair.elements.append(allocator, .{ .integer = @intCast(this.index) }) catch { pair.deinit(); return .{ .void = {} }; };
        pair.elements.append(allocator, this.source.elements.items[this.index]) catch { pair.deinit(); return .{ .void = {} }; };
        arrays.append(allocator, pair) catch { pair.deinit(); return .{ .void = {} }; };

        result.properties.put("value", .{ .array = pair }) catch { return .{ .void = {} }; };
        result.properties.put("done", .{ .boolean = false }) catch { return .{ .void = {} }; };
        objects.append(allocator, result) catch { result.deinit(); return .{ .void = {} }; };

        this.index += 1;
        return .{ .js_object = result };
    }
};

pub const Value = union(enum) {
    float: f64,
    integer: i64,
    string: []const u8,
    boolean: bool,
    array: *ArrayObject,
    object: *const BuiltinObject,
    closure: *ClosureValue,
    iterator: *ArrayIterator,
    js_object: *ObjectValue,
    void: void,
    null: void,
};

pub const BuiltinResult = union(enum) {
    value: Value,
    void,
};
