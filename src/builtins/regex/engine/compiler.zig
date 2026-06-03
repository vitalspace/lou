const std = @import("std");
const ast_mod = @import("ast.zig");
const Ast = ast_mod.Ast;
const NodeType = ast_mod.NodeType;

pub const Opcode = enum(u8) {
    match,
    fail,
    char,
    any,
    class,
    jmp,
    split,
    save,
    assert_bol,
    assert_eol,
    assert_wb,
    look_start,
    look_end,
    backref,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: u32,
    operand2: u32,
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    instructions: std.ArrayList(Instruction),
    class_data: std.ArrayList(ClassInfo),

    pub const ClassInfo = struct {
        negated: bool,
        ranges: []const ast_mod.Range,
    };

    pub fn dump(self: *const Program, writer: anytype) !void {
        try writer.print("=== Bytecode ({d} instructions, {d} classes) ===\n", .{ self.instructions.items.len, self.class_data.items.len });
        for (self.instructions.items, 0..) |instr, i| {
            const op_name = @tagName(instr.opcode);
            switch (instr.opcode) {
                .match, .fail, .any, .assert_bol, .assert_eol, .look_end => {
                    try writer.print("  {d}: {s}\n", .{ i, op_name });
                },
                .char, .backref => {
                    try writer.print("  {d}: {s} {d}\n", .{ i, op_name, instr.operand1 });
                },
                .class => {
                    const ci = &self.class_data.items[instr.operand1];
                    try writer.print("  {d}: class #{d} ", .{ i, instr.operand1 });
                    if (ci.negated) try writer.writeAll("negated ");
                    try writer.writeAll("[");
                    for (ci.ranges, 0..) |r, j| {
                        if (j > 0) try writer.writeAll(", ");
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
                .jmp, .save => {
                    try writer.print("  {d}: {s} -> {d}\n", .{ i, op_name, instr.operand1 });
                },
                .split => {
                    try writer.print("  {d}: split -> {d}, {d}\n", .{ i, instr.operand1, instr.operand2 });
                },
                .assert_wb => {
                    try writer.print("  {d}: {s} ({s})\n", .{ i, op_name, if (instr.operand1 == 0) "\\b" else "\\B" });
                },
                .look_start => {
                    const kind = if (instr.operand2 == 1) "lookahead" else "lookbehind";
                    const sign = if (instr.operand1 == 1) "positive" else "negative";
                    try writer.print("  {d}: {s} {s} {s}\n", .{ i, op_name, kind, sign });
                },
            }
        }
    }
};

pub fn compile(allocator: std.mem.Allocator, tree: *Ast) !Program {
    var prog = Program{
        .allocator = allocator,
        .instructions = std.ArrayList(Instruction).initCapacity(allocator, 0) catch unreachable,
        .class_data = std.ArrayList(Program.ClassInfo).initCapacity(allocator, 0) catch unreachable,
    };

    if (tree.nodes.items.len > 0) {
        _ = try compileNode(&prog, tree, @as(u32, @intCast(tree.nodes.items.len - 1)));
    }
    try prog.instructions.append(prog.allocator, .{ .opcode = .match, .operand1 = 0, .operand2 = 0 });

    return prog;
}

fn emit(prog: *Program, opcode: Opcode, op1: u32, op2: u32) !u32 {
    const idx = @as(u32, @intCast(prog.instructions.items.len));
    try prog.instructions.append(prog.allocator, .{ .opcode = opcode, .operand1 = op1, .operand2 = op2 });
    return idx;
}

fn emitAt(prog: *Program, idx: u32, opcode: Opcode, op1: u32, op2: u32) void {
    prog.instructions.items[idx] = .{ .opcode = opcode, .operand1 = op1, .operand2 = op2 };
}

fn compileNode(prog: *Program, tree: *Ast, node_id: u32) !void {
    const node = tree.get(node_id);
    switch (node.node_type) {
        .empty => {},
        .literal => {
            _ = try emit(prog, .char, node.literal, 0);
        },
        .dot => {
            _ = try emit(prog, .any, 0, 0);
        },
        .char_class => {
            const duped_ranges = try prog.allocator.dupe(ast_mod.Range, node.char_class.ranges);
            const class_idx = @as(u32, @intCast(prog.class_data.items.len));
            try prog.class_data.append(prog.allocator, .{
                .negated = node.char_class.negated,
                .ranges = duped_ranges,
            });
            _ = try emit(prog, .class, class_idx, 0);
        },
        .anchor_bol => {
            _ = try emit(prog, .assert_bol, 0, 0);
        },
        .anchor_eol => {
            _ = try emit(prog, .assert_eol, 0, 0);
        },
        .word_boundary => {
            _ = try emit(prog, .assert_wb, if (node.word_boundary_value) 0 else 1, 0);
        },
        .backref => {
            _ = try emit(prog, .backref, node.backref_index, 0);
        },
        .concat => {
            for (node.children) |child_id| {
                try compileNode(prog, tree, child_id);
            }
        },
        .alternate => {
            const children = node.children;
            if (children.len == 1) {
                try compileNode(prog, tree, children[0]);
            } else {
                var jmp_indices = std.ArrayList(u32).initCapacity(prog.allocator, children.len - 1) catch unreachable;
                defer jmp_indices.deinit(prog.allocator);

                for (children, 0..) |child_id, i| {
                    if (i < children.len - 1) {
                        const split_idx = try emit(prog, .split, 0, 0);
                        try compileNode(prog, tree, child_id);
                        const jmp_idx = try emit(prog, .jmp, 0, 0);
                        try jmp_indices.append(prog.allocator, jmp_idx);
                        const next_start = @as(u32, @intCast(prog.instructions.items.len));
                        emitAt(prog, split_idx, .split, split_idx + 1, next_start);
                    } else {
                        try compileNode(prog, tree, child_id);
                        const after = @as(u32, @intCast(prog.instructions.items.len));
                        for (jmp_indices.items) |jmp_i| {
                            emitAt(prog, jmp_i, .jmp, after, 0);
                        }
                    }
                }
            }
        },
        .repeat => {
            const min = node.repeat.min;
            const max = node.repeat.max;
            const greedy = node.repeat.greedy;

            if (max == null and min == 0) {
                const split_idx = try emit(prog, .split, 0, 0);
                try compileNode(prog, tree, node.children[0]);
                const jmp_idx = try emit(prog, .jmp, split_idx, 0);
                const after = @as(u32, @intCast(prog.instructions.items.len));
                if (greedy) {
                    emitAt(prog, split_idx, .split, split_idx + 1, after);
                } else {
                    emitAt(prog, split_idx, .split, after, split_idx + 1);
                }
                emitAt(prog, jmp_idx, .jmp, split_idx, 0);
            } else if (max == null and min == 1) {
                try compileNode(prog, tree, node.children[0]);
                const split_idx = try emit(prog, .split, 0, 0);
                try compileNode(prog, tree, node.children[0]);
                const jmp_idx = try emit(prog, .jmp, split_idx, 0);
                const after = @as(u32, @intCast(prog.instructions.items.len));
                if (greedy) {
                    emitAt(prog, split_idx, .split, split_idx + 1, after);
                } else {
                    emitAt(prog, split_idx, .split, after, split_idx + 1);
                }
                emitAt(prog, jmp_idx, .jmp, split_idx, 0);
            } else if (max != null and max.? == 1 and min == 0) {
                const split_idx = try emit(prog, .split, 0, 0);
                try compileNode(prog, tree, node.children[0]);
                const after = @as(u32, @intCast(prog.instructions.items.len));
                if (greedy) {
                    emitAt(prog, split_idx, .split, split_idx + 1, after);
                } else {
                    emitAt(prog, split_idx, .split, after, split_idx + 1);
                }
            } else {
                for (0..min) |_| {
                    try compileNode(prog, tree, node.children[0]);
                }
                if (max) |m| {
                    if (m > min) {
                        for (0..(m - min)) |_| {
                            const split_idx = try emit(prog, .split, 0, 0);
                            try compileNode(prog, tree, node.children[0]);
                            const after = @as(u32, @intCast(prog.instructions.items.len));
                            if (greedy) {
                                emitAt(prog, split_idx, .split, split_idx + 1, after);
                            } else {
                                emitAt(prog, split_idx, .split, after, split_idx + 1);
                            }
                        }
                    }
                } else {
                    const split_idx = try emit(prog, .split, 0, 0);
                    try compileNode(prog, tree, node.children[0]);
                    const jmp_idx = try emit(prog, .jmp, split_idx, 0);
                    const after = @as(u32, @intCast(prog.instructions.items.len));
                    if (greedy) {
                        emitAt(prog, split_idx, .split, split_idx + 1, after);
                    } else {
                        emitAt(prog, split_idx, .split, after, split_idx + 1);
                    }
                    emitAt(prog, jmp_idx, .jmp, split_idx, 0);
                }
            }
        },
        .capture => {
            _ = try emit(prog, .save, node.capture.index * 2, 0);
            try compileNode(prog, tree, node.children[0]);
            _ = try emit(prog, .save, node.capture.index * 2 + 1, 0);
        },
        .non_capture => {
            try compileNode(prog, tree, node.children[0]);
        },
        .lookahead => {
            _ = try emit(prog, .look_start, if (node.lookahead.positive) 1 else 0, 1);
            try compileNode(prog, tree, node.children[0]);
            _ = try emit(prog, .look_end, 0, 0);
        },
        .lookbehind => {
            _ = try emit(prog, .look_start, if (node.lookbehind.positive) 1 else 0, 0);
            try compileNode(prog, tree, node.children[0]);
            _ = try emit(prog, .look_end, 0, 0);
        },
    }
}
