const std = @import("std");
const metrics = @import("metrics.zig");
const PerfMetrics = metrics.PerfMetrics;
const PerfFunction = metrics.PerfFunction;

pub fn parsePerfStatOutput(stderr: []const u8) PerfMetrics {
    var p = PerfMetrics{};
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const val_part = blk: {
            if (std.mem.indexOf(u8, trimmed, "#")) |hash| {
                break :blk std.mem.trim(u8, trimmed[0..hash], " \t");
            }
            break :blk trimmed;
        };
        if (std.mem.lastIndexOfScalar(u8, val_part, ' ')) |space| {
            const num_str = val_part[0..space];
            const label = std.mem.trim(u8, val_part[space + 1 ..], " \t");
            const val = parseInt(num_str);
            const label_clean = stripPerfSuffix(label);
            if (std.mem.eql(u8, label_clean, "cycles")) {
                p.cycles = val;
            } else if (std.mem.eql(u8, label_clean, "instructions")) {
                p.instructions = val;
            } else if (std.mem.eql(u8, label_clean, "cache-misses")) {
                p.cache_misses = val;
            } else if (std.mem.eql(u8, label_clean, "cache-references")) {
                p.cache_refs = val;
            } else if (std.mem.eql(u8, label_clean, "branch-misses")) {
                p.branch_misses = val;
            } else if (std.mem.eql(u8, label_clean, "branches")) {
                p.branches = val;
            } else if (std.mem.indexOf(u8, label_clean, "stalled-cycles-frontend") != null) {
                p.stalled_frontend = val;
            } else if (std.mem.indexOf(u8, label_clean, "stalled-cycles-backend") != null) {
                p.stalled_backend = val;
            }
        }
    }
    if (p.instructions > 0 and p.cycles > 0)
        p.ipc = @as(f64, @floatFromInt(p.instructions)) / @as(f64, @floatFromInt(p.cycles));
    return p;
}

fn stripPerfSuffix(label: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, label, ':')) |colon| {
        return label[0..colon];
    }
    return label;
}

pub fn parsePerfReportOutput(output: []const u8, allocator: std.mem.Allocator) ![]PerfFunction {
    var list = std.ArrayList(PerfFunction).init(allocator);
    var lines = std.mem.splitScalar(u8, output, '\n');
    var in_table = false;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) { in_table = false; continue; }
        if (std.mem.indexOf(u8, trimmed, "Overhead")) |_| {
            if (std.mem.indexOf(u8, trimmed, "Source")) |_|
                in_table = true;
            continue;
        }
        if (in_table) {
            var parts = std.mem.splitScalar(u8, trimmed, ' ');
            const pct_str = parts.next() orelse continue;
            const pct = std.fmt.parseFloat(f64, pct_str) catch continue;
            const rest = std.mem.trim(u8, parts.rest(), " \t");
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon| {
                try list.append(allocator, .{
                    .overhead_pct = pct,
                    .symbol = try allocator.dupe(u8, rest[0..colon]),
                    .source = try allocator.dupe(u8, rest[colon + 1 ..]),
                });
            } else {
                try list.append(allocator, .{
                    .overhead_pct = pct,
                    .symbol = try allocator.dupe(u8, rest),
                    .source = "",
                });
            }
        }
    }
    return list.toOwnedSlice();
}

fn parseInt(s: []const u8) u64 {
    const trimmed = std.mem.trim(u8, s, " \t\r");
    if (trimmed.len == 0) return 0;
    var result: u64 = 0;
    for (trimmed) |c| {
        if (c >= '0' and c <= '9')
            result = result * 10 + (c - '0');
    }
    return result;
}
