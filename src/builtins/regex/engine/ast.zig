const std = @import("std");

pub const NodeType = enum {
    empty,
    literal,
    dot,
    char_class,
    anchor_bol,
    anchor_eol,
    word_boundary,
    concat,
    alternate,
    repeat,
    capture,
    non_capture,
    backref,
    lookahead,
    lookbehind,
};

pub const CharClassNode = struct {
    negated: bool,
    ranges: []const Range,
};

pub const Range = struct {
    start: u21,
    end: u21,
};

pub const RepeatNode = struct {
    min: u32,
    max: ?u32,
    greedy: bool,
};

pub const CaptureNode = struct {
    index: u32,
    name: ?[]const u8,
};

pub const LookaheadNode = struct {
    positive: bool,
};

pub const LookbehindNode = struct {
    positive: bool,
};

pub const Node = struct {
    id: u32,
    node_type: NodeType,
    literal: u21,
    char_class: CharClassNode,
    repeat: RepeatNode,
    capture: CaptureNode,
    lookahead: LookaheadNode,
    lookbehind: LookbehindNode,
    word_boundary_value: bool,
    backref_index: u32,
    children: []u32,
};

pub const NodeList = std.ArrayList(Node);

pub const NamedGroupEntry = struct {
    name: []const u8,
    index: u32,
};

pub const Ast = struct {
    allocator: std.mem.Allocator,
    nodes: NodeList,
    group_count: u32,
    named_groups: std.ArrayList(NamedGroupEntry),

    pub fn init(allocator: std.mem.Allocator) Ast {
        return .{
            .allocator = allocator,
            .nodes = NodeList.initCapacity(allocator, 0) catch unreachable,
            .group_count = 0,
            .named_groups = std.ArrayList(NamedGroupEntry).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Ast) void {
        for (self.named_groups.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.named_groups.deinit(self.allocator);
        for (self.nodes.items) |node| {
            if (node.children.len > 0) {
                self.allocator.free(node.children);
            }
            if (node.node_type == .char_class and node.char_class.ranges.len > 0) {
                self.allocator.free(node.char_class.ranges);
            }
        }
        self.nodes.deinit(self.allocator);
    }

    pub fn addNode(self: *Ast, node_type: NodeType, options: struct {
        literal: u21 = 0,
        char_class: CharClassNode = .{ .negated = false, .ranges = &.{} },
        repeat: RepeatNode = .{ .min = 0, .max = null, .greedy = true },
        capture: CaptureNode = .{ .index = 0, .name = null },
        lookahead: LookaheadNode = .{ .positive = true },
        lookbehind: LookbehindNode = .{ .positive = true },
        word_boundary_value: bool = true,
        backref_index: u32 = 0,
        children: []u32 = &.{},
    }) !u32 {
        const id = @as(u32, @intCast(self.nodes.items.len));
        try self.nodes.append(self.allocator, .{
            .id = id,
            .node_type = node_type,
            .literal = options.literal,
            .char_class = options.char_class,
            .repeat = options.repeat,
            .capture = options.capture,
            .lookahead = options.lookahead,
            .lookbehind = options.lookbehind,
            .word_boundary_value = options.word_boundary_value,
            .backref_index = options.backref_index,
            .children = options.children,
        });
        return id;
    }

    pub fn get(self: *const Ast, id: u32) *const Node {
        return &self.nodes.items[id];
    }

    pub fn allocChildren(self: *Ast, children: []const u32) ![]u32 {
        return try self.allocator.dupe(u32, children);
    }

    pub fn dump(self: *const Ast, writer: anytype) !void {
        if (self.nodes.items.len == 0) {
            try writer.writeAll("(empty)\n");
            return;
        }
        try dumpNode(self, @as(u32, @intCast(self.nodes.items.len - 1)), writer, 0);
    }

    fn dumpNode(self: *const Ast, node_id: u32, writer: anytype, depth: usize) !void {
        const node = self.get(node_id);
        for (0..depth) |_| try writer.writeAll("  ");
        switch (node.node_type) {
            .empty => try writer.writeAll("empty\n"),
            .literal => {
                var utf8_buf: [4]u8 = undefined;
                const utf8_slice = utf8_buf[0..std.unicode.utf8Encode(@as(u21, node.literal), &utf8_buf) catch 1];
                try writer.print("literal '{s}' (0x{x:0>4})\n", .{ utf8_slice, node.literal });
            },
            .dot => try writer.writeAll(".\n"),
            .char_class => {
                if (node.char_class.negated) try writer.writeAll("[^") else try writer.writeAll("[");
                for (node.char_class.ranges, 0..) |r, i| {
                    if (i > 0) try writer.writeAll(", ");
                    if (r.start == r.end) {
                        var buf: [4]u8 = undefined;
                        const slice = buf[0..std.unicode.utf8Encode(@as(u21, @intCast(r.start)), &buf) catch 1];
                        try writer.print("'{s}'", .{slice});
                    } else {
                        var buf1: [4]u8 = undefined;
                        var buf2: [4]u8 = undefined;
                        const s1 = buf1[0..std.unicode.utf8Encode(@as(u21, @intCast(r.start)), &buf1) catch 1];
                        const s2 = buf2[0..std.unicode.utf8Encode(@as(u21, @intCast(r.end)), &buf2) catch 1];
                        try writer.print("'{s}'-'{s}'", .{ s1, s2 });
                    }
                }
                try writer.writeAll("]\n");
            },
            .anchor_bol => try writer.writeAll("^\n"),
            .anchor_eol => try writer.writeAll("$\n"),
            .word_boundary => {
                if (node.word_boundary_value) {
                    try writer.writeAll("\\b\n");
                } else {
                    try writer.writeAll("\\B\n");
                }
            },
            .concat => {
                try writer.writeAll("concat\n");
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
            .alternate => {
                try writer.writeAll("alternate\n");
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
            .repeat => {
                const r = node.repeat;
                if (r.max) |max| {
                    try writer.print("repeat {{{d},{d}}}{s}\n", .{ r.min, max, if (r.greedy) "" else "?" });
                } else {
                    try writer.print("repeat {{{d},}}{s}\n", .{ r.min, if (r.greedy) "" else "?" });
                }
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
            .capture => {
                if (node.capture.name) |name| {
                    try writer.print("capture #{d} '{s}'\n", .{ node.capture.index, name });
                } else {
                    try writer.print("capture #{d}\n", .{node.capture.index});
                }
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
            .non_capture => {
                try writer.writeAll("(?:...)\n");
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
            .backref => try writer.print("backref \\{d}\n", .{node.backref_index}),
            .lookahead => {
                if (node.lookahead.positive) {
                    try writer.writeAll("(?=...)\n");
                } else {
                    try writer.writeAll("(?!...)\n");
                }
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
            .lookbehind => {
                if (node.lookbehind.positive) {
                    try writer.writeAll("(?<=...)\n");
                } else {
                    try writer.writeAll("(?<!...)\n");
                }
                for (node.children) |child_id| {
                    try dumpNode(self, child_id, writer, depth + 1);
                }
            },
        }
    }
};
