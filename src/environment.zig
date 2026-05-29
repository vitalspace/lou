const std = @import("std");
const ast = @import("ast.zig");
const builtins = @import("./builtins/builtins.zig");
const builtinsTypes = @import("./types/types.zig");

pub const Io = std.Io;
pub const DEBUG_OPTIMIZATION = false;

pub inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG_OPTIMIZATION) {
        std.debug.print(fmt, args);
    }
}

inline fn freeValue(value: ast.Value) void {
    switch (value) {
        .array => |arr| arr.deinit(),
        .closure => |cl| cl.deinit(),
        .iterator => |it| it.deinit(),
        .js_object => |obj| obj.deinit(),
        .symbol => |sym| sym.deinit(),
        else => {},
    }
}

pub const ModuleCacheEntry = struct {
    exports: std.StringHashMap(ast.Value),
    functions: std.StringHashMap(*ast.Node),

    pub fn deinit(self: *ModuleCacheEntry) void {
        self.exports.deinit();
        self.functions.deinit();
    }
};

pub const Environment = struct {
    allocator: std.mem.Allocator,
    io: ?std.Io,
    values: std.StringHashMap(ast.Value),
    constants: std.StringHashMap(void),
    functions: std.StringHashMap(*ast.Node),
    builtins: std.StringHashMap(builtinsTypes.BuiltinFn),
    builtin_objects: std.StringHashMap(*const builtinsTypes.BuiltinObjectImpl),
    timers: std.StringHashMap(i128),
    arrays: std.ArrayList(*ast.ArrayObject),
    iterators: std.ArrayList(*ast.ArrayIterator),
    objects: std.ArrayList(*ast.ObjectValue),
    symbols: std.ArrayList(*ast.SymbolValue),
    generators: std.ArrayList(*ast.GeneratorObject),
    owned_strings: std.ArrayList([]const u8),
    outer: ?*Environment,
    scope_kind: enum { block, function } = .function,
    return_hit: bool = false,
    yield_hit: bool = false,
    yield_value: ast.Value = .{ .void = {} },
    yield_caught_by_loop: bool = false,
    yield_star_gen: ?*ast.GeneratorObject = null,
    yield_star_array: ?*ast.ArrayObject = null,
    yield_star_index: usize = 0,
    yield_star_iterator: ?*ast.ArrayIterator = null,
    yield_star_string: ?[]const u8 = null,
    yield_star_js_iterator: ?*ast.ObjectValue = null,
    for_yield_node: ?*const anyopaque = null,
    for_of_gen: ?*ast.GeneratorObject = null,
    for_of_array: ?*ast.ArrayObject = null,
    for_of_array_index: usize = 0,
    exports: std.StringHashMap(ast.Value),
    module_dir: ?[]const u8,
    module_contents: std.ArrayList([]const u8),
    module_arenas: std.ArrayList(*std.heap.ArenaAllocator),
    module_cache: std.StringHashMap(ModuleCacheEntry),

    pub fn init(allocator: std.mem.Allocator, outer: ?*Environment) !Environment {
        return initWithIo(allocator, outer, if (outer) |o| o.io else null);
    }

    pub fn initModule(allocator: std.mem.Allocator, module_dir: []const u8) !Environment {
        var env = try initWithIo(allocator, null, null);
        env.module_dir = module_dir;
        return env;
    }

    pub fn initWithIo(allocator: std.mem.Allocator, outer: ?*Environment, io: ?std.Io) !Environment {
        const arrays = try std.ArrayList(*ast.ArrayObject).initCapacity(allocator, 0);
        const iterators = try std.ArrayList(*ast.ArrayIterator).initCapacity(allocator, 0);
        const objects = try std.ArrayList(*ast.ObjectValue).initCapacity(allocator, 0);
        const symbols = try std.ArrayList(*ast.SymbolValue).initCapacity(allocator, 0);
        const generators = try std.ArrayList(*ast.GeneratorObject).initCapacity(allocator, 0);
        const owned_strings = try std.ArrayList([]const u8).initCapacity(allocator, 0);

        const env = Environment{
            .allocator = allocator,
            .io = io,
            .values = std.StringHashMap(ast.Value).init(allocator),
            .constants = std.StringHashMap(void).init(allocator),
            .functions = std.StringHashMap(*ast.Node).init(allocator),
            .builtins = try builtins.initBuiltins(allocator),
            .builtin_objects = try builtins.initBuiltinObjects(allocator),
            .timers = std.StringHashMap(i128).init(allocator),
            .arrays = arrays,
            .iterators = iterators,
            .objects = objects,
            .symbols = symbols,
            .generators = generators,
            .owned_strings = owned_strings,
            .outer = outer,
            .exports = std.StringHashMap(ast.Value).init(allocator),
            .module_dir = null,
            .module_contents = try std.ArrayList([]const u8).initCapacity(allocator, 0),
            .module_arenas = try std.ArrayList(*std.heap.ArenaAllocator).initCapacity(allocator, 0),
            .module_cache = std.StringHashMap(ModuleCacheEntry).init(allocator),
        };

        return env;
    }

    pub fn initBlock(allocator: std.mem.Allocator, outer: *Environment) !Environment {
        const owned_strings = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        const env = Environment{
            .allocator = allocator,
            .io = outer.io,
            .values = std.StringHashMap(ast.Value).init(allocator),
            .constants = std.StringHashMap(void).init(allocator),
            .functions = std.StringHashMap(*ast.Node).init(allocator),
            .builtins = std.StringHashMap(builtinsTypes.BuiltinFn).init(allocator),
            .builtin_objects = std.StringHashMap(*const builtinsTypes.BuiltinObjectImpl).init(allocator),
            .timers = std.StringHashMap(i128).init(allocator),
            .arrays = try std.ArrayList(*ast.ArrayObject).initCapacity(allocator, 0),
            .iterators = try std.ArrayList(*ast.ArrayIterator).initCapacity(allocator, 0),
            .objects = try std.ArrayList(*ast.ObjectValue).initCapacity(allocator, 0),
            .symbols = try std.ArrayList(*ast.SymbolValue).initCapacity(allocator, 0),
            .generators = try std.ArrayList(*ast.GeneratorObject).initCapacity(allocator, 0),
            .owned_strings = owned_strings,
            .outer = outer,
            .scope_kind = .block,
            .exports = std.StringHashMap(ast.Value).init(allocator),
            .module_dir = null,
            .module_contents = try std.ArrayList([]const u8).initCapacity(allocator, 0),
            .module_arenas = try std.ArrayList(*std.heap.ArenaAllocator).initCapacity(allocator, 0),
            .module_cache = std.StringHashMap(ModuleCacheEntry).init(allocator),
        };
        return env;
    }

    pub fn getFunction(self: *Environment, name: []const u8) ?*ast.Node {
        if (self.functions.get(name)) |node| {
            return node;
        }
        if (self.outer) |outer| {
            return outer.getFunction(name);
        }
        return null;
    }

    pub fn getFunctionWithModuleFallback(self: *Environment, name: []const u8) ?*ast.Node {
        if (self.getFunction(name)) |node| return node;
        var root = self;
        while (root.outer) |outer| root = outer;
        var it = root.module_cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.functions.get(name)) |node| return node;
        }
        return null;
    }

    pub fn setFunction(self: *Environment, name: []const u8, node: *ast.Node) !void {
        var env = self;
        while (env.scope_kind == .block) {
            if (env.outer) |outer| {
                env = outer;
            } else {
                break;
            }
        }
        try env.functions.put(name, node);
    }

    pub fn getBuiltin(self: *Environment, name: []const u8) ?builtinsTypes.BuiltinFn {
        if (self.builtins.get(name)) |fn_ptr| {
            return fn_ptr;
        }
        if (self.outer) |outer| {
            return outer.getBuiltin(name);
        }
        return null;
    }

    pub fn getBuiltinObject(self: *Environment, name: []const u8) ?*const builtinsTypes.BuiltinObjectImpl {
        if (self.builtin_objects.get(name)) |obj| {
            return obj;
        }
        if (self.outer) |outer| {
            return outer.getBuiltinObject(name);
        }
        return null;
    }

    pub fn getTimer(self: *Environment, name: []const u8) ?i64 {
        if (self.timers.get(name)) |t| {
            return t;
        }
        if (self.outer) |outer| {
            return outer.getTimer(name);
        }
        return null;
    }

    pub fn setTimer(self: *Environment, name: []const u8, value: i64) !void {
        var env = self;
        while (env.scope_kind == .block) {
            if (env.outer) |outer| {
                env = outer;
            } else {
                break;
            }
        }
        try env.timers.put(name, value);
    }

    pub fn setVar(self: *Environment, name: []const u8, value: ast.Value) !void {
        var env = self;
        while (env.scope_kind == .block) {
            if (env.outer) |outer| {
                env = outer;
            } else {
                break;
            }
        }
        if (env.constants.contains(name)) {
            return error.ConstantReassignment;
        }
        try env.values.put(name, value);
    }

    pub fn setLet(self: *Environment, name: []const u8, value: ast.Value) !void {
        if (self.values.contains(name)) {
            return error.LetRedeclaration;
        }
        if (self.constants.contains(name)) {
            return error.ConstantReassignment;
        }
        try self.values.put(name, value);
    }

    pub fn deinit(self: *Environment) void {
        // Clean up generators FIRST so they can safely promote to outer
        // before outer's lists are freed.
        if (self.outer) |outer| {
            for (self.generators.items) |gen| {
                outer.generators.append(outer.allocator, gen) catch {};
            }
        } else {
            // Drain with popOrNull: inner generators promoted via gen_env.deinit()
            // (which appends to self.generators) are also caught.
            while (self.generators.pop()) |gen| {
                if (@hasField(@TypeOf(gen.*), "gen_env")) {
                    if (gen.gen_env) |env_ptr| {
                        const env: *Environment = @alignCast(@ptrCast(env_ptr));
                        env.deinit();
                        gen.allocator.destroy(env);
                    }
                }
                gen.deinit();
            }
        }
        self.generators.deinit(self.allocator);

        if (self.outer) |outer| {
            for (self.owned_strings.items) |s| {
                outer.owned_strings.append(outer.allocator, s) catch {};
            }
        } else {
            for (self.owned_strings.items) |s| {
                self.allocator.free(s);
            }
        }
        self.owned_strings.deinit(self.allocator);

        if (self.outer) |outer| {
            for (self.arrays.items) |arr| {
                outer.arrays.append(outer.allocator, arr) catch {};
            }
        } else {
            for (self.arrays.items) |array_obj| {
                array_obj.deinit();
            }
        }
        self.arrays.deinit(self.allocator);

        if (self.outer) |outer| {
            for (self.iterators.items) |it| {
                outer.iterators.append(outer.allocator, it) catch {};
            }
        } else {
            for (self.iterators.items) |it| {
                it.deinit();
            }
        }
        self.iterators.deinit(self.allocator);

        if (self.outer) |outer| {
            for (self.objects.items) |obj| {
                outer.objects.append(outer.allocator, obj) catch {};
            }
        } else {
            for (self.objects.items) |obj| {
                obj.deinit();
            }
        }
        self.objects.deinit(self.allocator);

        if (self.outer) |outer| {
            for (self.symbols.items) |sym| {
                outer.symbols.append(outer.allocator, sym) catch {};
            }
        } else {
            for (self.symbols.items) |sym| {
                sym.deinit();
            }
        }
        self.symbols.deinit(self.allocator);

        self.exports.deinit();
        self.values.deinit();
        self.constants.deinit();
        self.functions.deinit();
        self.builtins.deinit();
        self.builtin_objects.deinit();
        self.timers.deinit();

        for (self.module_contents.items) |c| {
            self.allocator.free(c);
        }
        self.module_contents.deinit(self.allocator);

        for (self.module_arenas.items) |a| {
            a.deinit();
            self.allocator.destroy(a);
        }
        self.module_arenas.deinit(self.allocator);

        var cache_it = self.module_cache.iterator();
        while (cache_it.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.module_cache.deinit();
    }

    pub fn get(self: *Environment, name: []const u8) ?ast.Value {
        if (self.values.get(name)) |value| {
            return value;
        }
        if (self.outer) |outer| {
            return outer.get(name);
        }
        return null;
    }

    pub fn findEnv(self: *Environment, name: []const u8) ?*Environment {
        if (self.values.contains(name)) {
            return self;
        }
        if (self.outer) |outer| {
            return outer.findEnv(name);
        }
        return null;
    }

    pub fn setInScope(self: *Environment, name: []const u8, value: ast.Value) !void {
        if (self.findEnv(name)) |target| {
            if (target.constants.contains(name)) {
                return error.ConstantReassignment;
            }
            try target.values.put(name, value);
        } else {
            return error.UndefinedVariable;
        }
    }

    pub fn set(self: *Environment, name: []const u8, value: ast.Value) !void {
        if (self.isConstant(name)) {
            return error.ConstantReassignment;
        }
        try self.values.put(name, value);
    }

    pub fn setConstant(self: *Environment, name: []const u8, value: ast.Value) !void {
        if (self.values.contains(name)) {
            return error.ConstantReassignment;
        }
        try self.values.put(name, value);
        try self.constants.put(name, {});
    }

    pub fn isConstant(self: *Environment, name: []const u8) bool {
        if (self.constants.contains(name)) {
            return true;
        }
        if (self.outer) |outer| {
            return outer.isConstant(name);
        }
        return false;
    }
};
