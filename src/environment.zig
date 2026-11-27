const std = @import("std");
const ast = @import("ast.zig");
const builtins = @import("./builtins/builtins.zig");
const builtinsTypes = @import("./types/types.zig");

pub const Io = std.Io;
pub const DEBUG_OPTIMIZATION = false;

pub const DEBUG_TRACE = false;

pub const tracePrint = struct {
    pub fn call(comptime fmt: []const u8, args: anytype) void {
        if (DEBUG_TRACE) std.debug.print(fmt, args);
    }
}.call;

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
        .hole => {},
        else => {},
    }
}

pub const TraceFrame = struct {
    name: []const u8,
    line: u32,
};

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
    console_counts: std.StringHashMap(u64),
    console_group_depth: u32 = 0,
    /// Root-only: user-visible call frames for `console.trace`.
    trace_frames: std.ArrayList(TraceFrame),
    /// Root-only: name of the script currently being executed.
    source_name: []const u8 = "<script>",
    current_call_line: u32 = 0,
    /// Root-only: `NO_COLOR`/`TERM=dumb` requested plain output.
    ansi_disabled: bool = false,
    arrays: std.ArrayList(*ast.ArrayObject),
    iterators: std.ArrayList(*ast.ArrayIterator),
    objects: std.ArrayList(*ast.ObjectValue),
    symbols: std.ArrayList(*ast.SymbolValue),
    bigints: std.ArrayList(*ast.BigIntValue),
    regexp_objects: std.ArrayList(*ast.RegExpValue),
    generators: std.ArrayList(*ast.GeneratorObject),
    owned_strings: std.ArrayList([]const u8),
    /// Heap-allocated sub-environments that must outlive the current
    /// scope — primarily per-iteration envs from `for (let/const ...)`
    /// loops, whose reference may be captured by closures created in
    /// the loop body. Each entry is deinit'd + destroyed during parent
    /// env teardown so closures continue to read valid memory after
    /// the loop has returned.
    iter_envs: std.ArrayList(*Environment),
    /// Heap-allocated closure captures. When an arrow/function/generator
    /// declaration is evaluated inside a function-or-block scope, we
    /// create a fresh heap-allocated block env as the closure's lexical
    /// scope so that the captured pointer remains valid after the
    /// enclosing scope returns. Tracked here for lifetime management.
    closure_envs: std.ArrayList(*Environment),
    /// Synthetic AST nodes created during testing / JSON parse.
    /// Tracked so deinit can run freeAst on them.
    synthetic_asts: std.ArrayList(*ast.Node),
    /// Object.prototype — singleton shared by all plain object literals.
    /// Holds stub dispatchers (toString, valueOf, hasOwnProperty) that
    /// vm.zig recognizes via the `@@native = "ObjectProtoMethod"` marker.
    /// Only set on the root environment so it outlives all derived
    /// object literals whose `.prototype` field points at it.
    object_prototype: ?*ast.ObjectValue = null,
    /// The global this object (js_object wrapper for the root environment).
    /// Only set on the root environment. Property reads/writes on this object
    /// are synchronized with the root environment's values map.
    global_this: ?*ast.ObjectValue = null,
    outer: ?*Environment,
    scope_kind: enum { block, function } = .function,
    return_hit: bool = false,
    break_hit: bool = false,
    break_label: ?[]const u8 = null,
    continue_hit: bool = false,
    continue_label: ?[]const u8 = null,
    pending_loop_label: ?[]const u8 = null,
    throw_hit: bool = false,
    throw_value: ast.Value = .{ .void = {} },
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
    /// Current per-iteration scope of the for-let loop that yielded.
    for_yield_iter_env: ?*anyopaque = null,
    for_of_gen: ?*ast.GeneratorObject = null,
    for_of_array: ?*ast.ArrayObject = null,
    for_of_array_index: usize = 0,
    exports: std.StringHashMap(ast.Value),
    module_dir: ?[]const u8,
    module_contents: std.ArrayList([]const u8),
    module_arenas: std.ArrayList(*std.heap.ArenaAllocator),
    module_cache: std.StringHashMap(ModuleCacheEntry),
    /// Heap-allocated ClosureValue objects created by the per-iteration
    /// closure-capture logic. Each ClosureValue wraps an AST function node
    /// together with its captured environment. Tracked here so they are
    /// freed at scope teardown (the captured env is separately tracked in
    /// iter_envs/closure_envs, so we only destroy the ClosureValue wrapper).
    closures: std.ArrayList(*ast.ClosureValue),
    /// Mark this environment as a per-iteration env (heap-allocated by a
    /// for-let/for-of/for-in loop). Used by the closure-capture logic
    /// to decide whether to set `closure_env` on freshly-defined
    /// ArrowFunction / FunctionDeclaration / GeneratorDeclaration nodes
    /// — only heap-allocated iter envs are guaranteed to outlive their
    /// natural scope.
    is_iter_env: bool = false,
    /// Heap-owned scope (created by initHeap/initIterHeap/initClosureHeap).
    /// Only heap-owned scopes may be adopted by a closure; stack scopes get
    /// snapshotted by captureEnv().
    owned: bool = false,
    /// Set once a closure adopted this scope, so the call-site cleanup knows
    /// it must not free it anymore.
    captured: bool = false,
    /// Set when this scope's storage has already been released.
    deinited: bool = false,
    /// This environment exists only as a captured lexical scope (it is not a
    /// call frame and is freed at program exit together with closure_envs).
    is_closure_env: bool = false,

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
        const bigints = try std.ArrayList(*ast.BigIntValue).initCapacity(allocator, 0);
        const regexp_objects = try std.ArrayList(*ast.RegExpValue).initCapacity(allocator, 0);
        const generators = try std.ArrayList(*ast.GeneratorObject).initCapacity(allocator, 0);
        const owned_strings = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        const iter_envs = try std.ArrayList(*Environment).initCapacity(allocator, 0);
        const closure_envs = try std.ArrayList(*Environment).initCapacity(allocator, 0);
        const synthetic_asts = try std.ArrayList(*ast.Node).initCapacity(allocator, 0);
        const closures = try std.ArrayList(*ast.ClosureValue).initCapacity(allocator, 0);
        const trace_frames = try std.ArrayList(TraceFrame).initCapacity(allocator, 0);

        const env = Environment{
            .allocator = allocator,
            .io = io,
            .values = std.StringHashMap(ast.Value).init(allocator),
            .constants = std.StringHashMap(void).init(allocator),
            .functions = std.StringHashMap(*ast.Node).init(allocator),
            .builtins = try builtins.initBuiltins(allocator),
            .builtin_objects = try builtins.initBuiltinObjects(allocator),
            .timers = std.StringHashMap(i128).init(allocator),
            .console_counts = std.StringHashMap(u64).init(allocator),
            .trace_frames = trace_frames,
            .arrays = arrays,
            .iterators = iterators,
            .objects = objects,
            .symbols = symbols,
            .bigints = bigints,
            .regexp_objects = regexp_objects,
            .generators = generators,
            .owned_strings = owned_strings,
            .iter_envs = iter_envs,
            .closure_envs = closure_envs,
            .synthetic_asts = synthetic_asts,
            .closures = closures,
            .global_this = null,
            .outer = outer,
            .exports = std.StringHashMap(ast.Value).init(allocator),
            .module_dir = null,
            .module_contents = try std.ArrayList([]const u8).initCapacity(allocator, 0),
            .module_arenas = try std.ArrayList(*std.heap.ArenaAllocator).initCapacity(allocator, 0),
            .module_cache = std.StringHashMap(ModuleCacheEntry).init(allocator),
        };

        return env;
    }

    pub fn initHeap(allocator: std.mem.Allocator, outer: ?*Environment) !*Environment {
        const env_ptr = try allocator.create(Environment);
        env_ptr.* = try init(allocator, outer);
        env_ptr.owned = true;
        return env_ptr;
    }

    /// Scope a callback should see: closures keep their captured scope, any
    /// other callable falls back to the caller environment.
    pub fn callableScope(fn_val: ast.Value, fallback: *Environment) *Environment {
        return switch (fn_val) {
            .closure => |cl| @alignCast(@ptrCast(cl.env)),
            else => fallback,
        };
    }

    /// Like init(), but parented to a closure captured scope when the callee
    /// is a closure value. Returned by value so call sites keep their `defer
    /// deinit()` ownership.
    pub fn initCallable(allocator: std.mem.Allocator, fallback: *Environment, fn_val: ast.Value) !Environment {
        return init(allocator, callableScope(fn_val, fallback));
    }

    pub fn initIterHeap(allocator: std.mem.Allocator, outer: *Environment) !*Environment {
        const env_ptr = try allocator.create(Environment);
        env_ptr.* = try initBlock(allocator, outer);
        // Iteration scopes hold the loop's own let/const bindings; treat them
        // as a binding target so setVar() does not hoist them to the root.
        env_ptr.scope_kind = .function;
        env_ptr.owned = true;
        env_ptr.is_iter_env = true;
        // Register on the root so per-iteration scopes survive for the whole
        // program: a closure created in the loop body may be called long
        // after the enclosing function returned.
        try outer.root().iter_envs.append(allocator, env_ptr);
        return env_ptr;
    }

    /// Heap-allocate a lexical scope that lives until program exit. Used as
    /// the call frame of functions whose body creates closures, so those
    /// closures can adopt it safely.
    pub fn initClosureHeap(allocator: std.mem.Allocator, outer: *Environment) !*Environment {
        const env_ptr = try allocator.create(Environment);
        env_ptr.* = try init(allocator, outer);
        env_ptr.owned = true;
        env_ptr.is_closure_env = true;
        try outer.root().closure_envs.append(allocator, env_ptr);
        return env_ptr;
    }

    /// Return a heap-lifetime scope to store in a closure. Root, per-iteration
    /// and captured scopes already qualify; other heap scopes are registered
    /// for teardown at program exit; stack scopes are snapshotted (their
    /// bindings are copied so the closure never dangles).
    pub fn captureEnv(self: *Environment) !*Environment {
        if (self.outer == null) return self; // program-lifetime root
        if (self.is_iter_env or self.is_closure_env) return self;
        if (self.owned) {
            if (!self.captured) {
                self.captured = true;
                try self.root().closure_envs.append(self.allocator, self);
            }
            return self;
        }
        const outer = self.outer.?;
        // The copy is parented to outer, so every heap-owned ancestor on
        // that chain must stay alive as a captured scope. Without this, a
        // function scope whose block created the closure is freed on return
        // and the copy's parent chain dangles.
        {
            var anc: ?*Environment = outer;
            while (anc) |a| {
                if (a.owned) {
                    if (!a.captured) {
                        a.captured = true;
                        if (!a.is_closure_env) try a.root().closure_envs.append(self.allocator, a);
                    }
                } else break;
                anc = a.outer;
            }
        }
        const heap = try initClosureHeap(self.allocator, outer);
        var it = self.values.iterator();
        while (it.next()) |entry| {
            heap.values.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
        var fit = self.functions.iterator();
        while (fit.next()) |entry| {
            heap.functions.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
        var cit = self.constants.iterator();
        while (cit.next()) |entry| {
            heap.constants.put(entry.key_ptr.*, {}) catch {};
        }
        return heap;
    }

    pub fn retain(self: *Environment) void {
        // Placeholder for shared-ownership semantics. Currently each
        // heap-iter-env has exactly one owner (its parent, via iter_envs).
        _ = self;
    }

    pub fn release(self: *Environment) void {
        self.deinit();
        self.allocator.destroy(self);
    }

    pub fn initBlock(allocator: std.mem.Allocator, outer: *Environment) !Environment {
        const owned_strings = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        const iter_envs = try std.ArrayList(*Environment).initCapacity(allocator, 0);
        const closure_envs = try std.ArrayList(*Environment).initCapacity(allocator, 0);
        const closures = try std.ArrayList(*ast.ClosureValue).initCapacity(allocator, 0);
        const synthetic_asts = try std.ArrayList(*ast.Node).initCapacity(allocator, 0);
        const trace_frames = try std.ArrayList(TraceFrame).initCapacity(allocator, 0);
        const env = Environment{
            .allocator = allocator,
            .io = outer.io,
            .values = std.StringHashMap(ast.Value).init(allocator),
            .constants = std.StringHashMap(void).init(allocator),
            .functions = std.StringHashMap(*ast.Node).init(allocator),
            .builtins = std.StringHashMap(builtinsTypes.BuiltinFn).init(allocator),
            .builtin_objects = std.StringHashMap(*const builtinsTypes.BuiltinObjectImpl).init(allocator),
            .timers = std.StringHashMap(i128).init(allocator),
            .console_counts = std.StringHashMap(u64).init(allocator),
            .trace_frames = trace_frames,
            .arrays = try std.ArrayList(*ast.ArrayObject).initCapacity(allocator, 0),
            .iterators = try std.ArrayList(*ast.ArrayIterator).initCapacity(allocator, 0),
            .objects = try std.ArrayList(*ast.ObjectValue).initCapacity(allocator, 0),
            .symbols = try std.ArrayList(*ast.SymbolValue).initCapacity(allocator, 0),
            .bigints = try std.ArrayList(*ast.BigIntValue).initCapacity(allocator, 0),
            .regexp_objects = try std.ArrayList(*ast.RegExpValue).initCapacity(allocator, 0),
            .generators = try std.ArrayList(*ast.GeneratorObject).initCapacity(allocator, 0),
            .owned_strings = owned_strings,
            .iter_envs = iter_envs,
            .closure_envs = closure_envs,
            .synthetic_asts = synthetic_asts,
            .closures = closures,
            .global_this = null,
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
        var root_env = self;
        while (root_env.outer) |outer| root_env = outer;
        var it = root_env.module_cache.iterator();
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
        if (env.outer == null) env.syncExistingGlobalProperty(name, value);
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
        if (self.outer) |outer| {
            if (outer.deinited) self.outer = null;
        }
        self.deinited = true;
        // Drain both heap-tracked env lists. These were kept alive past
        // their natural scope so closures could safely reference them.
        // We deinit each one (their own lists are drained recursively)
        // and free the backing memory.
        // Reverse creation order: a nested scope's parent was always created
        // before it, so children are torn down before their parents.
        var re_i: usize = self.iter_envs.items.len;
        while (re_i > 0) {
            re_i -= 1;
            const iter_env = self.iter_envs.items[re_i];
            iter_env.deinit();
            self.allocator.destroy(iter_env);
        }
        self.iter_envs.deinit(self.allocator);

        var ce_i: usize = self.closure_envs.items.len;
        while (ce_i > 0) {
            ce_i -= 1;
            const closure_env = self.closure_envs.items[ce_i];
            closure_env.deinit();
            self.allocator.destroy(closure_env);
        }
        self.closure_envs.deinit(self.allocator);
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

        if (self.outer) |outer| {
            for (self.bigints.items) |bi| {
                outer.bigints.append(outer.allocator, bi) catch {};
            }
        } else {
            for (self.bigints.items) |bi| {
                bi.deinit();
            }
        }
        self.bigints.deinit(self.allocator);
        for (self.regexp_objects.items) |r| {
            r.deinit();
        }
        self.regexp_objects.deinit(self.allocator);

        for (self.synthetic_asts.items) |node| {
            ast.freeAst(self.allocator, node);
        }
        self.synthetic_asts.deinit(self.allocator);

        // Free ClosureValue wrappers (the captured envs they point to
        // are tracked separately in iter_envs/closure_envs).
        for (self.closures.items) |cv| {
            self.allocator.destroy(cv);
        }
        self.closures.deinit(self.allocator);

        self.exports.deinit();
        self.values.deinit();
        self.constants.deinit();
        self.functions.deinit();
        self.builtins.deinit();
        self.builtin_objects.deinit();
        self.timers.deinit();
        self.console_counts.deinit();
        self.trace_frames.deinit(self.allocator);

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

    pub fn root(self: *Environment) *Environment {
        var env_ptr = self;
        while (env_ptr.outer) |outer| env_ptr = outer;
        return env_ptr;
    }

    /// Record a new user-visible call frame. The root owns the stack so every
    /// nested environment pushes to the same place; builtins never call this.
    pub fn pushTraceFrame(self: *Environment, name: []const u8, line: u32) void {
        const rt = self.root();
        rt.trace_frames.append(rt.allocator, .{ .name = name, .line = line }) catch {};
    }

    /// Update the line of the frame currently executing. Call sites emit this
    /// before invoking a function, so the caller frame reports the line of the
    /// call expression (matching Node's stack frames).
    pub fn setTraceLine(self: *Environment, line: u32) void {
        if (line == 0) return;
        const rt = self.root();
        rt.current_call_line = line;
        if (rt.trace_frames.items.len > 0) {
            rt.trace_frames.items[rt.trace_frames.items.len - 1].line = line;
        }
    }

    pub fn popTraceFrame(self: *Environment) void {
        const rt = self.root();
        if (rt.trace_frames.items.len > 0) {
            _ = rt.trace_frames.pop();
        }
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
            if (target.outer == null) target.syncExistingGlobalProperty(name, value);
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

    /// The `globalThis` object when the CLI initialized this chain.
    pub fn globalObject(self: *Environment) ?*ast.ObjectValue {
        return self.root().global_this;
    }

    /// Mirror a root binding into the `globalThis` object.
    fn syncGlobalProperty(self: *Environment, name: []const u8, value: ast.Value) void {
        const g = self.global_this orelse return;
        g.properties.put(name, value) catch {};
    }

    /// Keep an existing `globalThis` property in sync with its binding.
    /// Declarations do not create new global-object properties (Node module
    /// semantics), but assignments to names created via `globalThis.x` must
    /// update both views.
    fn syncExistingGlobalProperty(self: *Environment, name: []const u8, value: ast.Value) void {
        const g = self.global_this orelse return;
        if (g.properties.contains(name)) g.properties.put(name, value) catch {};
    }

    /// Remove a `globalThis` property and its binding (e.g. `delete globalThis.x`).
    pub fn removeGlobalProperty(self: *Environment, name: []const u8) void {
        const rt = self.root();
        if (rt.global_this) |g| _ = g.properties.remove(name);
        if (!rt.constants.contains(name)) _ = rt.values.remove(name);
    }

    /// Write a property on the global object and expose it as a binding.
    pub fn setGlobalProperty(self: *Environment, name: []const u8, value: ast.Value) void {
        const rt = self.root();
        if (!rt.constants.contains(name)) {
            rt.values.put(name, value) catch {};
        }
        if (rt.global_this) |g| g.properties.put(name, value) catch {};
    }
};

test "globalThis writes are visible as bindings" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator, null);
    defer env.deinit();

    const obj = try ast.ObjectValue.init(allocator);
    try env.objects.append(allocator, obj);
    env.global_this = obj;

    env.setGlobalProperty("g", .{ .integer = 7 });
    try std.testing.expectEqual(@as(?ast.Value, .{ .integer = 7 }), env.get("g"));
    try std.testing.expect(obj.properties.get("g") != null);

    env.setGlobalProperty("g", .{ .integer = 9 });
    try std.testing.expectEqual(@as(?ast.Value, .{ .integer = 9 }), env.get("g"));
    try std.testing.expectEqual(@as(?ast.Value, .{ .integer = 9 }), obj.properties.get("g"));

    env.removeGlobalProperty("g");
    try std.testing.expect(env.get("g") == null);
    try std.testing.expect(obj.properties.get("g") == null);
}
