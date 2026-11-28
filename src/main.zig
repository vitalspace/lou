const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Dir = Io.Dir;

const Ast = @import("ast.zig");
const Environment = @import("evaluator.zig").Environment;
const evaluate = @import("evaluator.zig").evaluate;
const drainPromiseJobs = @import("evaluator.zig").drainPromiseJobs;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const VM = @import("vm.zig").VM;
const Compiler = @import("vm.zig").Compiler;
const Chunk = @import("vm.zig").Chunk;
const initSimboloObject = @import("builtins/symbol.zig").initSimboloObject;
const objectPrototypeMod = @import("builtins/object/prototype.zig");
const TypeChecker = @import("type_checker.zig").TypeChecker;

const use_vm = true;

test {
    _ = @import("builtins/console/log.zig");
    _ = @import("builtins/console/error.zig");
    _ = @import("builtins/console/clear.zig");
    _ = @import("builtins/console/time.zig");
}

test {
    _ = @import("builtins/array/length.zig");
    _ = @import("builtins/array/at.zig");
    _ = @import("builtins/array/pop.zig");
    _ = @import("builtins/array/push.zig");
    _ = @import("builtins/array/concat.zig");
    _ = @import("builtins/array/copyWithin.zig");
    _ = @import("builtins/array/entries.zig");
    _ = @import("builtins/array/every.zig");
    _ = @import("builtins/array/fill.zig");
    _ = @import("builtins/array/filter.zig");
    _ = @import("builtins/array/find.zig");
    _ = @import("builtins/array/findIndex.zig");
}

test {
    _ = @import("builtins/math/math.zig");
    _ = @import("builtins/math/abs.zig");
}

test {
    _ = @import("builtins/string/string.zig");
    _ = @import("builtins/string/toUpperCase.zig");
    _ = @import("builtins/string/normalize.zig");
    _ = @import("builtins/string/padEnd.zig");
    _ = @import("builtins/string/padStart.zig");
    _ = @import("builtins/string/repeat.zig");
    _ = @import("builtins/string/replace.zig");
    _ = @import("builtins/string/replaceAll.zig");
    _ = @import("builtins/string/search.zig");
    _ = @import("builtins/string/slice.zig");
    _ = @import("builtins/string/split.zig");
    _ = @import("builtins/string/startsWith.zig");
}

test {
    _ = @import("builtins/set/set.zig");
    _ = @import("builtins/map/map.zig");
}

fn openFile(filePath: []const u8, allocator: std.mem.Allocator, io: Io) ![]const u8 {
    Dir.cwd().access(io, filePath, .{}) catch {
        return error.FileNotFound;
    };

    return try Dir.cwd().readFileAlloc(io, filePath, allocator, Io.Limit.limited(10 * 1024 * 1024));
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Debug builds use the safety allocator with leak detection; release builds
    // use the fast general-purpose allocator.
    const Mode = @TypeOf(builtin.mode);
    const is_debug = if (@hasField(Mode, "debug")) builtin.mode == .debug else builtin.mode == .Debug;
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer if (is_debug) {
        if (debug_allocator.deinit() == .leak) {
            @panic("MEMORY LEAK DETECTED");
        }
    };
    const allocator = if (is_debug) debug_allocator.allocator() else std.heap.smp_allocator;

    var args_it = std.process.Args.Iterator.init(init.minimal.args);
    defer args_it.deinit();

    _ = args_it.next();

    const cmd = args_it.next() orelse {
        std.debug.print("Usage: lou run <filename>\n", .{});
        return;
    };

    if (!std.mem.eql(u8, cmd, "run")) {
        std.debug.print("Usage: lou run <filename>\n", .{});
        return;
    }

    const filePath = args_it.next() orelse {
        std.debug.print("Usage: lou run <filename>\n", .{});
        return;
    };

    const content = try openFile(filePath, allocator, io);
    defer allocator.free(content);

    var lexer = Lexer.init(content);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const program = try parser.parseProgram();

    // --- Type checking pass ---
    // File extension policy:
    //   .lou, .ts → run type checking pass
    //   .js       → skip type checking (plain JavaScript interop)
    //   other     → skip type checking
    const ext = if (std.mem.lastIndexOfScalar(u8, filePath, '.')) |dot_idx| filePath[dot_idx..] else "";
    const should_typecheck = std.mem.eql(u8, ext, ".lou") or std.mem.eql(u8, ext, ".ts");

    if (should_typecheck) {
        var type_checker = TypeChecker.init(allocator, filePath);
        try type_checker.check(program);
        if (type_checker.has_errors) {
            std.debug.print("Type checking failed for: {s}\n", .{filePath});
            return;
        }
    }

    var env_ = try Environment.initWithIo(allocator, null, io);
    env_.source_name = filePath;
    env_.ansi_disabled =
        if (init.environ_map.get("NO_COLOR")) |value| value.len > 0
        else if (init.environ_map.get("TERM")) |term| std.mem.eql(u8, term, "dumb")
        else false;
    // Bootstrap Object.prototype singleton so plain object literals
    // created later inherit it via their `.prototype` field.
    env_.object_prototype = try objectPrototypeMod.createObjectPrototype(allocator, &env_.objects);
    defer env_.deinit();

    var dir_buf: []const u8 = ".";
    if (std.mem.lastIndexOfScalar(u8, filePath, '/')) |idx| {
        dir_buf = filePath[0..idx];
    }

    env_.module_dir = dir_buf;

    try initSimboloObject(&env_);

    // Register eval builtin
    try env_.builtins.put("eval", @import("evaluator.zig").evalFn);

    // ES global constants
    try env_.setConstant("NaN", .{ .float = std.math.nan(f64) });
    try env_.setConstant("Infinity", .{ .float = std.math.inf(f64) });

    // globalThis — the global object (js_object wrapper for the root environment).
    // Set a self-referencing "globalThis" property so globalThis.globalThis === globalThis.
    const global_this_obj = try Ast.ObjectValue.init(allocator);
    try env_.objects.append(allocator, global_this_obj);
    env_.global_this = global_this_obj;
    try global_this_obj.properties.put("globalThis", .{ .js_object = global_this_obj });
    try global_this_obj.properties.put("NaN", .{ .float = std.math.nan(f64) });
    try global_this_obj.properties.put("Infinity", .{ .float = std.math.inf(f64) });
    try global_this_obj.properties.put("undefined", .{ .void = {} });
    try env_.setConstant("globalThis", .{ .js_object = global_this_obj });

    // Reserve top-level lexical bindings so reads before their declaration
    // hit the temporal dead zone instead of falling through to `undefined`.
    for (program) |stmt| {
        switch (stmt.*) {
            .LetDeclaration => |v| env_.declareLexical(v.name) catch {},
            .ConstantDeclaration => |c| env_.declareLexical(c.name) catch {},
            else => {},
        }
    }

    // Async/await and Promise need evaluator-level continuations and the
    // promise job queue; run those programs through the evaluator so the VM
    // does not need a suspension opcode.
    const needs_evaluator = std.mem.indexOf(u8, content, "async") != null or
        std.mem.indexOf(u8, content, "await") != null or
        std.mem.indexOf(u8, content, "Promise") != null;

    if (use_vm and !needs_evaluator) {
        var chunk = Chunk.init(allocator);
        defer chunk.deinit();
        var comp = Compiler.init(&env_);
        comp.compile(program, &chunk);
        if (comp.compile_error) |err| {
            comp.deinit();
            if (comp.compile_error_line > 0) {
                std.debug.print("Error at line {d}: {s}\n", .{ comp.compile_error_line, err });
            } else {
                std.debug.print("Error: {s}\n", .{err});
            }
            return error.CompileError;
        }
        var vm = VM.init(&env_);
        vm.compiled_chunks = comp.compiled_chunks; // Transfer ownership
        // Prevent Compiler deinit from double-freeing the chunks
        comp.compiled_chunks = std.StringHashMap(*Chunk).init(allocator);
        comp.deinit();
        defer vm.deinit();
        try vm.interpret(&chunk);
    } else {
        for (program) |stmt| {
            _ = try evaluate(stmt, &env_);
        }
    }
    drainPromiseJobs(&env_);
}
