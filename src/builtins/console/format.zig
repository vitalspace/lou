const std = @import("std");
const Types = @import("../../types/types.zig");
const Env = @import("../../evaluator.zig").Environment;
const ansi = @import("../../utils/ansi.zig");
const number_format = @import("../number/format.zig");
const typedArrayMod = @import("../typedarray.zig");

const MaxLineWidth = 80;

pub const Stream = enum { stdout, stderr };

/// Options accepted by `console.dir` (and reused by the table renderer).
/// `depth = null` means unlimited; `max_array_length = null` means no
/// truncation.
pub const InspectOptions = struct {
    depth: ?usize = 2,
    colors: ?bool = null,
    max_array_length: ?usize = 100,
    sorted: bool = false,
};

const SeenMap = std.AutoHashMapUnmanaged(usize, void);

const Ctx = struct {
    use_ansi: bool,
    env: *Env,
    depth: ?usize,
    max_array_length: ?usize,
    sorted: bool,
    seen: *SeenMap,
};

pub fn truthy(v: Types.Value) bool {
    return switch (v) {
        .boolean => |b| b,
        .float => |f| f != 0.0 and !std.math.isNan(f),
        .integer => |i| i != 0,
        .big_int => |b| !b.eqlZero(),
        .string => |s| s.len > 0,
        .void, .null, .hole => false,
        else => true,
    };
}

fn valueDisplayWidth(v: Types.Value) usize {
    return switch (v) {
        .integer => 4,
        .float => 12,
        .string => |s| 2 + s.len,
        .boolean => |b| if (b) 4 else 5,
        .void => 9,
        .null => 4,
        .hole => 6,
        .array => 10,
        else => 8,
    };
}

/// Width of the token V8 prints for a run of N holes, i.e. "<N empty item(s)>".
fn holeRunWidth(count: usize) usize {
    var digits: usize = 1;
    var n = count;
    while (n >= 10) {
        n /= 10;
        digits += 1;
    }
    return 9 + digits + if (count == 1) @as(usize, 4) else 5;
}

fn printHoleRun(out: anytype, count: usize, ctx: Ctx) void {
    const Gy = if (ctx.use_ansi) ansi.Gray else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";
    if (count == 1) {
        out.print("{s}<1 empty item>{s}", .{ Gy, R }) catch {};
    } else {
        out.print("{s}<{d} empty items>{s}", .{ Gy, count, R }) catch {};
    }
}

fn shouldFormatArrayWrapped(a: *Types.ArrayObject) bool {
    var total: usize = 4;
    var i: usize = 0;
    while (i < a.elements.items.len) {
        if (a.elements.items[i] == .hole) {
            var run: usize = 1;
            while (i + run < a.elements.items.len and a.elements.items[i + run] == .hole) run += 1;
            total += holeRunWidth(run) + 2;
            i += run;
        } else {
            total += valueDisplayWidth(a.elements.items[i]) + 2;
            i += 1;
        }
    }
    return total > MaxLineWidth;
}

fn printFloat(out: anytype, f: f64, color: []const u8, reset: []const u8, env: *Types.Environment) void {
    // `String(-0)` is "0", but console inspection shows `-0`.
    if (f == 0 and std.math.signbit(f)) {
        out.print("{s}-0{s}", .{ color, reset }) catch {};
        return;
    }
    var buf = std.ArrayList(u8).initCapacity(env.allocator, 24) catch return;
    defer buf.deinit(env.allocator);
    number_format.appendFloat(env.allocator, &buf, f);
    out.print("{s}{s}{s}", .{ color, buf.items, reset }) catch {};
}

fn isContainer(v: Types.Value) bool {
    return switch (v) {
        .array, .js_object => true,
        else => false,
    };
}

fn printPlaceholder(out: anytype, value: Types.Value, ctx: Ctx) void {
    const C = if (ctx.use_ansi) ansi.Cyan else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";
    switch (value) {
        .array => out.print("{s}[Array]{s}", .{ C, R }) catch {},
        .js_object => out.print("{s}[Object]{s}", .{ C, R }) catch {},
        else => {},
    }
}

fn childCtx(ctx: Ctx) Ctx {
    return .{
        .use_ansi = ctx.use_ansi,
        .env = ctx.env,
        .depth = if (ctx.depth) |d| if (d > 0) d - 1 else 0 else null,
        .max_array_length = ctx.max_array_length,
        .sorted = ctx.sorted,
        .seen = ctx.seen,
    };
}

fn printChild(out: anytype, value: Types.Value, ctx: Ctx) void {
    if (ctx.depth) |d| {
        if (d == 0 and isContainer(value)) {
            printPlaceholder(out, value, ctx);
            return;
        }
    }
    printValueCtx(out, value, childCtx(ctx));
}

fn printArrayInline(out: anytype, a: *Types.ArrayObject, ctx: Ctx) void {
    out.print("[ ", .{}) catch {};
    const total = a.elements.items.len;
    const limit = if (ctx.max_array_length) |max| @min(max, total) else total;
    var j: usize = 0;
    while (j < limit) {
        if (j > 0) out.print(", ", .{}) catch {};
        const elem = a.elements.items[j];
        if (elem == .hole) {
            var run: usize = 1;
            while (j + run < limit and a.elements.items[j + run] == .hole) run += 1;
            printHoleRun(out, run, ctx);
            j += run;
        } else {
            printChild(out, elem, ctx);
            j += 1;
        }
    }
    if (limit < total) {
        if (limit > 0) out.print(", ", .{}) catch {};
        out.print("... {d} more items", .{total - limit}) catch {};
    }
    if (a.extras) |extras| {
        const known_keys = [_][]const u8{ "index", "input", "groups" };
        for (known_keys) |key| {
            if (extras.properties.get(key)) |val| {
                out.print(", {s}: ", .{key}) catch {};
                printChild(out, val, ctx);
            }
        }
        var it = extras.properties.iterator();
        while (it.next()) |entry| {
            var is_known = false;
            for (known_keys) |k| {
                if (std.mem.eql(u8, entry.key_ptr.*, k)) {
                    is_known = true;
                    break;
                }
            }
            if (!is_known and !std.mem.startsWith(u8, entry.key_ptr.*, "@@")) {
                out.print(", {s}: ", .{entry.key_ptr.*}) catch {};
                printChild(out, entry.value_ptr.*, ctx);
            }
        }
    }
    out.print(" ]", .{}) catch {};
}

fn printArrayWrapped(out: anytype, a: *Types.ArrayObject, ctx: Ctx) void {
    out.print("[ ", .{}) catch {};
    const total = a.elements.items.len;
    const limit = if (ctx.max_array_length) |max| @min(max, total) else total;
    var j: usize = 0;
    while (j < limit) {
        if (j > 0) {
            out.print(", ", .{}) catch {};
            if ((j % 6) == 0) out.print("\n  ", .{}) catch {};
        }
        const elem = a.elements.items[j];
        if (elem == .hole) {
            var run: usize = 1;
            while (j + run < limit and a.elements.items[j + run] == .hole) run += 1;
            printHoleRun(out, run, ctx);
            j += run;
        } else {
            printChild(out, elem, ctx);
            j += 1;
        }
    }
    if (limit < total) {
        if (limit > 0) out.print(", ", .{}) catch {};
        out.print("... {d} more items", .{total - limit}) catch {};
    }
    out.print("\n]", .{}) catch {};
}

fn isInternalKey(key: []const u8) bool {
    return std.mem.startsWith(u8, key, "@@");
}

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn printObjectEntry(out: anytype, key: []const u8, value: Types.Value, ctx: Ctx) void {
    var is_numeric_key = false;
    if (key.len > 0) {
        var all_valid = true;
        var has_digit = false;
        for (key) |c| {
            if (c >= '0' and c <= '9') {
                has_digit = true;
            } else if (c != '.') {
                all_valid = false;
                break;
            }
        }
        is_numeric_key = all_valid and has_digit;
    }
    if (is_numeric_key) {
        out.print("'{s}': ", .{key}) catch {};
    } else {
        out.print("{s}: ", .{key}) catch {};
    }
    printChild(out, value, ctx);
}

fn printObject(out: anytype, o: *Types.ObjectValue, ctx: Ctx) void {
    const addr = @intFromPtr(o);
    const C = if (ctx.use_ansi) ansi.Cyan else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";
    if (ctx.seen.contains(addr)) {
        out.print("{s}[Circular *1]{s}", .{ C, R }) catch {};
        return;
    }
    ctx.seen.put(ctx.env.allocator, addr, {}) catch {};
    defer _ = ctx.seen.remove(addr);

    var keys = std.ArrayList([]const u8).initCapacity(ctx.env.allocator, o.properties.map.count()) catch {
        out.print("{{}}", .{}) catch {};
        return;
    };
    defer keys.deinit(ctx.env.allocator);
    var it = o.properties.iterator();
    while (it.next()) |entry| {
        if (!isInternalKey(entry.key_ptr.*)) keys.append(ctx.env.allocator, entry.key_ptr.*) catch {};
    }
    if (ctx.sorted) std.mem.sort([]const u8, keys.items, {}, lessThanString);
    if (keys.items.len == 0) {
        out.print("{{}}", .{}) catch {};
        return;
    }

    out.print("{{ ", .{}) catch {};
    for (keys.items, 0..) |key, i| {
        if (i > 0) out.print(", ", .{}) catch {};
        const value = o.properties.get(key) orelse continue;
        printObjectEntry(out, key, value, ctx);
    }
    out.print(" }}", .{}) catch {};
}

fn printArray(out: anytype, a: *Types.ArrayObject, ctx: Ctx) void {
    const addr = @intFromPtr(a);
    const C = if (ctx.use_ansi) ansi.Cyan else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";
    if (ctx.seen.contains(addr)) {
        out.print("{s}[Circular *1]{s}", .{ C, R }) catch {};
        return;
    }
    ctx.seen.put(ctx.env.allocator, addr, {}) catch {};
    defer _ = ctx.seen.remove(addr);

    if (a.elements.items.len == 0 and a.extras == null) {
        out.print("[]", .{}) catch {};
    } else if (shouldFormatArrayWrapped(a)) {
        printArrayWrapped(out, a, ctx);
    } else {
        printArrayInline(out, a, ctx);
    }
}

fn typedElementWidth(value: Types.Value, env: *Env) usize {
    return switch (value) {
        .integer => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk 0;
            break :blk s.len;
        },
        .float => |f| blk: {
            var buf = std.ArrayList(u8).empty;
            defer buf.deinit(env.allocator);
            number_format.appendFloat(env.allocator, &buf, f);
            break :blk buf.items.len;
        },
        .big_int => |b| blk: {
            const digits = b.toString(env.allocator) catch break :blk 1;
            defer env.allocator.free(digits);
            break :blk digits.len + 1;
        },
        .string => |s| s.len + 2,
        .boolean => |b| if (b) 4 else 5,
        .void => 9,
        .null => 4,
        else => 9,
    };
}

fn printTypedArray(out: anytype, value: Types.Value, ctx: Ctx) void {
    const kind = typedArrayMod.getKind(value) orelse return;
    const name = typedArrayMod.kindName(kind);
    const len = typedArrayMod.getLength(value);
    const C = if (ctx.use_ansi) ansi.Cyan else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";

    if (len == 0) {
        out.print("{s}{s}(0){s} []", .{ C, name, R }) catch {};
        return;
    }

    var total: usize = name.len + 8;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        total += typedElementWidth(typedArrayMod.getElement(value, i, ctx.env), ctx.env) + 2;
    }

    if (total <= 72) {
        out.print("{s}{s}({d}){s} [ ", .{ C, name, len, R }) catch {};
        i = 0;
        while (i < len) : (i += 1) {
            if (i > 0) out.print(", ", .{}) catch {};
            printChild(out, typedArrayMod.getElement(value, i, ctx.env), ctx);
        }
        out.print(" ]", .{}) catch {};
        return;
    }

    out.print("{s}{s}({d}){s} [\n", .{ C, name, len, R }) catch {};
    i = 0;
    while (i < len) : (i += 1) {
        out.print("  ", .{}) catch {};
        printChild(out, typedArrayMod.getElement(value, i, ctx.env), ctx);
        if (i + 1 < len) out.print(",", .{}) catch {};
        out.print("\n", .{}) catch {};
    }
    out.print("]", .{}) catch {};
}

fn printValueCtx(out: anytype, value: Types.Value, ctx: Ctx) void {
    const Y = if (ctx.use_ansi) ansi.Yellow else "";
    const G = if (ctx.use_ansi) ansi.Green else "";
    const C = if (ctx.use_ansi) ansi.Cyan else "";
    const Red = if (ctx.use_ansi) ansi.Red else "";
    const B = if (ctx.use_ansi) ansi.Bold else "";
    const BOff = if (ctx.use_ansi) ansi.BoldOff else "";
    const Gy = if (ctx.use_ansi) ansi.Gray else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";

    switch (value) {
        .integer => |int_val| out.print("{s}{d}{s}", .{ Y, int_val, R }) catch {},
        .float => |f| printFloat(out, f, Y, R, ctx.env),
        .big_int => |b| {
            const digits = b.toString(ctx.env.allocator) catch return;
            defer ctx.env.allocator.free(digits);
            out.print("{s}{s}n{s}", .{ Y, digits, R }) catch {};
        },
        .string => |s| out.print("{s}'{s}'{s}", .{ G, s, R }) catch {},
        .boolean => |b| out.print("{s}{}{s}", .{ Y, b, R }) catch {},
        .array => |a| printArray(out, a, ctx),
        .hole => out.print("{s}<empty>{s}", .{ Gy, R }) catch {},
        .regexp => |r| {
            out.print("{s}/{s}{s}{s}{s}{s}/{s}", .{ G, R, Y, r.pattern, R, G, R }) catch {};
            if (r.flags.len > 0) out.print("{s}{s}{s}", .{ Red, r.flags, R }) catch {};
        },
        .void => out.print("{s}undefined{s}", .{ Gy, R }) catch {},
        .null => out.print("{s}null{s}", .{ B, BOff }) catch {},
        .object => out.print("{s}[object]{s}", .{ C, R }) catch {},
        .closure => out.print("{s}[closure]{s}", .{ C, R }) catch {},
        .function => out.print("{s}[function]{s}", .{ C, R }) catch {},
        .iterator => out.print("{s}[object Array Iterator]{s}", .{ C, R }) catch {},
        .generator => out.print("{s}[generator]{s}", .{ C, R }) catch {},
        .symbol => |sym| {
            if (sym.id <= @backingInt(Types.WellKnownSymbol.asyncIterator)) {
                out.print("{s}Symbol(Symbol.{s}){s}", .{ G, sym.description, R }) catch {};
            } else {
                out.print("{s}Symbol({s}){s}", .{ G, sym.description, R }) catch {};
            }
        },
        .js_object => |o| {
            if (typedArrayMod.isTypedArray(value)) {
                printTypedArray(out, value, ctx);
            } else {
                printObject(out, o, ctx);
            }
        },
        .array_iterator => |a| printArray(out, a, ctx),
    }
}

pub fn printArgsCtx(out: anytype, args: []const Types.Value, ctx: Ctx) void {
    const G = if (ctx.use_ansi) ansi.Green else "";
    const R = if (ctx.use_ansi) ansi.DefaultForeground else "";
    for (args, 0..) |arg, i| {
        if (i > 0) out.print(" ", .{}) catch {};
        if (arg == .string) {
            out.print("{s}{s}{s}", .{ G, arg.string, R }) catch {};
        } else {
            printValueCtx(out, arg, ctx);
        }
    }
}

fn makeCtx(env: *Env, options: InspectOptions, seen: *SeenMap) Ctx {
    const use_ansi = options.colors orelse if (env.io) |io| ansi.supportsAnsi(io, env.root().ansi_disabled) else false;
    return .{
        .use_ansi = use_ansi,
        .env = env,
        .depth = options.depth,
        .max_array_length = options.max_array_length,
        .sorted = options.sorted,
        .seen = seen,
    };
}

pub fn printValueToOptions(out: anytype, value: Types.Value, options: InspectOptions, env: *Types.Environment) void {
    var seen: SeenMap = .{};
    defer seen.deinit(env.allocator);
    const ctx = makeCtx(env, options, &seen);
    printValueCtx(out, value, ctx);
}

pub fn printValueTo(out: anytype, value: Types.Value, use_ansi: bool, env: *Types.Environment) void {
    printValueToOptions(out, value, .{ .colors = use_ansi }, env);
}

pub fn printArgs(out: anytype, args: []const Types.Value, use_ansi: bool, env: *Types.Environment) void {
    var seen: SeenMap = .{};
    defer seen.deinit(env.allocator);
    const ctx = makeCtx(env, .{ .colors = use_ansi }, &seen);
    printArgsCtx(out, args, ctx);
}

fn indent(out: anytype, env: *Types.Environment) void {
    var depth = env.root().console_group_depth;
    while (depth > 0) : (depth -= 1) out.print("  ", .{}) catch {};
}

fn fileFor(stream: Stream) std.Io.File {
    return switch (stream) {
        .stdout => std.Io.File.stdout(),
        .stderr => std.Io.File.stderr(),
    };
}

pub fn writeLineOptions(env: *Types.Environment, stream: Stream, args: []const Types.Value, prefix: ?[]const u8, options: InspectOptions) void {
    const io = env.io orelse return;
    var seen: SeenMap = .{};
    defer seen.deinit(env.allocator);
    const ctx = makeCtx(env, options, &seen);
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.Writer.initStreaming(fileFor(stream), io, &buf);
    const out = &file_writer.interface;
    indent(out, env);
    if (prefix) |p| out.print("{s}", .{p}) catch {};
    printArgsCtx(out, args, ctx);
    out.print("\n", .{}) catch {};
    file_writer.flush() catch {};
}

pub fn writeLine(env: *Types.Environment, stream: Stream, args: []const Types.Value, prefix: ?[]const u8) void {
    writeLineOptions(env, stream, args, prefix, .{});
}

pub fn writeFmt(env: *Types.Environment, stream: Stream, comptime fmt: []const u8, args: anytype) void {
    const io = env.io orelse return;
    var buf: [1024]u8 = undefined;
    var file_writer = std.Io.File.Writer.initStreaming(fileFor(stream), io, &buf);
    const out = &file_writer.interface;
    indent(out, env);
    out.print(fmt, args) catch {};
    out.print("\n", .{}) catch {};
    file_writer.flush() catch {};
}

const StringOut = struct {
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),

    pub fn print(self: *StringOut, comptime fmt: []const u8, args: anytype) !void {
        // Append directly: table/dir format thousands of tokens, and allocating
        // a temporary string for every `print` dominates their cost.
        try self.buf.print(self.allocator, fmt, args);
    }
};

pub fn valueToOwned(env: *Types.Environment, value: Types.Value, options: InspectOptions) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(env.allocator, 32);
    errdefer buf.deinit(env.allocator);
    var out = StringOut{ .allocator = env.allocator, .buf = &buf };
    printValueToOptions(&out, value, options, env);
    return buf.toOwnedSlice(env.allocator);
}

pub fn writeText(env: *Types.Environment, stream: Stream, text: []const u8) void {
    const io = env.io orelse return;
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.Writer.initStreaming(fileFor(stream), io, &buf);
    const out = &file_writer.interface;
    indent(out, env);
    out.writeAll(text) catch {};
    out.print("\n", .{}) catch {};
    file_writer.flush() catch {};
}

/// Write multiple lines with group indentation and a single flush. Used by
/// `console.table`, which would otherwise flush once per rendered row.
pub fn writeTextBlock(env: *Types.Environment, stream: Stream, text: []const u8) void {
    const io = env.io orelse return;
    var buf: [16 * 1024]u8 = undefined;
    var file_writer = std.Io.File.Writer.initStreaming(fileFor(stream), io, &buf);
    const out = &file_writer.interface;
    var rest = text;
    while (rest.len > 0) {
        indent(out, env);
        if (std.mem.indexOfScalar(u8, rest, '\n')) |newline| {
            out.writeAll(rest[0..newline]) catch {};
            out.print("\n", .{}) catch {};
            rest = rest[newline + 1 ..];
        } else {
            out.writeAll(rest) catch {};
            break;
        }
    }
    out.print("\n", .{}) catch {};
    file_writer.flush() catch {};
}

const TestOut = struct {
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),

    pub fn print(self: *TestOut, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.buf.appendSlice(self.allocator, text);
    }
};

test "console float formatting uses JS Number#toString" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var buf = try std.ArrayList(u8).initCapacity(std.testing.allocator, 0);
    defer buf.deinit(std.testing.allocator);
    var out = TestOut{ .allocator = std.testing.allocator, .buf = &buf };

    const cases = [_]struct { v: f64, want: []const u8 }{
        .{ .v = 1e21, .want = "1e+21" },
        .{ .v = 1e-7, .want = "1e-7" },
        .{ .v = std.math.inf(f64), .want = "Infinity" },
        .{ .v = -std.math.inf(f64), .want = "-Infinity" },
        .{ .v = -0.0, .want = "-0" },
        .{ .v = std.math.nan(f64), .want = "NaN" },
        .{ .v = 0.30000000000000004, .want = "0.30000000000000004" },
    };
    for (cases) |c| {
        buf.clearRetainingCapacity();
        printValueTo(&out, .{ .float = c.v }, false, &env);
        try std.testing.expectEqualStrings(c.want, buf.items);
    }
}

test "console inspect colors match Node palette" {
    var env: Env = undefined;
    env = try Env.init(std.testing.allocator, null);
    defer env.deinit();
    var buf = try std.ArrayList(u8).initCapacity(std.testing.allocator, 0);
    defer buf.deinit(std.testing.allocator);
    var out = TestOut{ .allocator = std.testing.allocator, .buf = &buf };

    const cases = [_]struct { value: Types.Value, want: []const u8 }{
        .{ .value = .{ .integer = 1 }, .want = "\x1b[33m1\x1b[39m" },
        .{ .value = .{ .float = 1.5 }, .want = "\x1b[33m1.5\x1b[39m" },
        .{ .value = .{ .string = "x" }, .want = "\x1b[32m'x'\x1b[39m" },
        .{ .value = .{ .boolean = true }, .want = "\x1b[33mtrue\x1b[39m" },
        .{ .value = .{ .null = {} }, .want = "\x1b[1mnull\x1b[22m" },
        .{ .value = .{ .void = {} }, .want = "\x1b[90mundefined\x1b[39m" },
    };
    for (cases) |c| {
        buf.clearRetainingCapacity();
        printValueToOptions(&out, c.value, .{ .colors = true }, &env);
        try std.testing.expectEqualStrings(c.want, buf.items);
    }

    const obj = try Types.ObjectValue.init(std.testing.allocator);
    defer obj.deinit();
    try obj.properties.put("a", .{ .integer = 1 });
    buf.clearRetainingCapacity();
    printValueToOptions(&out, .{ .js_object = obj }, .{ .colors = true }, &env);
    try std.testing.expectEqualStrings("{ a: \x1b[33m1\x1b[39m }", buf.items);
}
