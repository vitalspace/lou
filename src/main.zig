const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

const Ast = @import("ast.zig");
const Environment = @import("evaluator.zig").Environment;
const evaluate = @import("evaluator.zig").evaluate;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

const use_vm = false;

test {
    _ = @import("builtins/console/log.zig");
    _ = @import("builtins/console/error.zig");
    _ = @import("builtins/console/clear.zig");
    _ = @import("builtins/console/time.zig");
}

test {
    _ = @import("builtins/array/length.zig");
}

fn openFile(filePath: []const u8, allocator: std.mem.Allocator, io: Io) ![]const u8 {
    Dir.cwd().access(io, filePath, .{}) catch {
        return error.FileNotFound;
    };

    return try Dir.cwd().readFileAlloc(io, filePath, allocator, Io.Limit.limited(10 * 1024 * 1024));
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

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

    const content = try openFile(filePath, gpa, io);
    defer gpa.free(content);

    var lexer = Lexer.init(content);
    var parser = try Parser.init(&lexer, gpa);
    defer parser.deinit();
    const program = try parser.parseProgram();

    var env_ = try Environment.initWithIo(gpa, null, io);
    defer env_.deinit();

    for (program) |stmt| {
        _ = try evaluate(stmt, &env_);
    }
}
