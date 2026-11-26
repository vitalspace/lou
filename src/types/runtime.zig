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
     properties: StringHashMap,

     /// Back-pointer to this object's prototype (the next link in the
     /// chain). Used by getPropChain / lookupInChain to follow the
     /// prototype chain during property lookup and method dispatch.
     /// `null` means this object has no prototype (e.g. Object.create(null),
     /// or the chain terminal at Object.prototype).
     prototype: ?*ObjectValue = null,


     pub const StringHashMap = struct {
         map: std.StringArrayHashMapUnmanaged(Value),
         allocator: std.mem.Allocator,

         pub fn init(allocator: std.mem.Allocator) StringHashMap {
             return .{ .map = .{}, .allocator = allocator };
         }

         pub fn deinit(self: *StringHashMap) void {
             self.map.deinit(self.allocator);
         }

         pub fn get(self: *const StringHashMap, key: []const u8) ?Value {
             return self.map.get(key);
         }

         pub fn put(self: *StringHashMap, key: []const u8, value: Value) !void {
             try self.map.put(self.allocator, key, value);
         }

         pub fn contains(self: *const StringHashMap, key: []const u8) bool {
             return self.map.contains(key);
         }

        pub fn remove(self: *StringHashMap, key: []const u8) bool {
            const had = self.map.contains(key);
            if (had) _ = self.map.swapRemove(key);
            return had;
        }

         pub fn iterator(self: *const StringHashMap) std.StringArrayHashMapUnmanaged(Value).Iterator {
             return self.map.iterator();
         }
     };

     pub fn init(allocator: std.mem.Allocator) !*ObjectValue {
         return initWithProto(allocator, null);
     }

     /// Init an ObjectValue with an optional prototype link. Pass null
     /// for an object with no prototype (e.g. Object.create(null)).
     pub fn initWithProto(allocator: std.mem.Allocator, proto: ?*ObjectValue) !*ObjectValue {
         const obj = try allocator.create(ObjectValue);
         obj.* = .{ .allocator = allocator, .properties = StringHashMap.init(allocator), .prototype = proto };
         return obj;
     }

     pub fn deinit(this: *ObjectValue) void {
         this.properties.deinit();
         this.allocator.destroy(this);
     }

     /// Returns keys in ES for-in enumeration order:
     /// 1. Integer indices (parseable as non-negative integer) in ascending numeric order
     /// 2. String keys in insertion order (skipping @@-prefixed internal keys)
     /// The result is an ArrayObject whose elements are .string Values (the key names).
     pub fn getForInKeys(this: *ObjectValue, env_allocator: std.mem.Allocator, arrays: *std.ArrayList(*ArrayObject)) !*ArrayObject {
         const keys_arr = try ArrayObject.init(env_allocator);
         errdefer keys_arr.deinit();

         var int_keys = try std.ArrayList(struct { key: []const u8, num: usize }).initCapacity(env_allocator, 0);
         defer int_keys.deinit(env_allocator);
         var str_keys = try std.ArrayList([]const u8).initCapacity(env_allocator, 0);
         defer str_keys.deinit(env_allocator);

         var it = this.properties.iterator();
         while (it.next()) |entry| {
             const key = entry.key_ptr.*;
             // Skip internal @@-prefixed keys
             if (key.len >= 2 and std.mem.eql(u8, key[0..2], "@@")) continue;
             // Try parse as non-negative integer index.
             // Must be canonical (no leading zeros except "0" itself)
             // per ES 7.3.23 - only canonical numeric strings are array indices.
             if (std.fmt.parseInt(usize, key, 10)) |num| {
                 var buf: [32]u8 = undefined;
                 const canonical = std.fmt.bufPrint(&buf, "{d}", .{num}) catch "_";
                 // ECMAScript array indices are < 2^32 - 1, so 4294967295
                  // and larger are plain string keys, not integer keys.
                  if (num < 4294967295 and std.mem.eql(u8, key, canonical)) {
                     try int_keys.append(env_allocator, .{ .key = key, .num = num });
                 } else {
                     try str_keys.append(env_allocator, key);
                 }
             } else |_| {
                 try str_keys.append(env_allocator, key);
             }
         }

         // Sort integer keys by numeric value ascending
         std.mem.sort(
             @TypeOf(int_keys.items[0]),
             int_keys.items,
             {},
             struct {
                 fn lt(_: void, a: @TypeOf(int_keys.items[0]), b: @TypeOf(int_keys.items[0])) bool {
                     return a.num < b.num;
                 }
             }.lt,
         );

         // Append integer keys first (already sorted ascending)
         for (int_keys.items) |ik| {
             try keys_arr.elements.append(env_allocator, .{ .string = ik.key });
         }

         // Append string keys in insertion order
         for (str_keys.items) |sk| {
             try keys_arr.elements.append(env_allocator, .{ .string = sk });
         }

         try arrays.append(env_allocator, keys_arr);
         return keys_arr;
     }
 };

/// A closure: a function (AST node) coupled with the environment it was
/// defined in (its lexical scope). Used when a function is defined inside
/// another function and needs to capture variables from the outer scope.
pub const ClosureValue = struct {
    func_node: *AstNode,
    /// Heap-allocated Environment that serves as the closure's lexical
    /// scope. Owned by this ClosureValue — deinit calls release().
    env: *anyopaque,
    allocator: std.mem.Allocator,

    /// The `env` parameter must be a heap-allocated `*Environment` that
    /// this ClosureValue takes shared ownership of (via retain).
    pub fn init(allocator: std.mem.Allocator, func_node: *AstNode, env: *anyopaque) !*ClosureValue {
        const obj = try allocator.create(ClosureValue);
        obj.* = .{ .func_node = func_node, .env = env, .allocator = allocator };
        // Take shared ownership of the captured environment.
        const e: *@import("../environment.zig").Environment = @alignCast(@ptrCast(env));
        e.retain();
        // Track in the root environment's global closures list so the
        // closure is freed at program exit even if never stored in a
        // values HashMap (e.g. immediately-consumed closures).
        e.closures.append(e.allocator, obj) catch {};
        return obj;
    }

    pub fn deinit(this: *ClosureValue) void {
        const e: *@import("../environment.zig").Environment = @alignCast(@ptrCast(this.env));
        e.release();
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
    dispose = 9,
    asyncDispose = 10,
};

pub fn symbolPropertyName(allocator: std.mem.Allocator, description: []const u8) ![]const u8 {
    const full = try std.fmt.allocPrint(allocator, "@@{s}", .{description});
    return full;
}

pub const RegExpValue = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    flags: []const u8,
    global: bool,
    ignore_case: bool,
    multiline: bool,
    dot_all: bool,
    unicode: bool,
    sticky: bool,
    has_indices: bool,
    last_index: u32,
    cached: ?*anyopaque = null,
    cached_deinit: ?*const fn (*anyopaque, std.mem.Allocator) void = null,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8, flags_str: []const u8) !*RegExpValue {
        const obj = try allocator.create(RegExpValue);
        const pattern_dup = try allocator.dupe(u8, pattern);
        errdefer allocator.free(pattern_dup);
        const flags_dup = try allocator.dupe(u8, flags_str);
        obj.* = .{
            .allocator = allocator,
            .pattern = pattern_dup,
            .flags = flags_dup,
            .global = std.mem.indexOfScalar(u8, flags_str, 'g') != null,
            .ignore_case = std.mem.indexOfScalar(u8, flags_str, 'i') != null,
            .multiline = std.mem.indexOfScalar(u8, flags_str, 'm') != null,
            .dot_all = std.mem.indexOfScalar(u8, flags_str, 's') != null,
            .unicode = std.mem.indexOfScalar(u8, flags_str, 'u') != null,
            .sticky = std.mem.indexOfScalar(u8, flags_str, 'y') != null,
            .has_indices = std.mem.indexOfScalar(u8, flags_str, 'd') != null,
            .last_index = 0,
            .cached = null,
        };
        return obj;
    }

    pub fn deinit(this: *RegExpValue) void {
        this.allocator.free(this.pattern);
        this.allocator.free(this.flags);
        if (this.cached) |c| {
            if (this.cached_deinit) |cleanup| {
                cleanup(c, this.allocator);
            }
        }
        this.allocator.destroy(this);
    }

    pub fn lastIndex(this: *const RegExpValue) u32 {
        return this.last_index;
    }

    pub fn setLastIndex(this: *RegExpValue, idx: u32) void {
        this.last_index = idx;
    }
};

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
        errdefer obj.deinit();

        // StringToBigInt / BigInt(string) semantics: trim whitespace, accept
        // 0x/0o/0b radix prefixes, empty string is 0n, and a sign is only
        // valid for decimal literals (BigInt("-0x10") throws).
        const trimmed = std.mem.trim(u8, str, " \t\n\r\x0b\x0c");
        if (trimmed.len == 0) {
            obj.value.setString(10, "0") catch return error.InvalidBigInt;
            return obj;
        }
        var body = trimmed;
        const has_sign = body[0] == '+' or body[0] == '-';
        const negative = body[0] == '-';
        if (has_sign) body = body[1..];
        var radix: u8 = 10;
        if (body.len >= 2 and body[0] == '0') {
            radix = switch (body[1]) {
                'x', 'X' => 16,
                'o', 'O' => 8,
                'b', 'B' => 2,
                else => 10,
            };
            if (radix != 10) {
                if (has_sign) return error.InvalidBigInt;
                body = body[2..];
            }
        }
        obj.value.setString(radix, body) catch return error.InvalidBigInt;
        if (negative) obj.value.negate();
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
    array_iterator: *ArrayObject,
    js_object: *ObjectValue,
    function: *AstNode,
    generator: *GeneratorObject,
    symbol: *SymbolValue,
    regexp: *RegExpValue,
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

/// Returns true if the value is callable (can be invoked as a function).
/// Callable types: .function, .closure, .generator.
pub fn isCallable(v: Value) bool {
    return switch (v) {
        .function, .closure, .generator => true,
        else => false,
    };
}

// === Unit tests for getForInKeys ===

test "getForInKeys: integer keys sorted ascending, then string keys insertion order" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    // Insert in non-sorted order to verify sort
    try obj.properties.put("z", .{ .float = 1.0 });
    try obj.properties.put("2", .{ .float = 2.0 });
    try obj.properties.put("a", .{ .float = 3.0 });
    try obj.properties.put("10", .{ .float = 4.0 });
    try obj.properties.put("b", .{ .float = 5.0 });
    try obj.properties.put("0", .{ .float = 6.0 });

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    // Expected: "0", "2", "10", "z", "a", "b"
    try std.testing.expectEqual(@as(usize, 6), keys.elements.items.len);
    try std.testing.expectEqualStrings("0", keys.elements.items[0].string);
    try std.testing.expectEqualStrings("2", keys.elements.items[1].string);
    try std.testing.expectEqualStrings("10", keys.elements.items[2].string);
    try std.testing.expectEqualStrings("z", keys.elements.items[3].string);
    try std.testing.expectEqualStrings("a", keys.elements.items[4].string);
    try std.testing.expectEqualStrings("b", keys.elements.items[5].string);
}

test "getForInKeys: non-canonical integer keys treated as strings" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    // "00" and "01" are NOT canonical — they must be treated as string keys
    try obj.properties.put("a", .{ .float = 1.0 });
    try obj.properties.put("00", .{ .float = 2.0 });
    try obj.properties.put("0", .{ .float = 3.0 });
    try obj.properties.put("01", .{ .float = 4.0 });
    try obj.properties.put("b", .{ .float = 5.0 });

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    // Expected: "0" (int), then "a", "00", "01", "b" (strings in insertion order)
    try std.testing.expectEqual(@as(usize, 5), keys.elements.items.len);
    try std.testing.expectEqualStrings("0", keys.elements.items[0].string);
    try std.testing.expectEqualStrings("a", keys.elements.items[1].string);
    try std.testing.expectEqualStrings("00", keys.elements.items[2].string);
    try std.testing.expectEqualStrings("01", keys.elements.items[3].string);
    try std.testing.expectEqualStrings("b", keys.elements.items[4].string);
}

test "getForInKeys: @@-prefixed internal keys are skipped" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    try obj.properties.put("@@type", .{ .string = "MyType" });
    try obj.properties.put("@@iterator", .{ .float = 1.0 });
    try obj.properties.put("a", .{ .float = 2.0 });
    try obj.properties.put("1", .{ .float = 3.0 });
    try obj.properties.put("@@internal", .{ .float = 4.0 });

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    // Expected: "1" (int), then "a" (string). No @@ keys.
    try std.testing.expectEqual(@as(usize, 2), keys.elements.items.len);
    try std.testing.expectEqualStrings("1", keys.elements.items[0].string);
    try std.testing.expectEqualStrings("a", keys.elements.items[1].string);
}

test "getForInKeys: only integer keys sorted ascending" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    try obj.properties.put("5", .{ .float = 1.0 });
    try obj.properties.put("1", .{ .float = 2.0 });
    try obj.properties.put("3", .{ .float = 3.0 });
    try obj.properties.put("20", .{ .float = 4.0 });

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    try std.testing.expectEqual(@as(usize, 4), keys.elements.items.len);
    try std.testing.expectEqualStrings("1", keys.elements.items[0].string);
    try std.testing.expectEqualStrings("3", keys.elements.items[1].string);
    try std.testing.expectEqualStrings("5", keys.elements.items[2].string);
    try std.testing.expectEqualStrings("20", keys.elements.items[3].string);
}

test "getForInKeys: 4294967295 is a string key, not an array index" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    try obj.properties.put("a", .{ .float = 1.0 });
    try obj.properties.put("4294967295", .{ .float = 2.0 });
    try obj.properties.put("5", .{ .float = 3.0 });
    try obj.properties.put("b", .{ .float = 4.0 });

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    try std.testing.expectEqual(@as(usize, 4), keys.elements.items.len);
    try std.testing.expectEqualStrings("5", keys.elements.items[0].string);
    try std.testing.expectEqualStrings("a", keys.elements.items[1].string);
    try std.testing.expectEqualStrings("4294967295", keys.elements.items[2].string);
    try std.testing.expectEqualStrings("b", keys.elements.items[3].string);
}

test "getForInKeys: only string keys preserve insertion order" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    try obj.properties.put("c", .{ .float = 1.0 });
    try obj.properties.put("a", .{ .float = 2.0 });
    try obj.properties.put("b", .{ .float = 3.0 });

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    try std.testing.expectEqual(@as(usize, 3), keys.elements.items.len);
    try std.testing.expectEqualStrings("c", keys.elements.items[0].string);
    try std.testing.expectEqualStrings("a", keys.elements.items[1].string);
    try std.testing.expectEqualStrings("b", keys.elements.items[2].string);
}

test "getForInKeys: empty object returns empty array" {
    const allocator = std.testing.allocator;

    var obj = try ObjectValue.init(allocator);
    defer obj.deinit();

    var arrays = try std.ArrayList(*ArrayObject).initCapacity(allocator, 0);
    defer arrays.deinit(allocator);

    const keys = try obj.getForInKeys(allocator, &arrays);
    defer keys.deinit();

    try std.testing.expectEqual(@as(usize, 0), keys.elements.items.len);
}

