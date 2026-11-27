const std = @import("std");
const Types = @import("../../types/types.zig");
const Ast = @import("../../ast.zig");
const RegexEngine = @import("regex.zig");
const Environment = @import("../../evaluator.zig").Environment;

fn cachedRegexDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const re: *RegexEngine.Regex = @alignCast(@ptrCast(ptr));
    re.deinit();
    allocator.destroy(re);
}

fn getOrCompile(regexp: *Types.RegExpValue) !*RegexEngine.Regex {
    if (regexp.cached) |c| {
        return @as(*RegexEngine.Regex, @alignCast(@ptrCast(c)));
    }
    const compiled = try regexp.allocator.create(RegexEngine.Regex);
    compiled.* = try RegexEngine.Regex.compile(regexp.allocator, regexp.pattern, .{
        .global = regexp.global,
        .ignore_case = regexp.ignore_case,
        .multiline = regexp.multiline,
        .dot_all = regexp.dot_all,
        .unicode = regexp.unicode,
        .sticky = regexp.sticky,
        .has_indices = regexp.has_indices,
    });
    regexp.cached = @ptrCast(compiled);
    regexp.cached_deinit = cachedRegexDeinit;
    return compiled;
}

pub const CaptureInfo = struct {
    idx: usize,
    len: usize,
};

pub const NamedCaptureInfo = struct {
    name: []const u8,
    idx: usize,
    len: usize,
};

pub const ExecResult = struct {
    idx: usize,
    len: usize,
    captures: []CaptureInfo,
    named: ?[]NamedCaptureInfo,
    indices: ?[]?CaptureInfo, // null = capture didn't participate

    pub fn deinit(self: *ExecResult, allocator: std.mem.Allocator) void {
        for (self.captures) |_| {}
        allocator.free(self.captures);
        if (self.named) |n| {
            for (n) |nc| {
                allocator.free(nc.name);
            }
            allocator.free(n);
        }
        if (self.indices) |idx| {
            allocator.free(idx);
        }
    }
};

fn vmFlagsFrom(f: RegexEngine.Flags) RegexEngine.VmFlags {
    return .{
        .global = f.global,
        .ignore_case = f.ignore_case,
        .multiline = f.multiline,
        .dot_all = f.dot_all,
        .unicode = f.unicode,
        .sticky = f.sticky,
        .has_indices = f.has_indices,
    };
}

pub fn findMatch(input: []const u8, start: usize, regexp: *Types.RegExpValue) ?struct { idx: usize, len: usize } {
    var re = getOrCompile(regexp) catch return null;

    var state = RegexEngine.ExecState{};
    state.last_index = @as(u32, @intCast(start));
    const flags = RegexEngine.Flags{
        .global = true,
        .ignore_case = regexp.ignore_case,
        .multiline = regexp.multiline,
        .dot_all = regexp.dot_all,
        .unicode = regexp.unicode,
        .sticky = regexp.sticky,
    };
    const vm_flags = vmFlagsFrom(flags);
    var result = re.vm.exec(input, &state, vm_flags) catch return null;
    if (result) |_| {
        var m = &result.?;
        defer m.deinit(regexp.allocator);
        return .{ .idx = m.span.start, .len = m.span.end - m.span.start };
    }
    return null;
}

pub fn execMatchAt(input: []const u8, start: usize, regexp: *Types.RegExpValue) ?ExecResult {
    var re = getOrCompile(regexp) catch return null;

    var state = RegexEngine.ExecState{};
    state.last_index = @as(u32, @intCast(start));
    const flags = RegexEngine.Flags{
        .global = true,
        .ignore_case = regexp.ignore_case,
        .multiline = regexp.multiline,
        .dot_all = regexp.dot_all,
        .unicode = regexp.unicode,
        .sticky = regexp.sticky,
        .has_indices = regexp.has_indices,
    };
    const vm_flags = vmFlagsFrom(flags);
    var result = re.vm.exec(input, &state, vm_flags) catch return null;
    if (result) |_| {
        var m = &result.?;
        const allocator = regexp.allocator;
        const span_start = m.span.start;
        const span_end = m.span.end;
        // Copy captures
        var caps = allocator.alloc(CaptureInfo, m.captures.len) catch {
            m.deinit(allocator);
            return null;
        };
        for (m.captures, 0..) |cap, i| {
            if (cap.span) |s| {
                caps[i] = .{ .idx = s.start, .len = s.end - s.start };
            } else {
                caps[i] = .{ .idx = 0, .len = 0 };
            }
        }
        // Copy named captures
        var named: ?[]NamedCaptureInfo = null;
        if (m.named) |nc| {
            named = allocator.alloc(NamedCaptureInfo, nc.len) catch {
                allocator.free(caps);
                m.deinit(allocator);
                return null;
            };
            for (nc, 0..) |n, i| {
                const name_dup = allocator.dupe(u8, n.name) catch {
                    allocator.free(caps);
                    if (named) |n2| allocator.free(n2);
                    m.deinit(allocator);
                    return null;
                };
                if (n.span) |s| {
                    named.?[i] = .{ .name = name_dup, .idx = s.start, .len = s.end - s.start };
                } else {
                    named.?[i] = .{ .name = name_dup, .idx = 0, .len = 0 };
                }
            }
        }
        var match_indices: ?[]?CaptureInfo = null;
        if (m.indices != null) {
            const count = 1 + m.captures.len;
            match_indices = allocator.alloc(?CaptureInfo, count) catch {
                allocator.free(caps);
                if (named) |n| {
                    for (n) |nc| allocator.free(nc.name);
                    allocator.free(n);
                }
                m.deinit(allocator);
                return null;
            };
            match_indices.?[0] = CaptureInfo{ .idx = span_start, .len = span_end - span_start };
            for (m.captures, 0..) |cap, j| {
                if (cap.span) |s| {
                    match_indices.?[j + 1] = CaptureInfo{ .idx = s.start, .len = s.end - s.start };
                } else {
                    match_indices.?[j + 1] = null;
                }
            }
        }

        m.deinit(allocator);
        return ExecResult{
            .idx = span_start,
            .len = span_end - span_start,
            .captures = caps,
            .named = named,
            .indices = match_indices,
        };
    }
    return null;
}

pub fn execMatch(input: []const u8, regexp: *Types.RegExpValue) ?ExecResult {
    return execMatchAt(input, 0, regexp);
}

pub fn testMatch(input: []const u8, regexp: *Types.RegExpValue) ?usize {
    var re = getOrCompile(regexp) catch return null;
    const flags = RegexEngine.Flags{
        .global = regexp.global,
        .ignore_case = regexp.ignore_case,
        .multiline = regexp.multiline,
        .dot_all = regexp.dot_all,
        .unicode = regexp.unicode,
        .sticky = regexp.sticky,
        .has_indices = regexp.has_indices,
    };
    return if (re.testMatch(input, flags) catch false) 1 else null;
}

/// Returns the RegExp flags string (e.g. "gi" for /pattern/gi).
/// The slice points into the owned flags buffer, not a stack local.
fn flagsString(re: *Types.RegExpValue) []const u8 {
    return re.flags;
}

/// Get a RegExp property value (source, flags, global, lastIndex, etc.)
pub fn getProperty(regexp: *Types.RegExpValue, prop: []const u8) Types.Value {
    if (std.mem.eql(u8, prop, "source")) {
        return .{ .string = regexp.pattern };
    }
    if (std.mem.eql(u8, prop, "flags")) {
        return .{ .string = flagsString(regexp) };
    }
    if (std.mem.eql(u8, prop, "global")) {
        return .{ .boolean = regexp.global };
    }
    if (std.mem.eql(u8, prop, "ignoreCase")) {
        return .{ .boolean = regexp.ignore_case };
    }
    if (std.mem.eql(u8, prop, "multiline")) {
        return .{ .boolean = regexp.multiline };
    }
    if (std.mem.eql(u8, prop, "dotAll")) {
        return .{ .boolean = regexp.dot_all };
    }
    if (std.mem.eql(u8, prop, "unicode")) {
        return .{ .boolean = regexp.unicode };
    }
    if (std.mem.eql(u8, prop, "sticky")) {
        return .{ .boolean = regexp.sticky };
    }
    if (std.mem.eql(u8, prop, "hasIndices")) {
        return .{ .boolean = regexp.has_indices };
    }
    if (std.mem.eql(u8, prop, "lastIndex")) {
        return .{ .integer = @as(i64, @intCast(regexp.lastIndex())) };
    }
    return .{ .void = {} };
}

/// Set a RegExp property (currently only lastIndex is supported)
pub fn setProperty(regexp: *Types.RegExpValue, prop: []const u8, val: Types.Value) !void {
    if (std.mem.eql(u8, prop, "lastIndex")) {
        const idx = switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            .float => |f| @as(u32, @intFromFloat(f)),
            else => return error.InvalidAssignment,
        };
        regexp.setLastIndex(idx);
        return;
    }
    return error.InvalidAssignment;
}

/// RegExp.prototype.toString() — returns "/pattern/flags"
pub fn toString(regexp: *Types.RegExpValue, allocator: std.mem.Allocator, env: *Environment) Types.Value {
    var flag_count: usize = 0;
    if (regexp.global) flag_count += 1;
    if (regexp.ignore_case) flag_count += 1;
    if (regexp.multiline) flag_count += 1;
    if (regexp.dot_all) flag_count += 1;
    if (regexp.unicode) flag_count += 1;
    if (regexp.sticky) flag_count += 1;
    if (regexp.has_indices) flag_count += 1;
    const total = 1 + regexp.pattern.len + 1 + flag_count;
    const buf = allocator.alloc(u8, total) catch return .{ .string = regexp.pattern };
    buf[0] = '/';
    @memcpy(buf[1..][0..regexp.pattern.len], regexp.pattern);
    var pos: usize = 1 + regexp.pattern.len;
    buf[pos] = '/';
    pos += 1;
    if (regexp.global) { buf[pos] = 'g'; pos += 1; }
    if (regexp.ignore_case) { buf[pos] = 'i'; pos += 1; }
    if (regexp.multiline) { buf[pos] = 'm'; pos += 1; }
    if (regexp.dot_all) { buf[pos] = 's'; pos += 1; }
    if (regexp.unicode) { buf[pos] = 'u'; pos += 1; }
    if (regexp.sticky) { buf[pos] = 'y'; pos += 1; }
    if (regexp.has_indices) { buf[pos] = 'd'; pos += 1; }
    env.owned_strings.append(allocator, buf) catch {};
    return .{ .string = buf };
}

/// Build the match array result for regex exec()
fn buildMatchArray(allocator: std.mem.Allocator, env: *Environment, input: []const u8, exec: *const ExecResult) !*Ast.ArrayObject {
    var arr = try Ast.ArrayObject.initExtras(allocator);
    errdefer {
        arr.deinit();
        allocator.destroy(arr);
    }
    // Push full match first
    const full_str = input[exec.idx .. exec.idx + exec.len];
    const full_owned = try allocator.dupe(u8, full_str);
    try env.owned_strings.append(allocator, full_owned);
    try arr.elements.append(allocator, .{ .string = full_owned });

    // Push captures
    for (exec.captures) |cap| {
        if (cap.len > 0) {
            const cap_str = input[cap.idx .. cap.idx + cap.len];
            const cap_owned = try allocator.dupe(u8, cap_str);
            try env.owned_strings.append(allocator, cap_owned);
            try arr.elements.append(allocator, .{ .string = cap_owned });
        } else {
            try arr.elements.append(allocator, .{ .void = {} });
        }
    }

    // extras: index, input, groups
    try arr.extras.?.properties.put("index", .{ .integer = @as(i64, @intCast(exec.idx)) });
    const input_owned = try allocator.dupe(u8, input);
    try env.owned_strings.append(allocator, input_owned);
    try arr.extras.?.properties.put("input", .{ .string = input_owned });

    if (exec.named) |nc| {
        if (nc.len > 0) {
            const groups = try Ast.ObjectValue.init(allocator);
            for (nc) |n| {
                const name_owned = try allocator.dupe(u8, n.name);
                try env.owned_strings.append(allocator, name_owned);
                if (n.len > 0) {
                    const n_str = input[n.idx .. n.idx + n.len];
                    const n_owned = try allocator.dupe(u8, n_str);
                    try env.owned_strings.append(allocator, n_owned);
                    try groups.properties.put(name_owned, .{ .string = n_owned });
                } else {
                    try groups.properties.put(name_owned, .{ .void = {} });
                }
            }
            try env.objects.append(allocator, groups);
            try arr.extras.?.properties.put("groups", .{ .js_object = groups });
        }
    }

    // Build indices array for /d flag
    if (exec.indices) |idxv| {
        const indices_arr = try Ast.ArrayObject.initExtras(allocator);
        for (idxv) |entry| {
            if (entry) |ei| {
                const inner = try Ast.ArrayObject.init(allocator);
                try inner.elements.append(allocator, .{ .integer = @as(i64, @intCast(ei.idx)) });
                try inner.elements.append(allocator, .{ .integer = @as(i64, @intCast(ei.idx + ei.len)) });
                try env.arrays.append(allocator, inner);
                try indices_arr.elements.append(allocator, .{ .array = inner });
            } else {
                try indices_arr.elements.append(allocator, .{ .void = {} });
            }
        }
        // Build indices.groups for named captures
        if (exec.named) |nc| {
            if (nc.len > 0) {
                const indices_groups = try Ast.ObjectValue.init(allocator);
                for (nc) |n| {
                    const name_owned = try allocator.dupe(u8, n.name);
                    try env.owned_strings.append(allocator, name_owned);
                    if (n.len > 0) {
                        const inner = try Ast.ArrayObject.init(allocator);
                        try inner.elements.append(allocator, .{ .integer = @as(i64, @intCast(n.idx)) });
                        try inner.elements.append(allocator, .{ .integer = @as(i64, @intCast(n.idx + n.len)) });
                        try env.arrays.append(allocator, inner);
                        try indices_groups.properties.put(name_owned, .{ .array = inner });
                    } else {
                        try indices_groups.properties.put(name_owned, .{ .void = {} });
                    }
                }
                try env.objects.append(allocator, indices_groups);
                try indices_arr.extras.?.properties.put("groups", .{ .js_object = indices_groups });
            }
        }
        try env.arrays.append(allocator, indices_arr);
        try arr.extras.?.properties.put("indices", .{ .array = indices_arr });
    }

    try env.arrays.append(allocator, arr);
    return arr;
}

/// Implements RegExp.prototype.test()
pub fn callTest(args: []Types.Value, env: *Environment) anyerror!Types.Value {
    const re_val = args[0];
    const input = if (args.len > 1) switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    } else "";

    // For global/sticky regexps, use lastIndex like exec
    if (re_val.regexp.global or re_val.regexp.sticky) {
        const start = re_val.regexp.lastIndex();
        const result = execMatchAt(input, start, re_val.regexp);
        if (result) |exec| {
            var mutable_exec = exec;
            defer mutable_exec.deinit(env.allocator);
            re_val.regexp.setLastIndex(@intCast(mutable_exec.idx + mutable_exec.len));
            return .{ .boolean = true };
        } else {
            re_val.regexp.setLastIndex(@as(u32, 0));
            return .{ .boolean = false };
        }
    }

    const result = testMatch(input, re_val.regexp);
    return .{ .boolean = result != null };
}

/// Implements RegExp.prototype.exec()
pub fn callExec(args: []Types.Value, env: *Environment) anyerror!Types.Value {
    const re_val = args[0];
    const input = if (args.len > 1) switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    } else "";

    // Per JS spec: non-global, non-sticky exec ignores lastIndex
    const use_lastindex = re_val.regexp.global or re_val.regexp.sticky;
    const start = if (use_lastindex) re_val.regexp.lastIndex() else 0;
    const result = execMatchAt(input, start, re_val.regexp);
    if (result) |exec| {
        var mutable_exec = exec;
        defer mutable_exec.deinit(env.allocator);
        // Update lastIndex for global/sticky regexps
        if (use_lastindex) {
            re_val.regexp.setLastIndex(@intCast(mutable_exec.idx + mutable_exec.len));
        }
        const arr = try buildMatchArray(env.allocator, env, input, &mutable_exec);
        return .{ .array = arr };
    }
    // No match: reset lastIndex for global/sticky
    if (use_lastindex) {
        re_val.regexp.setLastIndex(@as(u32, 0));
    }
    return .{ .null = {} };
}

// --- BuiltinFn wrappers for registration as prototype methods ---

/// Wrapper that matches Types.BuiltinFn signature for RegExp.prototype.test
fn RegExpTest(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return .{ .value = callTest(args, env) catch return .{ .value = .{ .void = {} } } };
}

/// Wrapper that matches Types.BuiltinFn signature for RegExp.prototype.exec
fn RegExpExec(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    return .{ .value = callExec(args, env) catch return .{ .value = .{ .null = {} } } };
}

/// Wrapper that matches Types.BuiltinFn signature for RegExp.prototype.toString
fn RegExpToString(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0 or args[0] != .regexp) {
        return .{ .value = .{ .string = "/(?:)/" } };
    }
    return .{ .value = toString(args[0].regexp, env.allocator, env) };
}

/// RegExp.prototype[@@match](string)
/// For non-global: returns exec match array or null.
/// For global: finds all matches, returns array of matched strings or null.
pub fn RegExpMatch(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or args[0] != .regexp) return .{ .value = .{ .null = {} } };
    const re = args[0].regexp;
    const input = switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    };

    if (re.global) {
        // Global match: find all matches, collect full match strings
        if (re.pattern.len == 0) return .{ .value = .{ .null = {} } };
        const results = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .null = {} } };
        env.arrays.append(env.allocator, results) catch return .{ .value = .{ .null = {} } };
        var pos: usize = 0;
        while (pos <= input.len) {
            if (findMatch(input, pos, re)) |match| {
                if (match.len == 0) {
                    pos = match.idx + 1;
                    continue;
                }
                const matched = input[match.idx .. match.idx + match.len];
                const owned = env.allocator.dupe(u8, matched) catch return .{ .value = .{ .null = {} } };
                env.owned_strings.append(env.allocator, owned) catch return .{ .value = .{ .null = {} } };
                results.elements.append(env.allocator, .{ .string = owned }) catch return .{ .value = .{ .null = {} } };
                pos = match.idx + match.len;
            } else {
                break;
            }
        }
        if (results.elements.items.len == 0) return .{ .value = .{ .null = {} } };
        return .{ .value = .{ .array = results } };
    }

    // Non-global: same as exec
    if (execMatch(input, re)) |exec| {
        var mutable_exec = exec;
        defer mutable_exec.deinit(env.allocator);
        const arr = buildMatchArray(env.allocator, env, input, &mutable_exec) catch return .{ .value = .{ .null = {} } };
        return .{ .value = .{ .array = arr } };
    }
    return .{ .value = .{ .null = {} } };
}

/// RegExp.prototype[@@replace](string, replacement)
pub fn RegExpReplace(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or args[0] != .regexp) return .{ .value = .{ .string = "" } };
    const re = args[0].regexp;
    const input = switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    };
    const replacement = if (args.len >= 3) switch (args[2]) {
        .string => |r| r,
        else => "",
    } else "";

    if (re.pattern.len == 0) {
        const result = env.allocator.dupe(u8, input) catch return .{ .value = .{ .string = "" } };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    }

    // Simple replacement (no capture refs) can use findMatch
    // Capture refs need execMatch
    const has_refs = std.mem.indexOf(u8, replacement, "$") != null;

    if (re.global) {
        var buf = std.ArrayList(u8).initCapacity(env.allocator, input.len) catch return .{ .value = .{ .string = "" } };
        var pos: usize = 0;
        while (pos <= input.len) {
            if (has_refs) {
                if (execMatchAt(input, pos, re)) |exec| {
                    var mutable_exec = exec;
                    defer mutable_exec.deinit(env.allocator);
                    if (mutable_exec.len == 0) {
                        buf.appendSlice(env.allocator, input[pos..]) catch {};
                        break;
                    }
                    buf.appendSlice(env.allocator, input[pos..mutable_exec.idx]) catch {};
                    // Expand $ refs
                    var ri: usize = 0;
                    while (ri < replacement.len) {
                        if (replacement[ri] == '$' and ri + 1 < replacement.len) {
                            const next = replacement[ri + 1];
                            if (next == '$') { buf.append(env.allocator, '$') catch {}; ri += 2; }
                            else if (next == '&') { buf.appendSlice(env.allocator, input[mutable_exec.idx..mutable_exec.idx + mutable_exec.len]) catch {}; ri += 2; }
                            else if (next == '`') { buf.appendSlice(env.allocator, input[0..mutable_exec.idx]) catch {}; ri += 2; }
                            else if (next == '\'') { buf.appendSlice(env.allocator, input[mutable_exec.idx + mutable_exec.len ..]) catch {}; ri += 2; }
                            else if (std.ascii.isDigit(next)) {
                                var num: usize = next - '0';
                                ri += 2;
                                while (ri < replacement.len and std.ascii.isDigit(replacement[ri])) {
                                    num = num * 10 + (replacement[ri] - '0');
                                    ri += 1;
                                }
                                if (num > 0 and num - 1 < mutable_exec.captures.len) {
                                    const cap = mutable_exec.captures[num - 1];
                                    if (cap.len > 0) buf.appendSlice(env.allocator, input[cap.idx..cap.idx + cap.len]) catch {};
                                }
                            } else { buf.append(env.allocator, replacement[ri]) catch {}; ri += 1; }
                        } else { buf.append(env.allocator, replacement[ri]) catch {}; ri += 1; }
                    }
                    pos = mutable_exec.idx + mutable_exec.len;
                } else {
                    buf.appendSlice(env.allocator, input[pos..]) catch {};
                    break;
                }
            } else {
                if (findMatch(input, pos, re)) |match| {
                    buf.appendSlice(env.allocator, input[pos..match.idx]) catch {};
                    buf.appendSlice(env.allocator, replacement) catch {};
                    pos = match.idx + match.len;
                } else {
                    buf.appendSlice(env.allocator, input[pos..]) catch {};
                    break;
                }
            }
        }
        const result = buf.toOwnedSlice(env.allocator) catch return .{ .value = .{ .string = "" } };
        env.owned_strings.append(env.allocator, result) catch {};
        return .{ .value = .{ .string = result } };
    } else {
        // Non-global: replace first match
        if (has_refs) {
            if (execMatchAt(input, 0, re)) |exec| {
                var mutable_exec = exec;
                defer mutable_exec.deinit(env.allocator);
                if (mutable_exec.len == 0) {
                    const result = env.allocator.dupe(u8, input) catch return .{ .value = .{ .string = "" } };
                    env.owned_strings.append(env.allocator, result) catch {};
                    return .{ .value = .{ .string = result } };
                }
                var buf = std.ArrayList(u8).initCapacity(env.allocator, input.len) catch return .{ .value = .{ .string = "" } };
                buf.appendSlice(env.allocator, input[0..mutable_exec.idx]) catch {};
                // Expand $ refs
                var ri: usize = 0;
                while (ri < replacement.len) {
                    if (replacement[ri] == '$' and ri + 1 < replacement.len) {
                        const next = replacement[ri + 1];
                        if (next == '$') { buf.append(env.allocator, '$') catch {}; ri += 2; }
                        else if (next == '&') { buf.appendSlice(env.allocator, input[mutable_exec.idx..mutable_exec.idx + mutable_exec.len]) catch {}; ri += 2; }
                        else if (next == '`') { buf.appendSlice(env.allocator, input[0..mutable_exec.idx]) catch {}; ri += 2; }
                        else if (next == '\'') { buf.appendSlice(env.allocator, input[mutable_exec.idx + mutable_exec.len ..]) catch {}; ri += 2; }
                        else if (std.ascii.isDigit(next)) {
                            var num: usize = next - '0';
                            ri += 2;
                            while (ri < replacement.len and std.ascii.isDigit(replacement[ri])) {
                                num = num * 10 + (replacement[ri] - '0');
                                ri += 1;
                            }
                            if (num > 0 and num - 1 < mutable_exec.captures.len) {
                                const cap = mutable_exec.captures[num - 1];
                                if (cap.len > 0) buf.appendSlice(env.allocator, input[cap.idx..cap.idx + cap.len]) catch {};
                            }
                        } else { buf.append(env.allocator, replacement[ri]) catch {}; ri += 1; }
                    } else { buf.append(env.allocator, replacement[ri]) catch {}; ri += 1; }
                }
                buf.appendSlice(env.allocator, input[mutable_exec.idx + mutable_exec.len ..]) catch {};
                const result = buf.toOwnedSlice(env.allocator) catch return .{ .value = .{ .string = "" } };
                env.owned_strings.append(env.allocator, result) catch {};
                return .{ .value = .{ .string = result } };
            }
            const result = env.allocator.dupe(u8, input) catch return .{ .value = .{ .string = "" } };
            env.owned_strings.append(env.allocator, result) catch {};
            return .{ .value = .{ .string = result } };
        } else {
            if (findMatch(input, 0, re)) |match| {
                var buf = std.ArrayList(u8).initCapacity(env.allocator, input.len) catch return .{ .value = .{ .string = "" } };
                buf.appendSlice(env.allocator, input[0..match.idx]) catch {};
                buf.appendSlice(env.allocator, replacement) catch {};
                buf.appendSlice(env.allocator, input[match.idx + match.len ..]) catch {};
                const result = buf.toOwnedSlice(env.allocator) catch return .{ .value = .{ .string = "" } };
                env.owned_strings.append(env.allocator, result) catch {};
                return .{ .value = .{ .string = result } };
            }
            const result = env.allocator.dupe(u8, input) catch return .{ .value = .{ .string = "" } };
            env.owned_strings.append(env.allocator, result) catch {};
            return .{ .value = .{ .string = result } };
        }
    }
}

/// RegExp.prototype[@@search](string) — returns index of first match or -1
pub fn RegExpSearch(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    _ = env;
    if (args.len < 2 or args[0] != .regexp) return .{ .value = .{ .integer = -1 } };
    const re = args[0].regexp;
    const input = switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    };

    if (findMatch(input, 0, re)) |match| {
        return .{ .value = .{ .integer = @as(i64, @intCast(match.idx)) } };
    }
    return .{ .value = .{ .integer = -1 } };
}

/// RegExp.prototype[@@split](string, limit) — splits string by regex matches
pub fn RegExpSplit(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or args[0] != .regexp) return .{ .value = .{ .void = {} } };
    const re = args[0].regexp;
    const input = switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    };

    const limit: ?usize = if (args.len >= 3) switch (args[2]) {
        .integer => |i| if (i < 0) null else @as(usize, @intCast(i)),
        .float => |f| if (f < 0) null else @as(usize, @intCast(@as(i64, @intFromFloat(f)))),
        .void, .null => null,
        else => null,
    } else null;

    const arr = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.arrays.append(env.allocator, arr) catch return .{ .value = .{ .void = {} } };

    if (re.pattern.len == 0) {
        // Empty regex: split into characters
        if (input.len == 0) {
            const owned = env.allocator.dupe(u8, "") catch return .{ .value = .{ .array = arr } };
            env.owned_strings.append(env.allocator, owned) catch {};
            arr.elements.append(env.allocator, .{ .string = owned }) catch {};
        } else {
            for (input, 0..) |_, i| {
                if (limit) |lim| { if (arr.elements.items.len >= lim) break; }
                const char = input[i .. i + 1];
                const owned = env.allocator.dupe(u8, char) catch return .{ .value = .{ .array = arr } };
                env.owned_strings.append(env.allocator, owned) catch {};
                arr.elements.append(env.allocator, .{ .string = owned }) catch {};
            }
        }
        return .{ .value = .{ .array = arr } };
    }

    var start: usize = 0;
    var found_any = false;
    while (start <= input.len) {
        if (limit) |lim| { if (arr.elements.items.len >= lim) break; }
        if (findMatch(input, start, re)) |match| {
            found_any = true;
            if (match.idx != start) {
                const segment = input[start .. match.idx];
                const owned = env.allocator.dupe(u8, segment) catch return .{ .value = .{ .array = arr } };
                env.owned_strings.append(env.allocator, owned) catch {};
                arr.elements.append(env.allocator, .{ .string = owned }) catch {};
                start = match.idx + match.len;
            } else {
                break;
            }
        } else {
            const segment = input[start..];
            const owned = env.allocator.dupe(u8, segment) catch return .{ .value = .{ .array = arr } };
            env.owned_strings.append(env.allocator, owned) catch {};
            arr.elements.append(env.allocator, .{ .string = owned }) catch {};
            break;
        }
    }
    if (!found_any and re.pattern.len > 0) {
        const owned = env.allocator.dupe(u8, input) catch return .{ .value = .{ .array = arr } };
        env.owned_strings.append(env.allocator, owned) catch {};
        arr.elements.append(env.allocator, .{ .string = owned }) catch {};
    }

    return .{ .value = .{ .array = arr } };
}

/// RegExp.prototype[@@matchAll](string) — returns an iterator over all matches
/// Each match is a full exec-style array with captures, index, input, and groups.
pub fn RegExpMatchAll(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len < 2 or args[0] != .regexp) return .{ .value = .{ .void = {} } };
    const re = args[0].regexp;
    const input = switch (args[1]) {
        .string => |s| s,
        .null => "",
        .void => "",
        else => "",
    };

    const results = Ast.ArrayObject.init(env.allocator) catch return .{ .value = .{ .void = {} } };
    env.arrays.append(env.allocator, results) catch return .{ .value = .{ .void = {} } };

    var pos: usize = 0;
    while (pos <= input.len) {
        if (execMatchAt(input, pos, re)) |match| {
            var mutable_exec = match;
            defer mutable_exec.deinit(env.allocator);
            const match_arr = buildMatchArray(env.allocator, env, input, &mutable_exec) catch return .{ .value = .{ .void = {} } };
            results.elements.append(env.allocator, .{ .array = match_arr }) catch return .{ .value = .{ .void = {} } };
            pos = mutable_exec.idx + mutable_exec.len;
            if (mutable_exec.len == 0) {
                pos += 1;
            }
        } else {
            break;
        }
    }

    var iter = Ast.ArrayIterator.initValues(env.allocator, results) catch return .{ .value = .{ .void = {} } };
    env.iterators.append(env.allocator, iter) catch {
        iter.deinit();
        return .{ .value = .{ .void = {} } };
    };
    return .{ .value = .{ .iterator = iter } };
}

const REGEXP_METHODS = [_]Types.BuiltinMethod{
    .{ .name = "test", .func = RegExpTest },
    .{ .name = "exec", .func = RegExpExec },
    .{ .name = "toString", .func = RegExpToString },
    .{ .name = "@@match", .func = RegExpMatch },
    .{ .name = "@@matchAll", .func = RegExpMatchAll },
    .{ .name = "@@replace", .func = RegExpReplace },
    .{ .name = "@@search", .func = RegExpSearch },
    .{ .name = "@@split", .func = RegExpSplit },
};

pub const REGEXP_OBJECT = Types.BuiltinObjectImpl{
    .name = "RegExp",
    .methods = &REGEXP_METHODS,
};
