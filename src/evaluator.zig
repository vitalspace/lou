const std = @import("std");
const ast = @import("ast.zig");
const builtins = @import("./builtins/builtins.zig");
const builtinsTypes = @import("./types/types.zig");

const builtin = @import("builtin");
const Io = std.Io;
const DEBUG_OPTIMIZATION = false;

inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
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
    owned_strings: std.ArrayList([]const u8),
    outer: ?*Environment,
    scope_kind: enum { block, function } = .function,
    exports: std.StringHashMap(ast.Value),
    module_dir: ?[]const u8,
    module_contents: std.ArrayList([]const u8),
    module_arenas: std.ArrayList(*std.heap.ArenaAllocator),
    module_cache: std.StringHashMap(ModuleCacheEntry),

    pub fn init(allocator: std.mem.Allocator, outer: ?*Environment) !Environment {
        return initWithIo(allocator, outer, null);
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
        const owned_strings = try std.ArrayList([]const u8).initCapacity(allocator, 0);

        const env = Environment{
            .allocator = allocator,
            .io = io,
            .values = std.StringHashMap(ast.Value).init(allocator),
            .constants = std.StringHashMap(void).init(allocator),
            .functions = std.StringHashMap(*ast.Node).init(allocator),
            .builtins = std.StringHashMap(builtinsTypes.BuiltinFn).init(allocator),
            .builtin_objects = try builtins.initBuiltinObjects(allocator),
            .timers = std.StringHashMap(i128).init(allocator),
            .arrays = arrays,
            .iterators = iterators,
            .objects = objects,
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
        // Check module cache for functions defined in imported modules
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
        // Bubble up owned_strings to parent (prevent dangling on return)
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

        // Bubble up arrays to parent
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

        // Bubble up iterators to parent
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

        // Bubble up objects to parent
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

        self.exports.deinit();
        self.values.deinit();
        self.constants.deinit();
        self.functions.deinit();
        self.builtins.deinit();
        self.builtin_objects.deinit();
        self.timers.deinit();

        // Free module file contents
        for (self.module_contents.items) |c| {
            self.allocator.free(c);
        }
        self.module_contents.deinit(self.allocator);

        // Free module parser arenas
        for (self.module_arenas.items) |a| {
            a.deinit();
            self.allocator.destroy(a);
        }
        self.module_arenas.deinit(self.allocator);

        // Free module cache entries (keys + values)
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

fn valuesEqual(left: ast.Value, right: ast.Value) bool {
    return switch (left) {
        .integer => |li| switch (right) {
            .integer => |ri| li == ri,
            .float => |rf| @as(f64, @floatFromInt(li)) == rf,
            else => false,
        },
        .float => |ln| switch (right) {
            .float => |rn| ln == rn,
            .integer => |ri| ln == @as(f64, @floatFromInt(ri)),
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
        .array => |la| switch (right) {
            .array => |ra| la == ra,
            else => false,
        },
        .object => |lo| switch (right) {
            .object => |ro| lo == ro,
            else => false,
        },
        .void => right == .void,
        .null => right == .null,
        .closure => right == .closure,
        .iterator => right == .iterator,
        .js_object => right == .js_object,
    };
}

fn getFloatValue(node: *ast.Node) ?f64 {
    return switch (node.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => null,
    };
}

// Optimized fast path for simple for loops with DEBUGGING
// Fast path optimization for array push loops
// Pattern: while (i < N) { arr.push(i); i++; }
// Fast path optimization for array push loops
// Pattern: while (i < N) { arr.push(i); i++; }
fn optimizeArrayPushLoop(w: @TypeOf(@as(ast.Node, undefined).WhileLoop), env: *Environment) !?ast.Value {
    // debugPrint("[ARRAY PUSH OPTIMIZATION] Attempting to optimize array push loop\n", .{});

    // 1. Check condition: i < N
    if (w.condition.* != .BinaryExpression) return null;
    const cond = w.condition.BinaryExpression;
    if (cond.operator != .LessThan) return null;
    if (cond.left.* != .Identifier) return null;
    if (cond.right.* != .FloatLiteral) return null;

    const loop_var = cond.left.Identifier.name;
    const limit = cond.right.FloatLiteral.value;

    // 2. Check body: must have exactly 2 statements
    if (w.body.* != .BlockStatement) return null;
    const body_stmts = w.body.BlockStatement.statements;
    if (body_stmts.len != 2) return null;

    // 3. First statement must be: arr.push(something)
    if (body_stmts[0].* != .MethodCall) return null;
    const method_call = body_stmts[0].MethodCall;

    if (method_call.object.* != .Identifier) return null;
    const array_name = method_call.object.Identifier.name;

    if (!std.mem.eql(u8, method_call.method, "push")) return null;
    if (method_call.arguments.len != 1) return null;

    // The argument to push should be the loop variable
    if (method_call.arguments[0].* != .Identifier) return null;
    const push_arg = method_call.arguments[0].Identifier.name;
    if (!std.mem.eql(u8, push_arg, loop_var)) return null;

    // 4. Second statement must be: i++ (as i = i + 1 or similar)
    var increment_value: f64 = 1.0;
    const inc_stmt = body_stmts[1];

    if (inc_stmt.* == .Assignment) {
        const assign = inc_stmt.Assignment;
        if (!std.mem.eql(u8, assign.name, loop_var)) return null;
        if (assign.value.* != .BinaryExpression) return null;

        const add_expr = assign.value.BinaryExpression;
        if (add_expr.operator != .Plus) return null;
        if (add_expr.left.* != .Identifier) return null;
        if (!std.mem.eql(u8, add_expr.left.Identifier.name, loop_var)) return null;
        increment_value = getFloatValue(add_expr.right) orelse return null;
    } else if (inc_stmt.* == .BinaryExpression) {
        const inc_expr = inc_stmt.BinaryExpression;
        if (inc_expr.operator != .Assign) return null;
        if (inc_expr.left.* != .Identifier) return null;
        if (!std.mem.eql(u8, inc_expr.left.Identifier.name, loop_var)) return null;
        if (inc_expr.right.* != .BinaryExpression) return null;

        const add_expr = inc_expr.right.BinaryExpression;
        if (add_expr.operator != .Plus) return null;
        if (add_expr.left.* != .Identifier) return null;
        if (!std.mem.eql(u8, add_expr.left.Identifier.name, loop_var)) return null;

        increment_value = getFloatValue(add_expr.right) orelse return null;
    } else {
        return null;
    }

    // 5. Get initial value from the loop variable in environment
    const initial_val = env.get(loop_var) orelse return null;
    if (initial_val != .float) return null;
    const initial_value = initial_val.float;

    const array_val = env.get(array_name) orelse return null;
    if (array_val != .array) return null;

    // debugPrint("[ARRAY PUSH OPTIMIZATION] ✓ Pattern matched!\n", .{});
    // debugPrint("[ARRAY PUSH OPTIMIZATION] Array: {s}, Loop: {d} to {d}, step {d}\n", .{ array_name, initial_value, limit, increment_value });

    // 6. Calculate number of iterations - FIXED VERSION
    const iterations_i64 = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
    const iterations = @as(usize, @intCast(iterations_i64));

    // debugPrint("[ARRAY PUSH OPTIMIZATION] Will push {d} elements\n", .{iterations});

    // 7. PRE-ALLOCATE ARRAY CAPACITY (KEY OPTIMIZATION!)
    const current_len = array_val.array.elements.items.len;
    const new_total_capacity = current_len + iterations;

    // Reserve exact capacity to avoid reallocations
    try array_val.array.elements.ensureTotalCapacity(array_val.array.allocator, new_total_capacity);

    // debugPrint("[ARRAY PUSH OPTIMIZATION] Pre-allocated capacity: {d}\n", .{new_total_capacity});

    // 8. Fast loop: push elements without reallocation
    var i = initial_value;
    while (i < limit) : (i += increment_value) {
        // appendAssumeCapacity is MUCH faster than append
        // because it doesn't check capacity on every iteration
        array_val.array.elements.appendAssumeCapacity(.{ .float = i });
    }

    debugPrint("[ARRAY PUSH OPTIMIZATION] ✓ Completed, pushed {d} elements\n", .{iterations});

    // 9. Update loop variable
    try env.values.put(loop_var, .{ .float = i });

    return .{ .float = 0.0 };
}

// Optimized fast path for simple for loops - FIXED VERSION
fn optimizeSimpleForLoop(f: @TypeOf(@as(ast.Node, undefined).ForLoop), env: *Environment, pre_limit: ?f64) !?ast.Value {
    std.debug.print("", .{}); // [OPT] START pre_limit={?}\n", .{pre_limit});
    
    // Check if init is: let identifier = number
    if (f.init == null) {
        std.debug.print("", .{}); // [OPT] init is null\n", .{});
        return null;
    }

    if (f.init.?.* != .VariableDeclaration and f.init.?.* != .LetDeclaration) {
        return null;
    }

    const init_name: []const u8 = if (f.init.?.* == .VariableDeclaration)
        f.init.?.VariableDeclaration.name
    else
        f.init.?.LetDeclaration.name;

    debugPrint("[OPTIMIZATION] init_name: {s}\n", .{init_name});

    const init_value_node: *ast.Node = if (f.init.?.* == .VariableDeclaration)
        f.init.?.VariableDeclaration.value
    else
        f.init.?.LetDeclaration.value;

    const initial_value: f64 = switch (init_value_node.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => {
            debugPrint("[OPTIMIZATION] FAIL: init value not number, it is: {s}\n", .{@tagName(init_value_node.*)});
            return null;
        },
    };
    debugPrint("[OPTIMIZATION] initial_value: {d}\n", .{initial_value});

    const loop_var = init_name;

// Check condition
    if (f.condition == null) {
        return null;
    }

    if (f.condition.?.* != .BinaryExpression) {
        return null;
    }

    const cond = f.condition.?.BinaryExpression;

    if (cond.left.* != .Identifier) {
        return null;
    }

    if (!std.mem.eql(u8, cond.left.Identifier.name, loop_var)) {
        return null;
    }

    const limit: f64 = pre_limit orelse blk: {
        if (cond.right.* != .FloatLiteral and cond.right.* != .IntegerLiteral) {
            std.debug.print("", .{}); // [OPT] FAIL: cond.right not literal\n", .{});
            return null;
        }
        break :blk switch (cond.right.*) {
            .FloatLiteral => |v| v.value,
            .IntegerLiteral => |v| @floatFromInt(v.value),
            else => return null,
        };
    };

    // Check operator
    const is_less_than = cond.operator == .LessThan;

    if (!is_less_than) {
        debugPrint("[OPTIMIZATION] FAILED: operator is not LessThan, it is: {any}\n", .{cond.operator});
        return null;
    }

    // ========== FIX: Handle increment as BinaryExpression ==========
    if (f.increment == null) {
        debugPrint("[OPTIMIZATION] FAILED: increment is null\n", .{});
        return null;
    }

    debugPrint("[OPTIMIZATION] Increment type: {s}\n", .{@tagName(f.increment.?.*)});

    // The increment can be EITHER Assignment OR BinaryExpression with Assign operator
    var increment_value: f64 = undefined;

    if (f.increment.?.* == .Assignment) {
        // Handle: i = i + 1 as Assignment node
        const inc = f.increment.?.Assignment;

        if (!std.mem.eql(u8, inc.name, loop_var)) {
            // debugPrint("[OPTIMIZATION] FAILED: increment var mismatch: {s} != {s}\n", .{ inc.name, loop_var });
            return null;
        }

        if (inc.value.* != .BinaryExpression) {
            // debugPrint("[OPTIMIZATION] FAILED: increment value is not BinaryExpression, it is: {s}\n", .{@tagName(inc.value.*)});
            return null;
        }

        const inc_expr = inc.value.BinaryExpression;

        if (inc_expr.operator != .Plus) {
            // debugPrint("[OPTIMIZATION] FAILED: increment operator is not Plus, it is: {any}\n", .{inc_expr.operator});
            return null;
        }

        if (inc_expr.left.* != .Identifier) {
            // debugPrint("[OPTIMIZATION] FAILED: increment left is not Identifier, it is: {s}\n", .{@tagName(inc_expr.left.*)});
            return null;
        }

        if (!std.mem.eql(u8, inc_expr.left.Identifier.name, loop_var)) {
            // debugPrint("[OPTIMIZATION] FAILED: increment left identifier mismatch\n", .{});
            return null;
        }

        increment_value = getFloatValue(inc_expr.right) orelse return null;
    } else if (f.increment.?.* == .BinaryExpression) {
        // Handle: i = i + 1 as BinaryExpression with Assign operator
        const inc_expr = f.increment.?.BinaryExpression;

        // debugPrint("[OPTIMIZATION] Increment is BinaryExpression with operator: {any}\n", .{inc_expr.operator});

        // Check if it's an assignment: i = ...
        if (inc_expr.operator != .Assign) {
            // debugPrint("[OPTIMIZATION] FAILED: increment operator is not Assign, it is: {any}\n", .{inc_expr.operator});
            return null;
        }

        // Left side must be the loop variable
        if (inc_expr.left.* != .Identifier) {
            // debugPrint("[OPTIMIZATION] FAILED: increment left is not Identifier, it is: {s}\n", .{@tagName(inc_expr.left.*)});
            return null;
        }

        if (!std.mem.eql(u8, inc_expr.left.Identifier.name, loop_var)) {
            // debugPrint("[OPTIMIZATION] FAILED: increment left identifier mismatch: {s} != {s}\n", .{ inc_expr.left.Identifier.name, loop_var });
            return null;
        }

        // Right side must be: i + number
        if (inc_expr.right.* != .BinaryExpression) {
            // debugPrint("[OPTIMIZATION] FAILED: increment right is not BinaryExpression, it is: {s}\n", .{@tagName(inc_expr.right.*)});
            return null;
        }

        const add_expr = inc_expr.right.BinaryExpression;

        if (add_expr.operator != .Plus) {
            // debugPrint("[OPTIMIZATION] FAILED: add operator is not Plus, it is: {any}\n", .{add_expr.operator});
            return null;
        }

        if (add_expr.left.* != .Identifier) {
            // debugPrint("[OPTIMIZATION] FAILED: add left is not Identifier, it is: {s}\n", .{@tagName(add_expr.left.*)});
            return null;
        }

        if (!std.mem.eql(u8, add_expr.left.Identifier.name, loop_var)) {
            // debugPrint("[OPTIMIZATION] FAILED: add left identifier mismatch: {s} != {s}\n", .{ add_expr.left.Identifier.name, loop_var });
            return null;
        }

        increment_value = getFloatValue(add_expr.right) orelse return null;
    } else {
        // debugPrint("[OPTIMIZATION] FAILED: increment is neither Assignment nor BinaryExpression, it is: {s}\n", .{@tagName(f.increment.?.*)});
        return null;
    }

    // debugPrint("[OPTIMIZATION] Increment OK: {d}\n", .{increment_value});

    // Check body
    if (f.body.* != .BlockStatement) {
        // debugPrint("[OPTIMIZATION] FAILED: body is not BlockStatement, it is: {s}\n", .{@tagName(f.body.*)});
        return null;
    }

    const body_statements = f.body.BlockStatement.statements;

    // OPTIMIZATION 1: Empty body — direct calculation
    if (body_statements.len == 0) {
        const iterations = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
        const final_value = initial_value + (@as(f64, @floatFromInt(iterations)) * increment_value);
        try env.values.put(loop_var, .{ .float = final_value });
        return .{ .float = 0.0 };
    }

    // OPTIMIZATION 2: Body is `acc = acc + X` or `acc += X` where X is loop_var or constant
    if (body_statements.len == 1) {
        const body_stmt = body_statements[0];
        std.debug.print("", .{}); // [OPT] body_statements.len=1, body_stmt type={s}\n", .{@tagName(body_stmt.*)});
        const iterations = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
        const n = @as(f64, @floatFromInt(iterations));

        // Detect: acc = acc + X (Assignment)
        if (body_stmt.* == .Assignment) {
            const assign = body_stmt.Assignment;
            const acc_name = assign.name;
            std.debug.print("", .{}); // [OPTIMIZATION] checking assignment for acc={s}\n", .{acc_name});

            if (assign.value.* == .BinaryExpression) {
                const add = assign.value.BinaryExpression;
                std.debug.print("", .{}); // [OPTIMIZATION] add operator={any}\n", .{add.operator});
                if (add.operator == .Plus and
                    add.left.* == .Identifier and
                    std.mem.eql(u8, add.left.Identifier.name, acc_name))
                {
                    std.debug.print("", .{}); // [OPTIMIZATION] Found acc=acc+X pattern, acc={s}\n", .{acc_name});
                    const acc_val = env.get(acc_name) orelse {
                        debugPrint("[OPTIMIZATION] acc {s} not in env\n", .{acc_name});
                        return null;
                    };
                    const acc_start = switch (acc_val) {
                        .integer => |v| @as(f64, @floatFromInt(v)),
                        .float => |v| v,
                        else => return null,
                    };

                    // acc = acc + loop_var
                    if (add.right.* == .Identifier and
                        std.mem.eql(u8, add.right.Identifier.name, loop_var))
                    {
                        const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                        try env.setInScope(acc_name, .{ .float = acc_start + sum });
                        try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                        return .{ .float = 0.0 };
                    }

                    // acc = acc + constant
                    if (getFloatValue(add.right)) |constant| {
                        try env.setInScope(acc_name, .{ .float = acc_start + n * constant });
                        try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                        return .{ .float = 0.0 };
                    }
                }
            }
        }

        // Detect: acc += X (BinaryExpression with PlusAssign)
        if (body_stmt.* == .BinaryExpression) {
            const be = body_stmt.BinaryExpression;
            if (be.operator == .PlusAssign and
                be.left.* == .Identifier)
            {
                const acc_name = be.left.Identifier.name;
                const acc_val = env.get(acc_name) orelse return null;
                const acc_start = switch (acc_val) {
                    .integer => |v| @as(f64, @floatFromInt(v)),
                    .float => |v| v,
                    else => return null,
                };

                // acc += loop_var
                if (be.right.* == .Identifier and
                    std.mem.eql(u8, be.right.Identifier.name, loop_var))
                {
                    const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                    try env.setInScope(acc_name, .{ .float = acc_start + sum });
                    try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                    return .{ .float = 0.0 };
                }

                // acc += constant
                if (getFloatValue(be.right)) |constant| {
                    try env.setInScope(acc_name, .{ .float = acc_start + n * constant });
                    try env.values.put(loop_var, .{ .float = initial_value + n * increment_value });
                    return .{ .float = 0.0 };
                }
            }
        }
    }

    return null;
}

// Optimized fast path for while loops - with direct calculation
fn optimizeSimpleWhileLoop(w: @TypeOf(@as(ast.Node, undefined).WhileLoop), env: *Environment) !?ast.Value {
    if (w.condition.* != .BinaryExpression) return null;
    const cond = w.condition.BinaryExpression;
    if (cond.operator != .LessThan) return null;
    if (cond.left.* != .Identifier) return null;
    if (cond.right.* != .FloatLiteral and cond.right.* != .IntegerLiteral) return null;

    const loop_var = cond.left.Identifier.name;
    const limit: f64 = switch (cond.right.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => unreachable,
    };

    if (w.body.* != .BlockStatement) return null;
    const body_stmts = w.body.BlockStatement.statements;

    if (body_stmts.len == 0) {
        const initial_val = env.get(loop_var) orelse return null;
        const initial_value: f64 = switch (initial_val) {
            .float => |v| v,
            .integer => |v| @floatFromInt(v),
            else => return null,
        };
        _ = initial_value;
        return .{ .float = 0.0 };
    }

    if (body_stmts.len != 1 and body_stmts.len != 2) return null;

    var increment_value: f64 = undefined;
    var acc_stmt: ?@TypeOf(body_stmts[0]) = null;

    if (body_stmts.len == 2) {
        for (body_stmts) |stmt| {
            const is_inc = switch (stmt.*) {
                .Assignment => |a| std.mem.eql(u8, a.name, loop_var),
                .BinaryExpression => |be| (be.operator == .Assign or
                    be.operator == .PlusAssign or be.operator == .MinusAssign) and
                    be.left.* == .Identifier and
                    std.mem.eql(u8, be.left.Identifier.name, loop_var),
                else => false,
            };
            if (is_inc) {
                if (stmt.* == .Assignment) {
                    const assign = stmt.Assignment;
                    if (assign.value.* != .BinaryExpression) return null;
                    const ae = assign.value.BinaryExpression;
                    if (ae.operator != .Plus) return null;
                    if (ae.left.* != .Identifier) return null;
                    if (!std.mem.eql(u8, ae.left.Identifier.name, loop_var)) return null;
                    increment_value = getFloatValue(ae.right) orelse return null;
                } else {
                    const be = stmt.BinaryExpression;
                    if (be.operator == .Assign) {
                        if (be.right.* != .BinaryExpression) return null;
                        const add = be.right.BinaryExpression;
                        if (add.operator != .Plus) return null;
                        if (add.left.* != .Identifier) return null;
                        if (!std.mem.eql(u8, add.left.Identifier.name, loop_var)) return null;
                        increment_value = getFloatValue(add.right) orelse return null;
                    } else if (be.operator == .PlusAssign) {
                        increment_value = getFloatValue(be.right) orelse return null;
                    } else if (be.operator == .MinusAssign) {
                        increment_value = getFloatValue(be.right) orelse return null;
                        increment_value = -increment_value;
                    } else {
                        return null;
                    }
                }
            } else {
                acc_stmt = stmt;
            }
        }
    } else {
        if (body_stmts[0].* == .Assignment) {
            const assign = body_stmts[0].Assignment;
            if (!std.mem.eql(u8, assign.name, loop_var)) return null;
            if (assign.value.* != .BinaryExpression) return null;
            const ae = assign.value.BinaryExpression;
            if (ae.operator != .Plus) return null;
            if (ae.left.* != .Identifier) return null;
            if (!std.mem.eql(u8, ae.left.Identifier.name, loop_var)) return null;
            increment_value = getFloatValue(ae.right) orelse return null;
        } else if (body_stmts[0].* == .BinaryExpression) {
            const be = body_stmts[0].BinaryExpression;
            if (be.operator != .Assign) return null;
            if (be.left.* != .Identifier) return null;
            if (!std.mem.eql(u8, be.left.Identifier.name, loop_var)) return null;
            if (be.right.* != .BinaryExpression) return null;
            const add = be.right.BinaryExpression;
            if (add.operator != .Plus) return null;
            if (add.left.* != .Identifier) return null;
            if (!std.mem.eql(u8, add.left.Identifier.name, loop_var)) return null;
            increment_value = getFloatValue(add.right) orelse return null;
        } else {
            return null;
        }
    }

    const initial_val = env.get(loop_var) orelse return null;
    const initial_value: f64 = switch (initial_val) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        else => return null,
    };

    const iterations = @divFloor(@as(i64, @intFromFloat(limit - initial_value)), @as(i64, @intFromFloat(increment_value)));
    const final_value = initial_value + (@as(f64, @floatFromInt(iterations)) * increment_value);
    const n = @as(f64, @floatFromInt(iterations));

    try env.values.put(loop_var, .{ .float = final_value });

    if (acc_stmt) |stmt| {
        if (stmt.* == .Assignment) {
            const assign = stmt.Assignment;
            if (assign.value.* == .BinaryExpression) {
                const add = assign.value.BinaryExpression;
                if (add.operator == .Plus and
                    add.left.* == .Identifier and
                    std.mem.eql(u8, add.left.Identifier.name, assign.name))
                {
                    const acc_val = env.get(assign.name) orelse return .{ .float = 0.0 };
                    const acc_start = switch (acc_val) {
                        .integer => |v| @as(f64, @floatFromInt(v)),
                        .float => |v| v,
                        else => return .{ .float = 0.0 },
                    };
                    if (add.right.* == .Identifier and std.mem.eql(u8, add.right.Identifier.name, loop_var)) {
                        const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                        try env.values.put(assign.name, .{ .float = acc_start + sum });
                    } else if (getFloatValue(add.right)) |constant| {
                        try env.values.put(assign.name, .{ .float = acc_start + n * constant });
                    }
                }
            }
        } else if (stmt.* == .BinaryExpression) {
            const be = stmt.BinaryExpression;
            if (be.operator == .PlusAssign and be.left.* == .Identifier) {
                const acc_name = be.left.Identifier.name;
                const acc_val = env.get(acc_name) orelse return .{ .float = 0.0 };
                const acc_start = switch (acc_val) {
                    .integer => |v| @as(f64, @floatFromInt(v)),
                    .float => |v| v,
                    else => return .{ .float = 0.0 },
                };
                if (be.right.* == .Identifier and std.mem.eql(u8, be.right.Identifier.name, loop_var)) {
                    const sum = n * (initial_value + (initial_value + (n - 1.0) * increment_value)) / 2.0;
                    try env.values.put(acc_name, .{ .float = acc_start + sum });
                } else if (getFloatValue(be.right)) |constant| {
                    try env.values.put(acc_name, .{ .float = acc_start + n * constant });
                }
            }
        }
    }

    return .{ .float = 0.0 };
}

pub fn evaluate(node: *ast.Node, env: *Environment) !ast.Value {
    switch (node.*) {
        .IntegerLiteral => |i| return .{ .integer = i.value },
        .FloatLiteral => |f| return .{ .float = f.value },
        .StringLiteral => |s| return .{ .string = s.value },
        .BooleanLiteral => |b| return .{ .boolean = b.value },
        .NullLiteral => return .{ .null = {} },
        .VoidLiteral => return .{ .void = {} },
        .ArrayLiteral => |a| {
            const array_obj = try ast.ArrayObject.init(env.allocator);
            errdefer array_obj.deinit();

            try array_obj.elements.ensureTotalCapacityPrecise(env.allocator, a.elements.len);

            for (a.elements) |elem| {
                const val = try evaluate(elem, env);
                array_obj.elements.appendAssumeCapacity(val);
            }

            try env.arrays.append(env.allocator, array_obj);

            return .{ .array = array_obj };
        },
        .ObjectLiteral => |o| {
            const obj = try ast.ObjectValue.init(env.allocator);
            errdefer obj.deinit();

            for (o.properties) |prop| {
                const val = try evaluate(prop.value, env);
                try obj.properties.put(prop.key, val);
            }

            try env.objects.append(env.allocator, obj);
            return .{ .js_object = obj };
        },
        .ArrayIndex => |a| {
            const array_val = try evaluate(a.array, env);
            if (array_val == .iterator) {
                return .{ .void = {} };
            }
            if (array_val == .js_object) {
                const index_val = try evaluate(a.index, env);
                const key = switch (index_val) {
                    .string => |s| s,
                    else => return error.InvalidIndex,
                };
                if (array_val.js_object.properties.get(key)) |v| {
                    return v;
                }
                return .{ .void = {} };
            }
            if (array_val != .array) {
                return error.NotAnArray;
            }
            const index_val = try evaluate(a.index, env);
            const index: usize = switch (index_val) {
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                else => return error.InvalidIndex,
            };
            if (array_val.array.get(index)) |value| {
                return value;
            } else {
                return error.IndexOutOfBounds;
            }
        },
        .PropertySet => |p| {
            const object_val = try evaluate(p.object, env);
            if (object_val != .js_object) {
                return error.InvalidAssignmentTarget;
            }
            const val = try evaluate(p.value, env);
            try object_val.js_object.properties.put(p.key, val);
            return val;
        },
        .Identifier => |i| {
            if (env.get(i.name)) |value| {
                return value;
            } else if (env.getFunction(i.name)) |_| {
                return .{ .string = i.name };
            } else {
                return error.UndefinedVariable;
            }
        },
        .BinaryExpression => |b| {
            if (b.operator == .Assign) {
                if (b.left.* == .MemberAccess) {
                    const obj_val = try evaluate(b.left.MemberAccess.object, env);
                    if (obj_val != .js_object) return error.InvalidAssignment;
                    const val = try evaluate(b.right, env);
                    try obj_val.js_object.properties.put(b.left.MemberAccess.property, val);
                    return val;
                }
                if (b.left.* != .Identifier) {
                    return error.InvalidAssignment;
                }
                const name = b.left.Identifier.name;
                const value = try evaluate(b.right, env);
                try env.setInScope(name, value);
                return value;
            }

            // Compound assignment operators: x += y  =>  x = x + y
            if (b.operator == .PlusAssign or b.operator == .MinusAssign or
                b.operator == .MultiplyAssign or b.operator == .DivideAssign or
                b.operator == .ModuloAssign)
            {
                if (b.left.* != .Identifier) {
                    return error.InvalidAssignment;
                }
                const name = b.left.Identifier.name;
                const current_val = env.get(name) orelse return error.UndefinedVariable;
                const right_val = try evaluate(b.right, env);
                const result = switch (b.operator) {
                    .PlusAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv + rv },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) + rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv + @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv + rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .MinusAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv - rv },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) - rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv - @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv - rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .MultiplyAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = lv * rv },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) * rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv * @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv * rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .DivideAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) / @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = @as(f64, @floatFromInt(lv)) / rv },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = lv / @as(f64, @floatFromInt(rv)) },
                            .float => |rv| ast.Value{ .float = lv / rv },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    .ModuloAssign => switch (current_val) {
                        .integer => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .integer = @mod(lv, rv) },
                            .float => |rv| ast.Value{ .float = @mod(@as(f64, @floatFromInt(lv)), rv) },
                            else => return error.TypeMismatch,
                        },
                        .float => |lv| switch (right_val) {
                            .integer => |rv| ast.Value{ .float = @mod(lv, @as(f64, @floatFromInt(rv))) },
                            .float => |rv| ast.Value{ .float = @mod(lv, rv) },
                            else => return error.TypeMismatch,
                        },
                        else => return error.TypeMismatch,
                    },
                    else => unreachable,
                };
                try env.setInScope(name, result);
                return result;
            }

            // Logical NOT: !x  (parsed as BinaryExpression with left=false, op=Not, right=x)
            if (b.operator == .Not) {
                const val = try evaluate(b.right, env);
                const result = switch (val) {
                    .boolean => |bv| !bv,
                    .integer => |iv| iv == 0,
                    .float => |fv| fv == 0.0,
                    .string => |sv| sv.len == 0,
                    .void => true,
                    else => false,
                };
                return .{ .boolean = result };
            }

            // Bitwise NOT: ~x  (parsed as BinaryExpression with left=0, op=BitNot, right=x)
            if (b.operator == .BitNot) {
                const val = try evaluate(b.right, env);
                return switch (val) {
                    .integer => |iv| .{ .integer = ~iv },
                    .float => |fv| .{ .integer = ~@as(i64, @intFromFloat(fv)) },
                    else => return error.TypeMismatch,
                };
            }

            // Nullish coalescing: x ?? y (only null/undefined trigger fallback, not falsy values)
            if (b.operator == .Nullish) {
                const left = try evaluate(b.left, env);
                return switch (left) {
                    .void, .null => try evaluate(b.right, env),
                    else => left,
                };
            }

            // Pipeline: x |> f
            if (b.operator == .Pipe) {
                const left_val = try evaluate(b.left, env);
                switch (b.right.*) {
                    .Identifier => |ident| {
                        if (env.getBuiltin(ident.name)) |builtin_fn| {
                            var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                            defer args.deinit(env.allocator);
                            try args.append(env.allocator, left_val);
                            const result = builtin_fn(args.items, env);
                            return switch (result) {
                                .value => |val| val,
                                .void => .{ .float = 0.0 },
                            };
                        }
                        const func_node = env.getFunction(ident.name) orelse return error.UndefinedFunction;
                        var func_env = try Environment.init(env.allocator, env);
                        defer func_env.deinit();
                        if (func_node.* == .FunctionDeclaration) {
                            const func = func_node.FunctionDeclaration;
                            if (func.parameters.len != 1) return error.InvalidArgumentCount;
                            try func_env.set(func.parameters[0], left_val);
                            return try evaluate(func.body, &func_env);
                        } else if (func_node.* == .ArrowFunction) {
                            const func = func_node.ArrowFunction;
                            if (func.parameters.len != 1) return error.InvalidArgumentCount;
                            try func_env.set(func.parameters[0], left_val);
                            return try evaluate(func.body, &func_env);
                        }
                        return error.NotAFunction;
                    },
                    .FunctionCall => |fc| {
                        var func_env = try Environment.init(env.allocator, env);
                        defer func_env.deinit();
                        const func_node = env.getFunction(fc.name) orelse {
                            if (env.getBuiltin(fc.name)) |builtin_fn| {
                                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                                defer args.deinit(env.allocator);
                                try args.append(env.allocator, left_val);
                                for (fc.arguments) |arg| {
                                    const val = try evaluate(arg, env);
                                    try args.append(env.allocator, val);
                                }
                                const result = builtin_fn(args.items, env);
                                return switch (result) {
                                    .value => |val| val,
                                    .void => .{ .float = 0.0 },
                                };
                            }
                            return error.UndefinedFunction;
                        };
                        if (func_node.* == .FunctionDeclaration) {
                            const func = func_node.FunctionDeclaration;
                            try func_env.set(func.parameters[0], left_val);
                            for (func.parameters[1..], 0..) |param, idx| {
                                if (idx < fc.arguments.len) {
                                    const val = try evaluate(fc.arguments[idx], env);
                                    try func_env.set(param, val);
                                }
                            }
                            return try evaluate(func.body, &func_env);
                        } else if (func_node.* == .ArrowFunction) {
                            const func = func_node.ArrowFunction;
                            try func_env.set(func.parameters[0], left_val);
                            for (func.parameters[1..], 0..) |param, idx| {
                                if (idx < fc.arguments.len) {
                                    const val = try evaluate(fc.arguments[idx], env);
                                    try func_env.set(param, val);
                                }
                            }
                            return try evaluate(func.body, &func_env);
                        }
                        return error.NotAFunction;
                    },
                    else => return error.InvalidPipeline,
                }
            }

            // Equality operators (before arithmetic)
            if (b.operator == .Equal or b.operator == .NotEqual or
                b.operator == .StrictEqual or b.operator == .StrictNotEqual)
            {
                const left = try evaluate(b.left, env);
                const right = try evaluate(b.right, env);
                const result = switch (b.operator) {
                    .Equal, .StrictEqual => valuesEqual(left, right),
                    .NotEqual, .StrictNotEqual => !valuesEqual(left, right),
                    else => unreachable,
                };
                return .{ .boolean = result };
            }

            // Logical operators: &&, ||
            if (b.operator == .And or b.operator == .Or) {
                const left = try evaluate(b.left, env);
                const left_truthy = switch (left) {
                    .boolean => |bv| bv,
                    .integer => |iv| iv != 0,
                    .float => |fv| fv != 0.0,
                    .string => |sv| sv.len > 0,
                    .void => false,
                    else => true,
                };

                if (b.operator == .And) {
                    if (!left_truthy) return .{ .boolean = false };
                    const right = try evaluate(b.right, env);
                    const right_truthy = switch (right) {
                        .boolean => |bv| bv,
                        .integer => |iv| iv != 0,
                        .float => |fv| fv != 0.0,
                        .string => |sv| sv.len > 0,
                        .void => false,
                        else => true,
                    };
                    return .{ .boolean = right_truthy };
                } else {
                    if (left_truthy) return .{ .boolean = true };
                    const right = try evaluate(b.right, env);
                    const right_truthy = switch (right) {
                        .boolean => |bv| bv,
                        .integer => |iv| iv != 0,
                        .float => |fv| fv != 0.0,
                        .string => |sv| sv.len > 0,
                        .void => false,
                        else => true,
                    };
                    return .{ .boolean = right_truthy };
                }
            }

            const left = try evaluate(b.left, env);
            const right = try evaluate(b.right, env);

            // String concatenation
            if (b.operator == .Plus and (left == .string or right == .string)) {
                var buf = std.ArrayList(u8).initCapacity(env.allocator, 64) catch return error.OutOfMemory;
                defer buf.deinit(env.allocator);
                switch (left) {
                    .string => |s| buf.appendSlice(env.allocator, s) catch return error.OutOfMemory,
                    .integer => |i| {
                        var tmp: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
                        buf.appendSlice(env.allocator, written) catch return error.OutOfMemory;
                    },
                    .float => |f| {
                        var tmp: [64]u8 = undefined;
                        const written = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
                        buf.appendSlice(env.allocator, written) catch return error.OutOfMemory;
                    },
                    .boolean => |bl| {
                        const s = if (bl) "true" else "false";
                        buf.appendSlice(env.allocator, s) catch return error.OutOfMemory;
                    },
                    .void => buf.appendSlice(env.allocator, "undefined") catch return error.OutOfMemory,
                    else => buf.appendSlice(env.allocator, "[object]") catch return error.OutOfMemory,
                }
                switch (right) {
                    .string => |s| buf.appendSlice(env.allocator, s) catch return error.OutOfMemory,
                    .integer => |i| {
                        var tmp: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return error.OutOfMemory;
                        buf.appendSlice(env.allocator, written) catch return error.OutOfMemory;
                    },
                    .float => |f| {
                        var tmp: [64]u8 = undefined;
                        const written = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return error.OutOfMemory;
                        buf.appendSlice(env.allocator, written) catch return error.OutOfMemory;
                    },
                    .boolean => |bl| {
                        const s = if (bl) "true" else "false";
                        buf.appendSlice(env.allocator, s) catch return error.OutOfMemory;
                    },
                    .void => buf.appendSlice(env.allocator, "undefined") catch return error.OutOfMemory,
                    else => buf.appendSlice(env.allocator, "[object]") catch return error.OutOfMemory,
                }
                const owned = buf.toOwnedSlice(env.allocator) catch return error.OutOfMemory;
                env.owned_strings.append(env.allocator, owned) catch {};
                return .{ .string = owned };
            }

            // Si ambos son enteros, retornar entero
            if (left == .integer and right == .integer) {
                const left_int = left.integer;
                const right_int = right.integer;
                return switch (b.operator) {
                    .Plus => .{ .integer = left_int + right_int },
                    .Minus => .{ .integer = left_int - right_int },
                    .Multiply => .{ .integer = left_int * right_int },
                    .Divide => .{ .float = @as(f64, @floatFromInt(left_int)) / @as(f64, @floatFromInt(right_int)) },
                    .Modulo => .{ .integer = @mod(left_int, right_int) },
                    .LessThan => .{ .boolean = left_int < right_int },
                    .LessThanOrEqual => .{ .boolean = left_int <= right_int },
                    .GreaterThan => .{ .boolean = left_int > right_int },
                    .GreaterThanOrEqual => .{ .boolean = left_int >= right_int },
                    .Equal => .{ .boolean = left_int == right_int },
                    .NotEqual => .{ .boolean = left_int != right_int },
                    .StrictEqual => .{ .boolean = left_int == right_int },
                    .StrictNotEqual => .{ .boolean = left_int != right_int },
                    .BitAnd => .{ .integer = left_int & right_int },
                    .BitOr => .{ .integer = left_int | right_int },
                    .BitXor => .{ .integer = left_int ^ right_int },
                    .LeftShift => .{ .integer = left_int << @intCast(right_int) },
                    .RightShift => .{ .integer = left_int >> @intCast(right_int) },
                    else => return error.UnsupportedOperator,
                };
            }

            // Si alguno es número (f64), convertir ambos a f64
            const left_num = if (left == .integer) @as(f64, @floatFromInt(left.integer)) else left.float;
            const right_num = if (right == .integer) @as(f64, @floatFromInt(right.integer)) else right.float;

            return switch (b.operator) {
                .Plus => .{ .float = left_num + right_num },
                .Minus => .{ .float = left_num - right_num },
                .Multiply => .{ .float = left_num * right_num },
                .Divide => .{ .float = left_num / right_num },
                .Modulo => .{ .float = @mod(left_num, right_num) },
                .LessThan => .{ .boolean = left_num < right_num },
                .LessThanOrEqual => .{ .boolean = left_num <= right_num },
                .GreaterThan => .{ .boolean = left_num > right_num },
                .GreaterThanOrEqual => .{ .boolean = left_num >= right_num },
                .Equal => .{ .boolean = left_num == right_num },
                .NotEqual => .{ .boolean = left_num != right_num },
                .StrictEqual => .{ .boolean = left_num == right_num },
                .StrictNotEqual => .{ .boolean = left_num != right_num },
                .BitAnd => .{ .integer = @as(i64, @intFromFloat(left_num)) & @as(i64, @intFromFloat(right_num)) },
                .BitOr => .{ .integer = @as(i64, @intFromFloat(left_num)) | @as(i64, @intFromFloat(right_num)) },
                .BitXor => .{ .integer = @as(i64, @intFromFloat(left_num)) ^ @as(i64, @intFromFloat(right_num)) },
                .LeftShift => .{ .integer = @as(i64, @intFromFloat(left_num)) << @intCast(@as(i64, @intFromFloat(right_num))) },
                .RightShift => .{ .integer = @as(i64, @intFromFloat(left_num)) >> @intCast(@as(i64, @intFromFloat(right_num))) },
                else => return error.UnsupportedOperator,
            };
        },
        .Assignment => |a| {
            const value = try evaluate(a.value, env);
            try env.setInScope(a.name, value);
            return value;
        },
        .ConstantDeclaration => |c| {
            if (c.value.* == .FunctionDeclaration or c.value.* == .ArrowFunction) {
                try env.setFunction(c.name, c.value);
                try env.setConstant(c.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(c.value, env);
                try env.setConstant(c.name, value);
                return value;
            }
        },
        .VariableDeclaration => |v| {
            if (v.value.* == .FunctionDeclaration or v.value.* == .ArrowFunction) {
                try env.setFunction(v.name, v.value);
                try env.setVar(v.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(v.value, env);
                try env.setVar(v.name, value);
                return value;
            }
        },
        .LetDeclaration => |v| {
            if (v.value.* == .FunctionDeclaration or v.value.* == .ArrowFunction) {
                try env.setFunction(v.name, v.value);
                try env.setLet(v.name, .{ .float = 0.0 });
                return .{ .float = 0.0 };
            } else {
                const value = try evaluate(v.value, env);
                try env.setLet(v.name, value);
                return value;
            }
        },
        .BlockStatement => |b| {
            var has_block_scope = false;
            for (b.statements) |stmt| {
                if (stmt.* == .LetDeclaration or stmt.* == .ConstantDeclaration) {
                    has_block_scope = true;
                    break;
                }
            }

            if (!has_block_scope) {
                var result: ast.Value = .{ .float = 0.0 };
                for (b.statements) |stmt| {
                    if (stmt.* == .ReturnStatement) {
                        const ret_stmt = stmt.ReturnStatement;
                        if (ret_stmt.value) |val| {
                            return try evaluate(val, env);
                        } else {
                            return .{ .void = {} };
                        }
                    }
                    result = try evaluate(stmt, env);
                }
                return result;
            }

            var block_env = try Environment.initBlock(env.allocator, env);
            defer block_env.deinit();

            var result: ast.Value = .{ .float = 0.0 };
            for (b.statements) |stmt| {
                if (stmt.* == .ReturnStatement) {
                    const ret_stmt = stmt.ReturnStatement;
                    if (ret_stmt.value) |val| {
                        return try evaluate(val, &block_env);
                    } else {
                        return .{ .void = {} };
                    }
                }

                result = try evaluate(stmt, &block_env);
            }
            return result;
        },
        .ForLoop => |f| {
            // Pre-evaluate condition limit for non-literal RHS
            var pre_limit: ?f64 = null;
            if (f.condition) |cond| {
                if (cond.* == .BinaryExpression) {
                    const be = cond.BinaryExpression;
                    if (be.operator == .LessThan and be.left.* == .Identifier) {
                        pre_limit = switch (be.right.*) {
                            .FloatLiteral => |v| v.value,
                            .IntegerLiteral => |v| @floatFromInt(v.value),
                            else => null,
                        };
                        if (pre_limit == null) {
                            const val = evaluate(be.right, env) catch null;
                            if (val) |v| {
                                pre_limit = switch (v) {
                                    .float => |fval| fval,
                                    .integer => |ival| @floatFromInt(ival),
                                    else => null,
                                };
                            }
                        }
                    }
                }
            }
            debugPrint("[OPTIMIZATION] Trying optimizeSimpleForLoop, pre_limit={?}\n", .{pre_limit});
            if (try optimizeSimpleForLoop(f, env, pre_limit)) |result| {
                debugPrint("[OPTIMIZATION] SUCCESS!\n", .{});
                return result;
            }
            debugPrint("[OPTIMIZATION] FAILED - falling through\n", .{});

            const is_let_init = f.init != null and f.init.?.* == .LetDeclaration;

            var loop_env_buf: Environment = undefined;
            const eval_env: *Environment = if (is_let_init) blk: {
                loop_env_buf = try Environment.initBlock(env.allocator, env);
                break :blk &loop_env_buf;
            } else env;
            defer if (is_let_init) loop_env_buf.deinit();

            var result: ast.Value = .{ .float = 0.0 };

            if (f.init) |init| {
                _ = try evaluate(init, eval_env);
            }

            const loop_var_name: ?[]const u8 = if (f.condition) |cond|
                if (cond.* == .BinaryExpression)
                    if (cond.BinaryExpression.left.* == .Identifier)
                        cond.BinaryExpression.left.Identifier.name
                    else
                        null
                else
                    null
            else
                null;

            while (true) {
                if (pre_limit != null and loop_var_name != null) {
                    const current_val = eval_env.get(loop_var_name.?) orelse break;
                    const current_f: f64 = switch (current_val) {
                        .float => |v| v,
                        .integer => |v| @floatFromInt(v),
                        else => break,
                    };
                    if (current_f >= pre_limit.?) break;
                } else if (f.condition) |cond| {
                    const cond_val = try evaluate(cond, eval_env);
                    const is_false = switch (cond_val) {
                        .boolean => |bv| !bv,
                        .float => |fv| fv == 0.0,
                        .integer => |iv| iv == 0,
                        else => false,
                    };
                    if (is_false) break;
                }

                result = try evaluate(f.body, eval_env);

                if (f.increment) |inc| {
                    _ = try evaluate(inc, eval_env);
                }
            }

            return result;
        },
        .WhileLoop => |w| {
            if (try optimizeArrayPushLoop(w, env)) |result| {
                return result;
            }

            if (try optimizeSimpleWhileLoop(w, env)) |result| {
                return result;
            }

            var w_pre_limit: ?f64 = null;
            if (w.condition.* == .BinaryExpression) {
                const be = w.condition.BinaryExpression;
                if (be.left.* == .Identifier) {
                    w_pre_limit = switch (be.right.*) {
                        .FloatLiteral => |v| v.value,
                        .IntegerLiteral => |v| @floatFromInt(v.value),
                        else => null,
                    };
                    if (w_pre_limit == null) {
                        const val = evaluate(be.right, env) catch null;
                        if (val) |v| {
                            w_pre_limit = switch (v) {
                                .float => |fval| fval,
                                .integer => |ival| @floatFromInt(ival),
                                else => null,
                            };
                        }
                    }
                }
            }

            const w_loop_var: ?[]const u8 = if (w_pre_limit != null)
                if (w.condition.* == .BinaryExpression)
                    if (w.condition.BinaryExpression.left.* == .Identifier)
                        w.condition.BinaryExpression.left.Identifier.name
                    else
                        null
                else
                    null
            else
                null;

            var result: ast.Value = .{ .float = 0.0 };

            while (true) {
                if (w_loop_var) |vn| {
                    const current_val = env.get(vn) orelse break;
                    const current_f: f64 = switch (current_val) {
                        .float => |v| v,
                        .integer => |v| @floatFromInt(v),
                        else => break,
                    };
                    if (w.condition.* == .BinaryExpression and w.condition.BinaryExpression.operator == .LessThanOrEqual) {
                        if (current_f > w_pre_limit.?) break;
                    } else {
                        if (current_f >= w_pre_limit.?) break;
                    }
                } else {
                    const cond_val = try evaluate(w.condition, env);
                    const is_false = switch (cond_val) {
                        .boolean => |bv| !bv,
                        .float => |fv| fv == 0.0,
                        .integer => |iv| iv == 0,
                        else => false,
                    };
                    if (is_false) break;
                }

                result = try evaluate(w.body, env);
            }

            return result;
        },
        .IfStatement => |i| {
            const cond_val = try evaluate(i.condition, env);
            const is_truthy = switch (cond_val) {
                .boolean => |b| b,
                .float => |f| f != 0.0,
                .integer => |iv| iv != 0,
                .string => |s| s.len > 0,
                .void => false,
                else => true,
            };

            // debugPrint("[IF] Condition is truthy: {}\n", .{is_truthy});

            if (is_truthy) {
                // debugPrint("[IF] Evaluating consequence\n", .{});
                const result = try evaluate(i.consequence, env);
                // debugPrint("[IF] Consequence result: {any}\n", .{result});
                return result;
            } else if (i.alternative) |alt| {
                // debugPrint("[IF] Evaluating alternative\n", .{});
                const result = try evaluate(alt, env);
                // debugPrint("[IF] Alternative result: {any}\n", .{result});
                return result;
            } else {
                // debugPrint("[IF] No consequence or alternative\n", .{});
                return .{ .float = 0.0 };
            }
        },
        .ReturnStatement => |r| {
            // This case is primarily handled in BlockStatement for proper control flow
            // But we keep this as a fallback for standalone return statements
            if (r.value) |val| {
                return try evaluate(val, env);
            } else {
                return .{ .void = {} };
            }
        },
        .FunctionDeclaration => |f| {
            try env.setFunction(f.name, node);
            return .{ .float = 0.0 };
        },
        .FunctionCall => |f| {
            if (env.getBuiltin(f.name)) |builtin_fn| {
                var stack_buf: [16]ast.Value = undefined;
                const total = f.arguments.len;
                if (total <= 16) {
                    for (f.arguments, 0..) |arg, idx| {
                        stack_buf[idx] = try evaluate(arg, env);
                    }
                    const result = builtin_fn(stack_buf[0..total], env);
                    return switch (result) {
                        .value => |val| val,
                        .void => .{ .float = 0.0 },
                    };
                }
                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                defer args.deinit(env.allocator);
                for (f.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try args.append(env.allocator, val);
                }
                const result = builtin_fn(args.items, env);
                args.clearAndFree(env.allocator);
                return switch (result) {
                    .value => |val| val,
                    .void => .{ .float = 0.0 },
                };
            }

            const func_node = env.getFunctionWithModuleFallback(f.name) orelse return error.UndefinedFunction;

            var func_env = try Environment.init(env.allocator, env);
            defer func_env.deinit();

            if (func_node.* == .FunctionDeclaration) {
                const func = func_node.FunctionDeclaration;
                for (func.parameters, f.arguments) |param, arg| {
                    const arg_val = try evaluate(arg, env);
                    try func_env.set(param, arg_val);
                }
                return try evaluate(func.body, &func_env);
            } else if (func_node.* == .ArrowFunction) {
                const func = func_node.ArrowFunction;
                for (func.parameters, f.arguments) |param, arg| {
                    const arg_val = try evaluate(arg, env);
                    try func_env.set(param, arg_val);
                }
                return try evaluate(func.body, &func_env);
            } else {
                return error.NotAFunction;
            }
        },
        .ArrowFunction => {
            return .{ .float = 0.0 };
        },
        .MemberAccess => |m| {
            const value = try evaluate(m.object, env);

            if (value == .array) {
                if (std.mem.eql(u8, m.property, "length")) {
                    return .{ .integer = @intCast(value.array.elements.items.len) };
                }

                const builtin_obj = env.getBuiltinObject("Array") orelse {
                    return error.UndefinedObject;
                };

                if (builtin_obj.getMethod(m.property)) |_| {
                    return .{ .object = @ptrCast(builtin_obj) };
                } else {
                    return error.UndefinedMethod;
                }
            } else if (value == .iterator) {
                return .{ .void = {} };
            } else if (value == .js_object) {
                if (value.js_object.properties.get(m.property)) |v| {
                    return v;
                }
                return .{ .void = {} };
            } else {
                return error.InvalidMemberAccess;
            }
        },
        .MethodCall => |m| {
            if (m.object.* == .Identifier) {
                const obj_name = m.object.Identifier.name;

                if (env.get(obj_name)) |value| {
                    if (value == .array) {
                        const builtin_obj = env.getBuiltinObject("Array") orelse {
                            return error.UndefinedObject;
                        };
                        const method = builtin_obj.getMethod(m.method) orelse {
                            return error.UndefinedMethod;
                        };
                        var stack_buf: [16]ast.Value = undefined;
                        stack_buf[0] = value;
                        const total = 1 + m.arguments.len;
                        if (total <= 16) {
                            for (m.arguments, 0..) |arg, idx| {
                                stack_buf[idx + 1] = try evaluate(arg, env);
                            }
                            const result = method(stack_buf[0..total], env);
                            return switch (result) {
                                .value => |val| val,
                                .void => .void,
                            };
                        }
                        var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                        defer args.deinit(env.allocator);
                        for (m.arguments) |arg| {
                            const val = try evaluate(arg, env);
                            try args.append(env.allocator, val);
                        }
                        var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                        defer method_args.deinit(env.allocator);
                        try method_args.append(env.allocator, value);
                        try method_args.appendSlice(env.allocator, args.items);
                        const result = method(method_args.items, env);
                        args.clearAndFree(env.allocator);
                        method_args.clearAndFree(env.allocator);
                        return switch (result) {
                            .value => |val| val,
                            .void => .void,
                        };
                    } else if (value == .iterator) {
                        if (std.mem.eql(u8, m.method, "next")) {
                            return value.iterator.next(env.allocator, &env.arrays, &env.objects);
                        }
                        return .{ .void = {} };
                    }
                }

                const builtin_obj = env.getBuiltinObject(obj_name) orelse {
                    return error.UndefinedObject;
                };
                const method = builtin_obj.getMethod(m.method) orelse {
                    return error.UndefinedMethod;
                };
                var stack_buf2: [16]ast.Value = undefined;
                const total2 = m.arguments.len;
                if (total2 <= 16) {
                    for (m.arguments, 0..) |arg, idx| {
                        stack_buf2[idx] = try evaluate(arg, env);
                    }
const result = method(stack_buf2[0..total2], env);
                     return switch (result) {
                         .value => |val| val,
                         .void => .void,
                     };
                 }
                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                defer args.deinit(env.allocator);
                for (m.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try args.append(env.allocator, val);
                }
const result = method(args.items, env);
                 args.clearAndFree(env.allocator);
                 return switch (result) {
                     .value => |val| val,
                     .void => .void,
                 };
             }

            const value = try evaluate(m.object, env);
            if (value == .array) {
                const builtin_obj = env.getBuiltinObject("Array") orelse {
                    return error.UndefinedObject;
                };
                const method = builtin_obj.getMethod(m.method) orelse {
                    return error.UndefinedMethod;
                };
                var stack_buf3: [16]ast.Value = undefined;
                stack_buf3[0] = value;
                const total3 = 1 + m.arguments.len;
                if (total3 <= 16) {
                    for (m.arguments, 0..) |arg, idx| {
                        stack_buf3[idx + 1] = try evaluate(arg, env);
                    }
                    const result = method(stack_buf3[0..total3], env);
                    return switch (result) {
                        .value => |val| val,
                        .void => .void,
                    };
                }
                var args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                for (m.arguments) |arg| {
                    const val = try evaluate(arg, env);
                    try args.append(env.allocator, val);
                }
                var method_args = try std.ArrayList(ast.Value).initCapacity(env.allocator, 0);
                defer method_args.deinit(env.allocator);
                try method_args.append(env.allocator, value);
                try method_args.appendSlice(env.allocator, args.items);
                const result = method(method_args.items, env);
                method_args.clearAndFree(env.allocator);
                args.clearAndFree(env.allocator);
                return switch (result) {
                    .value => |val| val,
                    .void => .void,
                };
            } else if (value == .iterator) {
                if (std.mem.eql(u8, m.method, "next")) {
                    return value.iterator.next(env.allocator, &env.arrays, &env.objects);
                }
                return .{ .void = {} };
            } else if (value == .object) {
                const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @alignCast(@ptrCast(value.object));
                const method = bObjPtr.getMethod(m.method) orelse {
                    return error.UndefinedMethod;
                };
                var stack_buf4: [16]ast.Value = undefined;
                var args4: []ast.Value = &[_]ast.Value{};
                if (m.arguments.len > 0) {
                    if (m.arguments.len <= 16) {
                        for (m.arguments, 0..) |arg, idx| {
                            stack_buf4[idx] = try evaluate(arg, env);
                        }
                        args4 = stack_buf4[0..m.arguments.len];
                    }
                }
                const result4 = method(args4, env);
                return switch (result4) {
                    .value => |val| val,
                    .void => .void,
                };
            } else {
                return error.InvalidMethodCall;
            }
        },
        .ImportStatement => |i| {
            const allocator = env.allocator;
            const io = env.io orelse return error.NoIo;

            var full_path: []const u8 = undefined;
            var needs_free = false;
            if (i.module_path.len > 0 and i.module_path[0] == '/') {
                full_path = i.module_path;
            } else if (env.module_dir) |dir| {
                full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, i.module_path });
                needs_free = true;
            } else {
                full_path = i.module_path;
            }
            defer if (needs_free) allocator.free(full_path);

            var root = env;
            while (root.outer) |outer| root = outer;

            // Check cache first
            var cached_exports: ?*const std.StringHashMap(ast.Value) = null;
            var cached_functions: ?*const std.StringHashMap(*ast.Node) = null;

            if (root.module_cache.get(full_path)) |cached| {
                cached_exports = &cached.exports;
                cached_functions = &cached.functions;
            }

            if (cached_exports == null) {
                // First import: load, parse, evaluate, cache
                const content = try Io.Dir.cwd().readFileAlloc(io, full_path, allocator, Io.Limit.limited(10 * 1024 * 1024));
                var resources_stored = false;
                errdefer if (!resources_stored) allocator.free(content);

                const LexerT = @import("lexer.zig").Lexer;
                const ParserT = @import("parser.zig").Parser;
                var lexer = LexerT.init(content);
                var parser = try ParserT.init(&lexer, allocator);
                errdefer if (!resources_stored) parser.deinit();
                const statements = try parser.parseProgram();

                try root.module_contents.append(root.allocator, content);
                try root.module_arenas.append(root.allocator, parser.arena);
                resources_stored = true;

                var module_dir: []const u8 = ".";
                if (std.mem.lastIndexOfScalar(u8, full_path, '/')) |idx| {
                    module_dir = full_path[0..idx];
                }

                var module_env = try Environment.initWithIo(allocator, null, io);
                defer module_env.deinit();
                module_env.module_dir = module_dir;

                for (statements) |stmt| {
                    _ = try evaluate(stmt, &module_env);
                }

                // Store in cache
                var cache_entry = ModuleCacheEntry{
                    .exports = std.StringHashMap(ast.Value).init(allocator),
                    .functions = std.StringHashMap(*ast.Node).init(allocator),
                };
                {
                    var it = module_env.exports.iterator();
                    while (it.next()) |entry| {
                        try cache_entry.exports.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
                {
                    var it = module_env.functions.iterator();
                    while (it.next()) |entry| {
                        try cache_entry.functions.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
                const cache_key = try allocator.dupe(u8, full_path);
                errdefer allocator.free(cache_key);
                try root.module_cache.put(cache_key, cache_entry);

                cached_exports = &root.module_cache.get(cache_key).?.exports;
                cached_functions = &root.module_cache.get(cache_key).?.functions;
            }

            // Bind exports from cache
            if (i.named_bindings) |bindings| {
                for (bindings) |binding| {
                    const export_name = binding.name;
                    const local_name = binding.alias orelse binding.name;
                    const val = cached_exports.?.get(export_name) orelse return error.ExportNotFound;
                    try env.setVar(local_name, val);
                    if (cached_functions.?.get(export_name)) |func_node| {
                        try env.setFunction(local_name, func_node);
                    }
                }
            }

            if (i.namespace) |_| {
                var it = cached_exports.?.iterator();
                while (it.next()) |entry| {
                    if (std.mem.eql(u8, entry.key_ptr.*, "default")) continue;
                    try env.setVar(entry.key_ptr.*, entry.value_ptr.*);
                    if (cached_functions.?.get(entry.key_ptr.*)) |func_node| {
                        try env.setFunction(entry.key_ptr.*, func_node);
                    }
                }
            }

            if (i.default_binding) |db| {
                const val = cached_exports.?.get("default") orelse return error.ExportNotFound;
                try env.setVar(db, val);
                if (cached_functions.?.get("default")) |func_node| {
                    try env.setFunction(db, func_node);
                }
            }

            return .{ .float = 0.0 };
        },
        .ExportStatement => |e| {
            const result = try evaluate(e.declaration, env);
            const decl_name: ?[]const u8 = switch (e.declaration.*) {
                .ConstantDeclaration => |c| c.name,
                .VariableDeclaration => |v| v.name,
                .LetDeclaration => |v| v.name,
                .FunctionDeclaration => |f| f.name,
                else => null,
            };

            if (e.is_default) {
                if (decl_name) |n| {
                    if (env.get(n)) |v| {
                        try env.exports.put("default", v);
                    } else if (env.getFunction(n)) |_| {
                        try env.exports.put("default", .{ .float = 0.0 });
                    } else {
                        try env.exports.put("default", result);
                    }
                } else {
                    try env.exports.put("default", result);
                }
            }

            if (!e.is_default) {
                if (decl_name) |n| {
                    if (env.get(n)) |v| {
                        try env.exports.put(n, v);
                    } else if (env.getFunction(n)) |_| {
                        try env.exports.put(n, .{ .float = 0.0 });
                    } else {
                        return error.ExportNotFound;
                    }
                }
            }

            return result;
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn parseAndEvaluate(source: []const u8, env_: *Environment) !ast.Value {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();
    return try evaluate(node, env_);
}

fn parseAndEvaluateProgram(source: []const u8, env_: *Environment) !ast.Value {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();
    var result: ast.Value = .{ .float = 0.0 };
    for (statements) |stmt| {
        result = try evaluate(stmt, env_);
    }
    return result;
}

fn parseProgramNoFree(source: []const u8, env_: *Environment) !struct { statements: []*ast.Node, parser: Parser } {
    var lexer = Lexer.init(source);
    var parser = try Parser.init(&lexer, env_.allocator);
    const statements = try parser.parseProgram();
    return .{ .statements = statements, .parser = parser };
}

// --- Environment tests ---

test "Environment - set and get" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.set("x", .{ .integer = 42 });
    const val = env_.get("x");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), val.?.integer);
}

test "Environment - get returns null for undefined" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const val = env_.get("undefined_var");
    try std.testing.expect(val == null);
}

test "Environment - outer scope lookup" {
    const allocator = std.testing.allocator;
    var outer = try Environment.init(allocator, null);
    defer outer.deinit();
    try outer.set("x", .{ .integer = 10 });

    var inner = try Environment.init(allocator, &outer);
    defer inner.deinit();

    const val = inner.get("x");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 10), val.?.integer);
}

test "Environment - setConstant" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.setConstant("PI", .{ .float = 3.14 });
    const val = env_.get("PI");
    try std.testing.expect(val != null);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), val.?.float, 0.001);
}

test "Environment - constant reassignment fails" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.setConstant("PI", .{ .float = 3.14 });
    const result = env_.set("PI", .{ .float = 3.14159 });
    try std.testing.expectError(error.ConstantReassignment, result);
}

test "Environment - isConstant" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try std.testing.expect(!env_.isConstant("x"));
    try env_.setConstant("x", .{ .integer = 1 });
    try std.testing.expect(env_.isConstant("x"));
}

// --- Literal evaluation tests ---

test "evaluate integer literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("42", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "evaluate float literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("3.14", &env_);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "evaluate string literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("'hello'", &env_);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "evaluate boolean true" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("true", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate boolean false" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("false", &env_);
    try std.testing.expect(!result.boolean);
}

// --- Binary expression arithmetic tests ---

test "evaluate integer addition" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("3 + 4", &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate integer subtraction" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("10 - 3", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate integer multiplication" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("6 * 7", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "evaluate integer division" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("10 / 2", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), result.float, 0.001);
}

test "evaluate integer modulo" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 % 2", &env_);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "evaluate float arithmetic" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("1.5 + 2.5", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result.float, 0.001);
}

test "evaluate operator precedence" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("2 + 3 * 4", &env_);
    try std.testing.expectEqual(@as(i64, 14), result.integer);
}

// --- Comparison operator tests ---

test "evaluate less than" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("3 < 5", &env_);
    try std.testing.expect(result == .boolean);
    try std.testing.expect(result.boolean);
}

test "evaluate greater than or equal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 >= 5", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate equality" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("42 == 42", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate not equal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("1 != 2", &env_);
    try std.testing.expect(result.boolean);
}

// --- Logical operator tests ---

test "evaluate logical and - true" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("true && true", &env_);
    try std.testing.expect(result == .boolean);
    try std.testing.expect(result.boolean);
}

test "evaluate logical and - false" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("true && false", &env_);
    try std.testing.expect(!result.boolean);
}

test "evaluate logical or - true" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("false || true", &env_);
    try std.testing.expect(result.boolean);
}

test "evaluate logical or - false" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("false || false", &env_);
    try std.testing.expect(!result.boolean);
}

test "evaluate logical not" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("!true", &env_);
    try std.testing.expect(!result.boolean);
}

// --- Bitwise operator tests ---

test "evaluate bitwise and" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 & 3", &env_);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "evaluate bitwise or" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 | 3", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate bitwise xor" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("5 ^ 3", &env_);
    try std.testing.expectEqual(@as(i64, 6), result.integer);
}

test "evaluate bitwise not" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("~5", &env_);
    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, -6), result.integer);
}

test "evaluate left shift" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("1 << 3", &env_);
    try std.testing.expectEqual(@as(i64, 8), result.integer);
}

test "evaluate right shift" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("8 >> 1", &env_);
    try std.testing.expectEqual(@as(i64, 4), result.integer);
}

// --- Assignment tests ---

test "evaluate variable declaration and identifier" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluate("x", &env_);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

test "evaluate constant declaration" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("const PI = 3.14", &env_);
    const result = try parseAndEvaluate("PI", &env_);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "evaluate reassignment" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    _ = try parseAndEvaluateProgram("x = 5", &env_);
    const result = try parseAndEvaluate("x", &env_);
    try std.testing.expectEqual(@as(i64, 5), result.integer);
}

// --- Compound assignment tests ---

test "evaluate plus assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluateProgram("x += 5", &env_);
    try std.testing.expectEqual(@as(i64, 15), result.integer);
}

test "evaluate minus assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluateProgram("x -= 3", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate multiply assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 4", &env_);
    const result = try parseAndEvaluateProgram("x *= 3", &env_);
    try std.testing.expectEqual(@as(i64, 12), result.integer);
}

test "evaluate modulo assign" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 10", &env_);
    const result = try parseAndEvaluateProgram("x %= 3", &env_);
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

// --- Nullish coalescing tests ---

test "evaluate nullish coalescing - nullish triggers fallback" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    try env_.set("x", .{ .void = {} });
    const result = try parseAndEvaluate("x ?? 42", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "evaluate nullish coalescing - non-nullish keeps left" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("0 ?? 99", &env_);
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

test "evaluate nullish coalescing - zero integer keeps left" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("10 ?? 42", &env_);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

// --- valuesEqual tests ---

test "valuesEqual - integer equality" {
    const left = ast.Value{ .integer = 42 };
    const right = ast.Value{ .integer = 42 };
    try std.testing.expect(valuesEqual(left, right));
}

test "valuesEqual - integer inequality" {
    const left = ast.Value{ .integer = 42 };
    const right = ast.Value{ .integer = 99 };
    try std.testing.expect(!valuesEqual(left, right));
}

test "valuesEqual - integer float cross comparison" {
    const left = ast.Value{ .integer = 42 };
    const right = ast.Value{ .float = 42.0 };
    try std.testing.expect(valuesEqual(left, right));
}

test "valuesEqual - string equality" {
    const left = ast.Value{ .string = "hello" };
    const right = ast.Value{ .string = "hello" };
    try std.testing.expect(valuesEqual(left, right));
}

test "valuesEqual - string inequality" {
    const left = ast.Value{ .string = "hello" };
    const right = ast.Value{ .string = "world" };
    try std.testing.expect(!valuesEqual(left, right));
}

test "valuesEqual - boolean equality" {
    try std.testing.expect(valuesEqual(.{ .boolean = true }, .{ .boolean = true }));
    try std.testing.expect(!valuesEqual(.{ .boolean = true }, .{ .boolean = false }));
}

test "valuesEqual - void equality" {
    try std.testing.expect(valuesEqual(.{ .void = {} }, .{ .void = {} }));
}

test "valuesEqual - different types" {
    try std.testing.expect(!valuesEqual(.{ .integer = 42 }, .{ .string = "42" }));
    try std.testing.expect(!valuesEqual(.{ .float = 42.0 }, .{ .boolean = true }));
}

// --- Block statement tests ---

test "evaluate block statement" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram("{ 42 }", &env_);
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

// --- If statement tests ---

test "evaluate if statement - true branch" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const if_result = try parseAndEvaluateProgram("if (true) { 100 }", &env_);
    try std.testing.expectEqual(@as(i64, 100), if_result.integer);
}

test "evaluate if else statement - false branch" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram("if (false) { 100 } else { 200 }", &env_);
    try std.testing.expectEqual(@as(i64, 200), result.integer);
}

test "evaluate if statement - no else returns 0" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluateProgram("if (false) { 100 }", &env_);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.float, 0.001);
}

// --- While loop tests ---

test "evaluate while loop" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var i = 0", &env_);
    _ = try parseAndEvaluateProgram("var sum = 0", &env_);
    _ = try parseAndEvaluateProgram("while (i < 5) { sum += i; i += 1 }", &env_);
    const result = try parseAndEvaluate("sum", &env_);
    const result_f: f64 = switch (result) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result_f, 0.001);
}

// --- For loop tests ---

test "evaluate for loop - simple" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var sum = 0", &env_);
    _ = try parseAndEvaluateProgram("for (var j = 1; j < 6; j = j + 1) { sum = sum + j }", &env_);
    const result = try parseAndEvaluate("sum", &env_);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), result.float, 0.001);
}

// --- Function tests ---

test "evaluate function declaration and call" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result_struct = try parseProgramNoFree("fn add(a, b) { return a + b }", &env_);
    var parser = result_struct.parser;
    defer parser.deinit();
    _ = try evaluate(result_struct.statements[0], &env_);
    const result = try parseAndEvaluate("add(3, 4)", &env_);
    try std.testing.expectEqual(@as(i64, 7), result.integer);
}

test "evaluate arrow function" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result_struct = try parseProgramNoFree("const double = (x) => x * 2", &env_);
    var parser = result_struct.parser;
    defer parser.deinit();
    _ = try evaluate(result_struct.statements[0], &env_);
    const result = try parseAndEvaluate("double(5)", &env_);
    try std.testing.expectEqual(@as(i64, 10), result.integer);
}

// --- Array tests ---

test "evaluate array literal" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = try parseAndEvaluate("[1, 2, 3]", &env_);
    try std.testing.expect(result == .array);
    try std.testing.expectEqual(@as(usize, 3), result.array.elements.items.len);
}

test "evaluate array index" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var arr = [10, 20, 30]", &env_);
    const result = try parseAndEvaluate("arr[1]", &env_);
    try std.testing.expectEqual(@as(i64, 20), result.integer);
}

// --- let vs var block scoping tests ---

test "let is block-scoped - not visible outside block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("{ let x = 42 }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result == null);
}

test "var leaks out of block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("{ var x = 42 }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 42), result.?.integer);
}

test "let shadows var in block" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    const result = try parseAndEvaluateProgram("{ let x = 2; x }", &env_);
    try std.testing.expectEqual(@as(i64, 2), result.integer);

    const outer = env_.get("x");
    try std.testing.expect(outer != null);
    try std.testing.expectEqual(@as(i64, 1), outer.?.integer);
}

test "var reassignment inside block updates outer" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    _ = try parseAndEvaluateProgram("{ x = 99 }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 99), result.?.integer);
}

test "let re-declaration in same block fails" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    const result = parseAndEvaluateProgram("{ let x = 1; let x = 2 }", &env_);
    try std.testing.expectError(error.LetRedeclaration, result);
}

test "let in nested blocks" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("let x = 1", &env_);
    const result = try parseAndEvaluateProgram("{ let x = 2; { let x = 3; x } }", &env_);
    try std.testing.expectEqual(@as(i64, 3), result.integer);

    const outer = env_.get("x");
    try std.testing.expect(outer != null);
    try std.testing.expectEqual(@as(i64, 1), outer.?.integer);
}

test "var in nested block updates function scope" {
    const allocator = std.testing.allocator;
    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    _ = try parseAndEvaluateProgram("var x = 1", &env_);
    _ = try parseAndEvaluateProgram("{ { var x = 99 } }", &env_);
    const result = env_.get("x");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 99), result.?.integer);
}
