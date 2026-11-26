const std = @import("std");
const Types = @import("../../types/types.zig");
const ansi = @import("../../utils/ansi.zig");
const format = @import("format.zig");

const Entry = struct {
    key: []const u8,
    value: Types.Value,
};

const Row = struct {
    index: []u8,
    entries: std.ArrayList(Entry),
    /// Formatted cell text, one slot per column. Computed once so widths and
    /// output do not format every value twice.
    rendered: []?[]u8 = &.{},
};

const DataKind = enum { objects, primitives };

fn isInternalKey(key: []const u8) bool {
    return std.mem.startsWith(u8, key, "@@");
}

fn isPlainObject(v: Types.Value) bool {
    return switch (v) {
        .js_object => |o| o.properties.get("@@type") == null,
        else => false,
    };
}

fn classify(data: Types.Value) ?DataKind {
    switch (data) {
        .array => |a| {
            var objects: usize = 0;
            var primitives: usize = 0;
            for (a.elements.items) |elem| {
                if (isPlainObject(elem)) objects += 1 else primitives += 1;
            }
            if (primitives == 0) return .objects;
            if (objects == 0) return .primitives;
            return null;
        },
        .js_object => |o| {
            if (o.properties.get("@@type") != null) return null;
            var objects: usize = 0;
            var primitives: usize = 0;
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                if (isInternalKey(entry.key_ptr.*)) continue;
                if (isPlainObject(entry.value_ptr.*)) objects += 1 else primitives += 1;
            }
            if (primitives == 0) return .objects;
            if (objects == 0) return .primitives;
            return null;
        },
        else => return null,
    }
}

fn appendObjectEntries(row: *Row, o: *Types.ObjectValue, allocator: std.mem.Allocator) !void {
    var it = o.properties.iterator();
    while (it.next()) |entry| {
        if (isInternalKey(entry.key_ptr.*)) continue;
        try row.entries.append(allocator, .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
    }
}

fn addRow(rows: *std.ArrayList(Row), allocator: std.mem.Allocator, index: []const u8) !*Row {
    var row = Row{
        .index = try allocator.dupe(u8, index),
        .entries = try std.ArrayList(Entry).initCapacity(allocator, 4),
    };
    errdefer {
        allocator.free(row.index);
        row.entries.deinit(allocator);
    }
    try rows.append(allocator, row);
    return &rows.items[rows.items.len - 1];
}

fn columnIndex(columns: *const std.ArrayList([]const u8), name: []const u8) ?usize {
    for (columns.items, 0..) |col, i| {
        if (std.mem.eql(u8, col, name)) return i;
    }
    return null;
}

fn buildRows(data: Types.Value, allocator: std.mem.Allocator, kind: DataKind) !std.ArrayList(Row) {
    var rows = try std.ArrayList(Row).initCapacity(allocator, 8);
    errdefer {
        for (rows.items) |*row| {
            allocator.free(row.index);
            row.entries.deinit(allocator);
            freeRendered(row, allocator);
        }
        rows.deinit(allocator);
    }

    switch (data) {
        .array => |a| {
            for (a.elements.items, 0..) |elem, i| {
                const idx = try std.fmt.allocPrint(allocator, "{d}", .{i});
                defer allocator.free(idx);
                const row = try addRow(&rows, allocator, idx);
                if (kind == .objects) {
                    try appendObjectEntries(row, elem.js_object, allocator);
                } else {
                    try row.entries.append(allocator, .{ .key = "Values", .value = elem });
                }
            }
        },
        .js_object => |o| {
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                if (isInternalKey(entry.key_ptr.*)) continue;
                const row = try addRow(&rows, allocator, entry.key_ptr.*);
                if (kind == .objects) {
                    try appendObjectEntries(row, entry.value_ptr.*.js_object, allocator);
                } else {
                    try row.entries.append(allocator, .{ .key = "Values", .value = entry.value_ptr.* });
                }
            }
        },
        else => unreachable,
    }
    return rows;
}

fn buildColumns(rows: *std.ArrayList(Row), allocator: std.mem.Allocator, selected: ?Types.Value) !std.ArrayList([]const u8) {
    var columns = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    errdefer columns.deinit(allocator);
    if (selected) |props| {
        if (props == .array) {
            for (props.array.elements.items) |prop| {
                if (prop != .string) continue;
                if (columnIndex(&columns, prop.string) == null) try columns.append(allocator, prop.string);
            }
            return columns;
        }
    }
    for (rows.items) |row| {
        for (row.entries.items) |entry| {
            if (columnIndex(&columns, entry.key) == null) try columns.append(allocator, entry.key);
        }
    }
    return columns;
}

fn freeRendered(row: *Row, allocator: std.mem.Allocator) void {
    for (row.rendered) |item| if (item) |text| allocator.free(text);
    if (row.rendered.len > 0) allocator.free(row.rendered);
    row.rendered = &.{};
}

fn formatCells(rows: *std.ArrayList(Row), columns: *const std.ArrayList([]const u8), env: *Types.Environment, allocator: std.mem.Allocator, use_ansi: bool) !void {
    const options = format.InspectOptions{
        .depth = 1,
        .colors = use_ansi,
        .max_array_length = 10,
    };
    for (rows.items) |*row| {
        row.rendered = try allocator.alloc(?[]u8, columns.items.len);
        @memset(row.rendered, null);
        for (columns.items, 0..) |col, i| {
            for (row.entries.items) |entry| {
                if (std.mem.eql(u8, entry.key, col)) {
                    row.rendered[i] = try format.valueToOwned(env, entry.value, options);
                    break;
                }
            }
        }
    }
}

fn textWidth(text: []const u8) usize {
    var width: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b and i + 1 < text.len and text[i + 1] == '[') {
            width += std.unicode.utf8CountCodepoints(text[start..i]) catch i - start;
            i += 2;
            while (i < text.len and text[i] != 'm') i += 1;
            if (i < text.len) i += 1;
            start = i;
        } else {
            i += 1;
        }
    }
    width += std.unicode.utf8CountCodepoints(text[start..]) catch text.len - start;
    return width;
}

fn appendRepeat(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try buf.appendSlice(allocator, text);
}

fn appendPadded(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8, width: usize) !void {
    try buf.appendSlice(allocator, text);
    const text_width = textWidth(text);
    const pad = if (text_width < width) width - text_width else 0;
    try buf.appendNTimes(allocator, ' ', pad);
}

fn appendBorder(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, left: []const u8, middle: []const u8, right: []const u8, widths: []const usize) !void {
    try buf.appendSlice(allocator, left);
    for (widths, 0..) |width, i| {
        if (i > 0) try buf.appendSlice(allocator, middle);
        try appendRepeat(buf, allocator, "─", width + 2);
    }
    try buf.appendSlice(allocator, right);
}

fn appendRow(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, widths: []const usize, cells: []const []const u8) !void {
    try buf.appendSlice(allocator, "│");
    for (widths, 0..) |width, i| {
        try buf.appendSlice(allocator, " ");
        try appendPadded(buf, allocator, if (i < cells.len) cells[i] else "", width);
        try buf.appendSlice(allocator, " │");
    }
}

fn render(env: *Types.Environment, rows: *std.ArrayList(Row), columns: *const std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    var widths = try allocator.alloc(usize, columns.items.len + 1);
    defer allocator.free(widths);
    widths[0] = "(index)".len;
    for (rows.items) |row| {
        const index_width = textWidth(row.index);
        if (index_width > widths[0]) widths[0] = index_width;
    }
    for (columns.items, 0..) |col, i| widths[i + 1] = textWidth(col);

    for (rows.items) |row| {
        for (row.rendered, 0..) |cell, i| {
            const text = cell orelse "";
            const width = textWidth(text);
            if (width > widths[i + 1]) widths[i + 1] = width;
        }
    }

    var output = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer output.deinit(allocator);

    try appendBorder(&output, allocator, "┌", "┬", "┐", widths);
    try output.append(allocator, '\n');

    var headers = try allocator.alloc([]const u8, columns.items.len + 1);
    defer allocator.free(headers);
    headers[0] = "(index)";
    for (columns.items, 0..) |col, i| headers[i + 1] = col;
    try appendRow(&output, allocator, widths, headers);
    try output.append(allocator, '\n');

    try appendBorder(&output, allocator, "├", "┼", "┤", widths);
    try output.append(allocator, '\n');

    var cells = try allocator.alloc([]const u8, columns.items.len + 1);
    defer allocator.free(cells);
    for (rows.items) |row| {
        cells[0] = row.index;
        for (row.rendered, 0..) |cell, i| cells[i + 1] = cell orelse "";
        try appendRow(&output, allocator, widths, cells);
        try output.append(allocator, '\n');
    }

    try appendBorder(&output, allocator, "└", "┴", "┘", widths);
    format.writeTextBlock(env, .stdout, output.items);
}

pub fn Table(args: []Types.Value, env: *Types.Environment) Types.BuiltinResult {
    if (args.len == 0) {
        format.writeLine(env, .stdout, &[_]Types.Value{.{ .void = {} }}, null);
        return .void;
    }
    const data = args[0];
    const kind = classify(data) orelse {
        format.writeLine(env, .stdout, args[0..1], null);
        return .void;
    };
    if (data != .array and data != .js_object) {
        format.writeLine(env, .stdout, args[0..1], null);
        return .void;
    }

    const allocator = env.allocator;
    const selected: ?Types.Value = if (args.len > 1) args[1] else null;
    var rows = buildRows(data, allocator, kind) catch {
        format.writeLine(env, .stdout, args[0..1], null);
        return .void;
    };
    defer {
        for (rows.items) |*row| {
            allocator.free(row.index);
            row.entries.deinit(allocator);
            freeRendered(row, allocator);
        }
        rows.deinit(allocator);
    }
    var columns = buildColumns(&rows, allocator, selected) catch {
        format.writeLine(env, .stdout, args[0..1], null);
        return .void;
    };
    defer columns.deinit(allocator);
    const use_ansi = if (env.io) |io| ansi.supportsAnsi(io, env.root().ansi_disabled) else false;
    formatCells(&rows, &columns, env, allocator, use_ansi) catch return .void;
    render(env, &rows, &columns, allocator) catch return .void;
    return .void;
}

test "table width ignores ANSI escapes" {
    try std.testing.expectEqual(@as(usize, 1), textWidth("\x1b[33m1\x1b[39m"));
    try std.testing.expectEqual(@as(usize, 4), textWidth("\x1b[1mnull\x1b[22m"));
    try std.testing.expectEqual(@as(usize, 2), textWidth("aé"));
}

test "table formats colored cells" {
    var env = try Types.Environment.init(std.testing.allocator, null);
    defer env.deinit();
    const allocator = std.testing.allocator;

    var rows = try std.ArrayList(Row).initCapacity(allocator, 1);
    defer {
        for (rows.items) |*row| {
            allocator.free(row.index);
            row.entries.deinit(allocator);
            freeRendered(row, allocator);
        }
        rows.deinit(allocator);
    }
    var row = Row{
        .index = try allocator.dupe(u8, "0"),
        .entries = try std.ArrayList(Entry).initCapacity(allocator, 1),
    };
    try row.entries.append(allocator, .{ .key = "a", .value = .{ .integer = 1 } });
    try rows.append(allocator, row);

    var columns = try std.ArrayList([]const u8).initCapacity(allocator, 1);
    defer columns.deinit(allocator);
    try columns.append(allocator, "a");

    try formatCells(&rows, &columns, &env, allocator, true);
    try std.testing.expectEqualStrings("\x1b[33m1\x1b[39m", rows.items[0].rendered[0].?);
}
