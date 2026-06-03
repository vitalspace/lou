const std = @import("std");
const ast = @import("ast.zig");
const Ast = ast.Ast;
const NodeType = ast.NodeType;
const unicode = @import("unicode.zig");

pub const ParseError = error{
    UnexpectedEnd,
    UnexpectedToken,
    InvalidEscape,
    InvalidUnicodeEscape,
    InvalidRange,
    UnclosedClass,
    UnclosedGroup,
    UnmatchedParen,
    InvalidQuantifier,
    QuantifierWithoutAtom,
    DuplicateGroupName,
    UnsupportedFeature,
    OutOfMemory,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    pos: u32,
    group_count: u32,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) Parser {
        return .{
            .allocator = allocator,
            .pattern = pattern,
            .pos = 0,
            .group_count = 0,
        };
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos >= self.pattern.len) return null;
        return self.pattern[self.pos];
    }

    fn advance(self: *Parser) u8 {
        const ch = self.pattern[self.pos];
        self.pos += 1;
        return ch;
    }

    fn expect(self: *Parser, ch: u8) !void {
        if (self.peek()) |c| {
            if (c == ch) {
                _ = self.advance();
                return;
            }
        }
        return error.UnexpectedToken;
    }

    pub fn parse(self: *Parser, resulting_ast: *Ast) ParseError!void {
        _ = try self.parseAlternation(resulting_ast);
        if (self.pos < self.pattern.len) {
            return error.UnexpectedToken;
        }
    }

    fn parseAlternation(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        var node_ids = std.ArrayList(u32).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer node_ids.deinit(self.allocator);

        const first = try self.parseConcatenation(resulting_ast);
        try node_ids.append(self.allocator, first);

        while (self.peek()) |ch| {
            if (ch == '|') {
                _ = self.advance();
                const next = try self.parseConcatenation(resulting_ast);
                try node_ids.append(self.allocator, next);
            } else if (ch == ')' or ch == ']') {
                break;
            } else {
                break;
            }
        }

        if (node_ids.items.len == 1) {
            return node_ids.items[0];
        }

        const children = try resulting_ast.allocChildren(node_ids.items);
        return resulting_ast.addNode(.alternate, .{ .children = children });
    }

    fn parseConcatenation(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        var node_ids = std.ArrayList(u32).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer node_ids.deinit(self.allocator);

        while (self.peek()) |ch| {
            if (ch == '|' or ch == ')' or ch == ']') break;
            if (ch == 0) break;
            const atom = try self.parseAtom(resulting_ast);
            try node_ids.append(self.allocator, atom);
        }

        if (node_ids.items.len == 0) {
            return resulting_ast.addNode(.empty, .{});
        }

        if (node_ids.items.len == 1) {
            return node_ids.items[0];
        }

        const children = try resulting_ast.allocChildren(node_ids.items);
        return resulting_ast.addNode(.concat, .{ .children = children });
    }

    fn parseAtom(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        const ch = self.peek() orelse return error.UnexpectedEnd;

        switch (ch) {
            '(' => {
                const id = try self.parseGroup(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            '[' => return self.parseCharClass(resulting_ast),
            '.' => {
                _ = self.advance();
                const id = try resulting_ast.addNode(.dot, .{});
                return self.maybeQuantify(id, resulting_ast);
            },
            '^' => {
                _ = self.advance();
                const id = try resulting_ast.addNode(.anchor_bol, .{});
                return self.maybeQuantify(id, resulting_ast);
            },
            '$' => {
                _ = self.advance();
                const id = try resulting_ast.addNode(.anchor_eol, .{});
                return self.maybeQuantify(id, resulting_ast);
            },
            '\\' => {
                _ = self.advance();
                return self.parseEscape(resulting_ast);
            },
            ')' => return error.UnmatchedParen,
            ']' => return error.UnexpectedToken,
            '|' => return error.UnexpectedToken,
            '*', '+', '?', '{' => return error.QuantifierWithoutAtom,
            else => {
                _ = self.advance();
                const id = try resulting_ast.addNode(.literal, .{ .literal = ch });
                return self.maybeQuantify(id, resulting_ast);
            },
        }
    }

    fn parseEscape(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        const ch = self.advance();
        switch (ch) {
            'd' => {
                const id = try makeDigitClass(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            'D' => {
                const id = try makeDigitClassInv(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            'w' => {
                const id = try makeWordClass(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            'W' => {
                const id = try makeWordClassInv(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            's' => {
                const id = try makeSpaceClass(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            'S' => {
                const id = try makeSpaceClassInv(resulting_ast);
                return self.maybeQuantify(id, resulting_ast);
            },
            'b' => {
                return resulting_ast.addNode(.word_boundary, .{ .word_boundary_value = true });
            },
            'B' => {
                return resulting_ast.addNode(.word_boundary, .{ .word_boundary_value = false });
            },
            'p' => {
                try self.expect('{');
                const prop_end = std.mem.indexOfScalar(u8, self.pattern[self.pos..], '}') orelse return error.InvalidEscape;
                const prop_name = self.pattern[self.pos..self.pos + prop_end];
                self.pos += @as(u32, @intCast(prop_end)) + 1;
                const ranges = try unicode.getRanges(resulting_ast.allocator, prop_name) orelse return error.InvalidEscape;
                const id = try resulting_ast.addNode(.char_class, .{
                    .char_class = .{ .negated = false, .ranges = ranges },
                });
                return self.maybeQuantify(id, resulting_ast);
            },
            'P' => {
                try self.expect('{');
                const prop_end = std.mem.indexOfScalar(u8, self.pattern[self.pos..], '}') orelse return error.InvalidEscape;
                const prop_name = self.pattern[self.pos..self.pos + prop_end];
                self.pos += @as(u32, @intCast(prop_end)) + 1;
                const ranges = try unicode.getRanges(resulting_ast.allocator, prop_name) orelse return error.InvalidEscape;
                const id = try resulting_ast.addNode(.char_class, .{
                    .char_class = .{ .negated = true, .ranges = ranges },
                });
                return self.maybeQuantify(id, resulting_ast);
            },
            't' => {
                const id = try resulting_ast.addNode(.literal, .{ .literal = '\t' });
                return self.maybeQuantify(id, resulting_ast);
            },
            'n' => {
                const id = try resulting_ast.addNode(.literal, .{ .literal = '\n' });
                return self.maybeQuantify(id, resulting_ast);
            },
            'r' => {
                const id = try resulting_ast.addNode(.literal, .{ .literal = '\r' });
                return self.maybeQuantify(id, resulting_ast);
            },
            'f' => {
                const id = try resulting_ast.addNode(.literal, .{ .literal = '\x0C' });
                return self.maybeQuantify(id, resulting_ast);
            },
            'v' => {
                const id = try resulting_ast.addNode(.literal, .{ .literal = '\x0B' });
                return self.maybeQuantify(id, resulting_ast);
            },
            '0' => {
                const id = try resulting_ast.addNode(.literal, .{ .literal = 0 });
                return self.maybeQuantify(id, resulting_ast);
            },
            'u' => return self.parseUnicodeEscape(resulting_ast),
            'c' => return self.parseControlEscape(resulting_ast),
            'x' => return self.parseHexEscape(resulting_ast),
            '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                const backref_index = ch - '0';
                if (backref_index <= self.group_count) {
                    return resulting_ast.addNode(.backref, .{ .backref_index = backref_index });
                }
                return error.InvalidEscape;
            },
            else => {
                if (std.ascii.isAlphanumeric(ch)) return error.InvalidEscape;
                const id = try resulting_ast.addNode(.literal, .{ .literal = ch });
                return self.maybeQuantify(id, resulting_ast);
            },
        }
    }

    fn parseUnicodeEscape(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        if (self.peek()) |ch| {
            if (ch == '{') {
                _ = self.advance();
                const end = std.mem.indexOfScalar(u8, self.pattern[self.pos..], '}') orelse return error.InvalidUnicodeEscape;
                if (end == 0 or end > 6) return error.InvalidUnicodeEscape;
                const hex_str = self.pattern[self.pos .. self.pos + end];
                const cp = std.fmt.parseInt(u21, hex_str, 16) catch return error.InvalidUnicodeEscape;
                self.pos += @as(u32, @intCast(end)) + 1;
                const id = try resulting_ast.addNode(.literal, .{ .literal = cp });
                return self.maybeQuantify(id, resulting_ast);
            }
        }
        if (self.pos + 4 > self.pattern.len) return error.InvalidUnicodeEscape;
        const hex_str = self.pattern[self.pos..][0..4];
        const cp = std.fmt.parseInt(u21, hex_str, 16) catch return error.InvalidUnicodeEscape;
        self.pos += 4;
        const id = try resulting_ast.addNode(.literal, .{ .literal = cp });
        return self.maybeQuantify(id, resulting_ast);
    }

    fn parseHexEscape(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        if (self.pos + 2 > self.pattern.len) return error.InvalidEscape;
        const hex_str = self.pattern[self.pos..][0..2];
        const val = std.fmt.parseInt(u8, hex_str, 16) catch return error.InvalidEscape;
        self.pos += 2;
        const id = try resulting_ast.addNode(.literal, .{ .literal = val });
        return self.maybeQuantify(id, resulting_ast);
    }

    fn parseControlEscape(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        const ch = self.advance();
        const val = (std.ascii.toUpper(ch) - 'A') + 1;
        const id = try resulting_ast.addNode(.literal, .{ .literal = val });
        return self.maybeQuantify(id, resulting_ast);
    }

    fn parseCharClass(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        const start_pos = self.pos;
        _ = self.advance();
        var negated = false;
        if (self.peek()) |ch| {
            if (ch == '^') {
                negated = true;
                _ = self.advance();
            }
        }

        var ranges = std.ArrayList(ast.Range).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer ranges.deinit(self.allocator);

        var literals = std.ArrayList(u21).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer literals.deinit(self.allocator);

        var i: usize = 0;
        var prev_cp: ?u21 = null;

        while (self.peek()) |ch| {
            if (ch == ']') {
                if (i == 0) {
                    try literals.append(self.allocator, ']');
                    _ = self.advance();
                    i += 1;
                    continue;
                }
                _ = self.advance();
                break;
            }

            if (ch == '-') {
                if (i == 0) {
                    try literals.append(self.allocator, '-');
                    _ = self.advance();
                    i += 1;
                    continue;
                }
                _ = self.advance();
                const next = self.peek();
                if (next == null or next.? == ']') {
                    try literals.append(self.allocator, '-');
                    continue;
                }
                const end_cp = try self.readClassChar();
                if (prev_cp) |start| {
                    if (start > end_cp) return error.InvalidRange;
                    try ranges.append(self.allocator, .{ .start = start, .end = end_cp });
                    prev_cp = null;
                } else {
                    try literals.append(self.allocator, '-');
                }
                continue;
            }

            if (ch == '\\') {
                _ = self.advance();
                const escape_ch = self.peek() orelse return error.UnexpectedEnd;
                switch (escape_ch) {
                    'd' => {
                        _ = self.advance();
                        try ranges.append(self.allocator, .{ .start = '0', .end = '9' });
                        prev_cp = null;
                    },
                    'w' => {
                        _ = self.advance();
                        try ranges.append(self.allocator, .{ .start = '0', .end = '9' });
                        try ranges.append(self.allocator, .{ .start = 'A', .end = 'Z' });
                        try ranges.append(self.allocator, .{ .start = 'a', .end = 'z' });
                        try ranges.append(self.allocator, .{ .start = '_', .end = '_' });
                        prev_cp = null;
                    },
                    's' => {
                        _ = self.advance();
                        try ranges.append(self.allocator, .{ .start = ' ', .end = ' ' });
                        try ranges.append(self.allocator, .{ .start = '\t', .end = '\t' });
                        try ranges.append(self.allocator, .{ .start = '\n', .end = '\n' });
                        try ranges.append(self.allocator, .{ .start = '\r', .end = '\r' });
                        try ranges.append(self.allocator, .{ .start = 0x0B, .end = 0x0B });
                        try ranges.append(self.allocator, .{ .start = 0x0C, .end = 0x0C });
                        prev_cp = null;
                    },                        'p' => {
                        _ = self.advance();
                        try self.expect('{');
                        const prop_end = std.mem.indexOfScalar(u8, self.pattern[self.pos..], '}') orelse return error.InvalidEscape;
                        const prop_name = self.pattern[self.pos..self.pos + prop_end];
                        self.pos += @as(u32, @intCast(prop_end)) + 1;
                        const prop_ranges = try unicode.getRanges(self.allocator, prop_name) orelse return error.InvalidEscape;
                        for (prop_ranges) |r| try ranges.append(self.allocator, r);
                        self.allocator.free(std.mem.sliceAsBytes(prop_ranges));
                        prev_cp = null;
                    },
                    'P' => {
                        _ = self.advance();
                        return error.UnsupportedFeature;
                    },
                    'D', 'W', 'S' => {
                        _ = self.advance();
                        return error.UnsupportedFeature;
                    },
                    else => {
                        const cp = try self.readClassEscape();
                        prev_cp = cp;
                        try literals.append(self.allocator, cp);
                    },
                }
            } else {
                prev_cp = ch;
                try literals.append(self.allocator, ch);
                _ = self.advance();
            }
            i += 1;
        } else {
            self.pos = start_pos;
            return error.UnclosedClass;
        }

        var all_ranges = std.ArrayList(ast.Range).initCapacity(self.allocator, ranges.items.len + literals.items.len) catch return error.OutOfMemory;
        defer all_ranges.deinit(self.allocator);

        for (ranges.items) |r| try all_ranges.append(self.allocator, r);
        for (literals.items) |cp| try all_ranges.append(self.allocator, .{ .start = cp, .end = cp });

        const final_ranges = try resulting_ast.allocator.dupe(ast.Range, all_ranges.items);
        const id = try resulting_ast.addNode(.char_class, .{
            .char_class = .{ .negated = negated, .ranges = final_ranges },
        });
        return self.maybeQuantify(id, resulting_ast);
    }

    fn readClassChar(self: *Parser) !u21 {
        const ch = self.peek() orelse return error.UnexpectedEnd;
        if (ch == '\\') {
            _ = self.advance();
            return self.readClassEscape();
        }
        _ = self.advance();
        return ch;
    }

    fn readClassEscape(self: *Parser) !u21 {
        const ch = self.advance();
        return switch (ch) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'f' => '\x0C',
            'v' => '\x0B',
            '0' => 0,
            'd', 'D', 'w', 'W', 's', 'S' => error.UnsupportedFeature,
            'u' => blk: {
                if (self.peek()) |c| {
                    if (c == '{') {
                        _ = self.advance();
                        const end = std.mem.indexOfScalar(u8, self.pattern[self.pos..], '}') orelse return error.InvalidUnicodeEscape;
                        const hex_str = self.pattern[self.pos .. self.pos + end];
                        const cp = std.fmt.parseInt(u21, hex_str, 16) catch return error.InvalidUnicodeEscape;
                        self.pos += @as(u32, @intCast(end)) + 1;
                        break :blk cp;
                    }
                }
                const hex_str = self.pattern[self.pos..][0..4];
                const cp = std.fmt.parseInt(u21, hex_str, 16) catch return error.InvalidUnicodeEscape;
                self.pos += 4;
                break :blk cp;
            },
            'x' => blk: {
                const hex_str = self.pattern[self.pos..][0..2];
                const val = std.fmt.parseInt(u8, hex_str, 16) catch return error.InvalidEscape;
                self.pos += 2;
                break :blk val;
            },
            else => ch,
        };
    }

    fn parseGroup(self: *Parser, resulting_ast: *Ast) ParseError!u32 {
        _ = self.advance();

        if (self.peek()) |ch| {
            if (ch == '?') {
                _ = self.advance();
                const next = self.peek() orelse return error.UnexpectedEnd;
                switch (next) {
                    ':' => {
                        _ = self.advance();
                        const inner = try self.parseAlternation(resulting_ast);
                        try self.expect(')');
                        return resulting_ast.addNode(.non_capture, .{
                            .children = try resulting_ast.allocChildren(&.{inner}),
                        });
                    },
                    '=' => {
                        _ = self.advance();
                        const inner = try self.parseAlternation(resulting_ast);
                        try self.expect(')');
                        return resulting_ast.addNode(.lookahead, .{
                            .lookahead = .{ .positive = true },
                            .children = try resulting_ast.allocChildren(&.{inner}),
                        });
                    },
                    '!' => {
                        _ = self.advance();
                        const inner = try self.parseAlternation(resulting_ast);
                        try self.expect(')');
                        return resulting_ast.addNode(.lookahead, .{
                            .lookahead = .{ .positive = false },
                            .children = try resulting_ast.allocChildren(&.{inner}),
                        });
                    },
                    '<' => {
                        _ = self.advance();
                        const next2 = self.peek() orelse return error.UnexpectedEnd;
                        if (next2 == '=' or next2 == '!') {
                            const positive = next2 == '=';
                            _ = self.advance();
                            const inner = try self.parseAlternation(resulting_ast);
                            try self.expect(')');
                            return resulting_ast.addNode(.lookbehind, .{
                                .lookbehind = .{ .positive = positive },
                                .children = try resulting_ast.allocChildren(&.{inner}),
                            });
                        }
                        const name_start = next2;
                        return self.parseNamedGroup(name_start, resulting_ast);
                    },
                    else => return error.UnsupportedFeature,
                }
            }
        }

        self.group_count += 1;
        const capture_index = self.group_count;
        const inner = try self.parseAlternation(resulting_ast);
        try self.expect(')');
        return resulting_ast.addNode(.capture, .{
            .capture = .{ .index = capture_index, .name = null },
            .children = try resulting_ast.allocChildren(&.{inner}),
        });
    }

    fn parseNamedGroup(self: *Parser, _: u8, resulting_ast: *Ast) ParseError!u32 {
        const name_end = std.mem.indexOfScalar(u8, self.pattern[self.pos..], '>') orelse return error.UnclosedGroup;
        const name_bytes = self.pattern[self.pos .. self.pos + name_end];
        const name = try self.allocator.dupe(u8, name_bytes);
        self.pos += @as(u32, @intCast(name_end)) + 1;

        for (resulting_ast.named_groups.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                self.allocator.free(name);
                return error.DuplicateGroupName;
            }
        }

        self.group_count += 1;
        const capture_index = self.group_count;
        try resulting_ast.named_groups.append(self.allocator, .{
            .name = name,
            .index = capture_index,
        });

        const inner = try self.parseAlternation(resulting_ast);
        try self.expect(')');
        return resulting_ast.addNode(.capture, .{
            .capture = .{ .index = capture_index, .name = name },
            .children = try resulting_ast.allocChildren(&.{inner}),
        });
    }

    fn maybeQuantify(self: *Parser, node_id: u32, resulting_ast: *Ast) ParseError!u32 {
        const ch = self.peek() orelse return node_id;

        switch (ch) {
            '*' => {
                _ = self.advance();
                var greedy = true;
                if (self.peek()) |c| {
                    if (c == '?') {
                        greedy = false;
                        _ = self.advance();
                    }
                }
                return resulting_ast.addNode(.repeat, .{
                    .repeat = .{ .min = 0, .max = null, .greedy = greedy },
                    .children = try resulting_ast.allocChildren(&.{node_id}),
                });
            },
            '+' => {
                _ = self.advance();
                var greedy = true;
                if (self.peek()) |c| {
                    if (c == '?') {
                        greedy = false;
                        _ = self.advance();
                    }
                }
                return resulting_ast.addNode(.repeat, .{
                    .repeat = .{ .min = 1, .max = null, .greedy = greedy },
                    .children = try resulting_ast.allocChildren(&.{node_id}),
                });
            },
            '?' => {
                _ = self.advance();
                var greedy = true;
                if (self.peek()) |c| {
                    if (c == '?') {
                        greedy = false;
                        _ = self.advance();
                    }
                }
                return resulting_ast.addNode(.repeat, .{
                    .repeat = .{ .min = 0, .max = 1, .greedy = greedy },
                    .children = try resulting_ast.allocChildren(&.{node_id}),
                });
            },
            '{' => {
                if (self.tryParseBrace()) |q| {
                    var greedy = true;
                    if (self.peek()) |c| {
                        if (c == '?') {
                            greedy = false;
                            _ = self.advance();
                        }
                    }
                    return resulting_ast.addNode(.repeat, .{
                        .repeat = .{ .min = q.min, .max = q.max, .greedy = greedy },
                        .children = try resulting_ast.allocChildren(&.{node_id}),
                    });
                }
                return node_id;
            },
            else => return node_id,
        }
    }

    const Quantifier = struct {
        min: u32,
        max: ?u32,
    };

    fn tryParseBrace(self: *Parser) ?Quantifier {
        const saved_pos = self.pos;
        _ = self.advance();

        if (self.peek() == null) {
            self.pos = saved_pos;
            return null;
        }

        const start = self.pos;
        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            _ = self.advance();
        }

        if (self.pos == start) {
            self.pos = saved_pos;
            return null;
        }

        const min_str = self.pattern[start..self.pos];
        const min = std.fmt.parseInt(u32, min_str, 10) catch {
            self.pos = saved_pos;
            return null;
        };

        if (self.peek()) |c| {
            if (c == ',') {
                _ = self.advance();
                const max_start = self.pos;
                while (self.peek()) |c2| {
                    if (!std.ascii.isDigit(c2)) break;
                    _ = self.advance();
                }

                if (self.peek()) |c2| {
                    if (c2 == '}') {
                        _ = self.advance();
                        if (self.pos > max_start + 1) {
                            const max_str = self.pattern[max_start..self.pos - 1];
                            const max = std.fmt.parseInt(u32, max_str, 10) catch {
                                self.pos = saved_pos;
                                return null;
                            };
                            if (min > max) return null;
                            return Quantifier{ .min = min, .max = max };
                        }
                        return Quantifier{ .min = min, .max = null };
                    }
                }
            } else if (c == '}') {
                _ = self.advance();
                return Quantifier{ .min = min, .max = min };
            }
        }

        self.pos = saved_pos;
        return null;
    }
};

fn makeDigitClass(resulting_ast: *Ast) !u32 {
    const ranges = try resulting_ast.allocator.dupe(ast.Range, &.{
        .{ .start = '0', .end = '9' },
    });
    return resulting_ast.addNode(.char_class, .{
        .char_class = .{ .negated = false, .ranges = ranges },
    });
}

fn makeDigitClassInv(resulting_ast: *Ast) !u32 {
    const ranges = try resulting_ast.allocator.dupe(ast.Range, &.{
        .{ .start = '0', .end = '9' },
    });
    return resulting_ast.addNode(.char_class, .{
        .char_class = .{ .negated = true, .ranges = ranges },
    });
}

fn makeWordClass(resulting_ast: *Ast) !u32 {
    const ranges = try resulting_ast.allocator.dupe(ast.Range, &.{
        .{ .start = '0', .end = '9' },
        .{ .start = 'A', .end = 'Z' },
        .{ .start = 'a', .end = 'z' },
        .{ .start = '_', .end = '_' },
    });
    return resulting_ast.addNode(.char_class, .{
        .char_class = .{ .negated = false, .ranges = ranges },
    });
}

fn makeWordClassInv(resulting_ast: *Ast) !u32 {
    const ranges = try resulting_ast.allocator.dupe(ast.Range, &.{
        .{ .start = '0', .end = '9' },
        .{ .start = 'A', .end = 'Z' },
        .{ .start = 'a', .end = 'z' },
        .{ .start = '_', .end = '_' },
    });
    return resulting_ast.addNode(.char_class, .{
        .char_class = .{ .negated = true, .ranges = ranges },
    });
}

fn makeSpaceClass(resulting_ast: *Ast) !u32 {
    const ranges = try resulting_ast.allocator.dupe(ast.Range, &.{
        .{ .start = ' ', .end = ' ' },
        .{ .start = '\t', .end = '\t' },
        .{ .start = '\n', .end = '\n' },
        .{ .start = '\r', .end = '\r' },
        .{ .start = '\x0B', .end = '\x0B' },
        .{ .start = '\x0C', .end = '\x0C' },
    });
    return resulting_ast.addNode(.char_class, .{
        .char_class = .{ .negated = false, .ranges = ranges },
    });
}

fn makeSpaceClassInv(resulting_ast: *Ast) !u32 {
    const ranges = try resulting_ast.allocator.dupe(ast.Range, &.{
        .{ .start = ' ', .end = ' ' },
        .{ .start = '\t', .end = '\t' },
        .{ .start = '\n', .end = '\n' },
        .{ .start = '\r', .end = '\r' },
        .{ .start = '\x0B', .end = '\x0B' },
        .{ .start = '\x0C', .end = '\x0C' },
    });
    return resulting_ast.addNode(.char_class, .{
        .char_class = .{ .negated = true, .ranges = ranges },
    });
}
