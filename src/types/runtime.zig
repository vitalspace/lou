const std = @import("std");

pub const BuiltinObject = opaque {};
pub const AstNode = opaque {};

pub const ArrayObject = struct {
    allocator: std.mem.Allocator,
    elements: std.ArrayListAligned(Value, null),
    extras: ?*ObjectValue = null,

    pub fn init(allocator: std.mem.Allocator) !*ArrayObject {
        const obj = try allocator.create(ArrayObject);
        obj.* = .{ .elements = .empty, .allocator = allocator };
        return obj;
    }

    pub fn initExtras(allocator: std.mem.Allocator) !*ArrayObject {
        const obj = try allocator.create(ArrayObject);
        const extras = try ObjectValue.init(allocator);
        obj.* = .{ .elements = .empty, .allocator = allocator, .extras = extras };
        return obj;
    }

    pub fn deinit(this: *ArrayObject) void {
        if (this.elements.capacity > 0) this.allocator.free(this.elements.allocatedSlice());
        if (this.extras) |e| e.deinit();
        this.allocator.destroy(this);
    }

    pub fn get(this: *ArrayObject, index: usize) ?Value {
        if (index >= this.elements.items.len) return null;
        return this.elements.items[index];
    }

    pub fn set(this: *ArrayObject, index: usize, value: Value) !void {
        if (index >= this.elements.items.len) {
            while (this.elements.items.len <= index) {
                try this.elements.append(this.allocator, .{ .hole = {} });
            }
        }
        this.elements.items[index] = value;
    }
};

pub const ObjectValue = struct {
     allocator: std.mem.Allocator,
     properties: std.StringArrayHashMap(Value),

     pub fn init(allocator: std.mem.Allocator) !*ObjectValue {
         const obj = try allocator.create(ObjectValue);
         obj.* = .{ .allocator = allocator, .properties = std.StringArrayHashMap(Value).init(allocator) };
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
    key_mode: bool,
    value_mode: bool,

    pub fn init(allocator: std.mem.Allocator, source: *ArrayObject) !*ArrayIterator {
        const obj = try allocator.create(ArrayIterator);
        obj.* = .{ .allocator = allocator, .source = source, .index = 0, .key_mode = false, .value_mode = false };
        return obj;
    }

    pub fn initKeys(allocator: std.mem.Allocator, source: *ArrayObject) !*ArrayIterator {
        const obj = try allocator.create(ArrayIterator);
        obj.* = .{ .allocator = allocator, .source = source, .index = 0, .key_mode = true, .value_mode = false };
        return obj;
    }

    pub fn initValues(allocator: std.mem.Allocator, source: *ArrayObject) !*ArrayIterator {
        const obj = try allocator.create(ArrayIterator);
        obj.* = .{ .allocator = allocator, .source = source, .index = 0, .key_mode = false, .value_mode = true };
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

        const element: Value = if (this.source.elements.items[this.index] == .hole) Value{ .void = {} } else this.source.elements.items[this.index];

        if (this.value_mode) {
            result.properties.put("value", element) catch { return .{ .void = {} }; };
        } else if (this.key_mode) {
            result.properties.put("value", .{ .integer = @intCast(this.index) }) catch { return .{ .void = {} }; };
        } else {
            var pair = ArrayObject.init(allocator) catch return .{ .void = {} };
            pair.elements.append(allocator, .{ .integer = @intCast(this.index) }) catch { pair.deinit(); return .{ .void = {} }; };
            pair.elements.append(allocator, element) catch { pair.deinit(); return .{ .void = {} }; };
            arrays.append(allocator, pair) catch { pair.deinit(); return .{ .void = {} }; };
            result.properties.put("value", .{ .array = pair }) catch { return .{ .void = {} }; };
        }
        result.properties.put("done", .{ .boolean = false }) catch { return .{ .void = {} }; };
        objects.append(allocator, result) catch { result.deinit(); return .{ .void = {} }; };

        this.index += 1;
        return .{ .js_object = result };
    }
};

pub const SymbolValue = struct {
    id: u64,
    description: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: u64, description: []const u8) !*SymbolValue {
        const sym = try allocator.create(SymbolValue);
        sym.* = .{ .id = id, .description = try allocator.dupe(u8, description), .allocator = allocator };
        return sym;
    }

    pub fn deinit(this: *SymbolValue) void {
        this.allocator.free(this.description);
        this.allocator.destroy(this);
    }
};

pub const WellKnownSymbol = enum(u64) {
    iterator = 0,
    match = 1,
    replace = 2,
    search = 3,
    split = 4,
    hasInstance = 5,
    toPrimitive = 6,
    toStringTag = 7,
    species = 8,
};

pub fn symbolPropertyName(allocator: std.mem.Allocator, description: []const u8) ![]const u8 {
    const full = try std.fmt.allocPrint(allocator, "@@{s}", .{description});
    return full;
}

pub const BigIntValue = struct {
    allocator: std.mem.Allocator,
    value: std.math.big.int.Managed,

    pub fn init(allocator: std.mem.Allocator) !*BigIntValue {
        const obj = try allocator.create(BigIntValue);
        obj.* = .{
            .allocator = allocator,
            .value = try std.math.big.int.Managed.init(allocator),
        };
        return obj;
    }

    pub fn deinit(this: *BigIntValue) void {
        this.value.deinit();
        this.allocator.destroy(this);
    }

    pub fn fromString(allocator_: std.mem.Allocator, str: []const u8) !*BigIntValue {
        const obj = try allocator_.create(BigIntValue);
        obj.* = .{
            .allocator = allocator_,
            .value = try std.math.big.int.Managed.init(allocator_),
        };
        obj.value.setString(10, str) catch {
            obj.deinit();
            return error.InvalidBigInt;
        };
        return obj;
    }

    /// Convert BigInt to its digit string (without `n` suffix). Caller owns the result.
    pub fn toString(self: *BigIntValue, allocator_: std.mem.Allocator) ![]const u8 {
        return self.value.toString(allocator_, 10, .lower);
    }

    /// Compare two BigInts. Returns .lt, .eq, or .gt.
    pub fn compare(a: *const BigIntValue, b: *const BigIntValue) std.math.Order {
        return std.math.big.int.Managed.order(a.value, b.value);
    }

    /// True if BigInt equals zero.
    pub fn eqlZero(self: *const BigIntValue) bool {
        return self.value.eqlZero();
    }

    /// Try to convert BigInt to i64. Returns false if it doesn't fit.
    pub fn toI64(self: *BigIntValue) ?i64 {
        // Slow path: convert via string. (We can't read raw limbs directly
        // without depending on internal API of std.math.big.int.Managed.)
        const s = self.value.toString(self.allocator, 10, .lower) catch return null;
        defer self.allocator.free(s);
        return std.fmt.parseInt(i64, s, 10) catch null;
    }
};

pub const Value = union(enum) {
    float: f64,
    integer: i64,
    big_int: *BigIntValue,
    string: []const u8,
    boolean: bool,
    array: *ArrayObject,
    object: *const BuiltinObject,
    closure: *ClosureValue,
    iterator: *ArrayIterator,
    js_object: *ObjectValue,
    function: *AstNode,
    generator: *GeneratorObject,
    symbol: *SymbolValue,
    void: void,
    null: void,
    hole: void,
};

pub const GeneratorObject = struct {
    allocator: std.mem.Allocator,
    func_node: *AstNode, // The GeneratorDeclaration AST node
    params: []const []const u8,
    gen_env: ?*anyopaque, // Opaque pointer to the generator's persistent environment
    ip: usize, // Instruction pointer (index into body statements)
    done: bool,

    pub fn init(allocator: std.mem.Allocator, func_node: *AstNode, params: []const []const u8) !*GeneratorObject {
        const obj = try allocator.create(GeneratorObject);
        obj.* = .{
            .allocator = allocator,
            .func_node = func_node,
            .params = params,
            .gen_env = null,
            .ip = 0,
            .done = false,
        };
        return obj;
    }

    pub fn deinit(this: *GeneratorObject) void {
        // Note: gen_env lifecycle is managed externally by the Environment deinit chain.
        // See Environment.deinit() in environment.zig which frees gen_env before calling this.
        this.allocator.destroy(this);
    }
};

pub const BuiltinResult = union(enum) {
    value: Value,
    void,
};
