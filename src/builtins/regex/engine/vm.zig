const std = @import("std");
const compiler = @import("compiler.zig");
const ast_mod = @import("ast.zig");
const Program = compiler.Program;
const Instruction = compiler.Instruction;
const Opcode = compiler.Opcode;

const SAVE_SLOTS: u32 = 64;

pub const MatchResult = struct {
    span: Span,
    captures: []Capture,
    named: ?[]NamedCapture,
    indices: ?[]Span, // [[start,end], ...] for full match + captures (when has_indices)

    pub fn deinit(self: *MatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.captures);
        if (self.named) |n| {
            allocator.free(n);
        }
        if (self.indices) |idx| {
            allocator.free(idx);
        }
    }
};

pub const Span = struct {
    start: u32,
    end: u32,
};

pub const Capture = struct {
    span: ?Span,
};

pub const NamedCapture = struct {
    name: []const u8,
    span: ?Span,
};

pub const ExecState = struct {
    last_index: u32 = 0,
    max_steps: u64 = 1_000_000,
};

pub const Thread = struct {
    pc: u32,
    input_pos: u32,
    saves: [SAVE_SLOTS]u32,
};

pub const Vm = struct {
    allocator: std.mem.Allocator,
    program: Program,
    group_count: u32,
    named_groups: ?[]const ast_mod.NamedGroupEntry,

    pub fn init(allocator: std.mem.Allocator, program: Program, group_count: u32, named_groups: ?[]const ast_mod.NamedGroupEntry) Vm {
        return .{
            .allocator = allocator,
            .program = program,
            .group_count = group_count,
            .named_groups = named_groups,
        };
    }

    pub fn deinit(self: *Vm) void {
        for (self.program.class_data.items) |cd| {
            self.program.allocator.free(cd.ranges);
        }
        self.program.class_data.deinit(self.program.allocator);
        self.program.instructions.deinit(self.program.allocator);
    }

    pub fn testMatch(self: *const Vm, input: []const u8, flags: Flags) !bool {
        var exec_state = ExecState{};
        var result = try self.exec(input, &exec_state, flags);
        if (result) |*m| {
            m.deinit(self.allocator);
            return true;
        }
        return false;
    }

    pub fn exec(self: *const Vm, input: []const u8, state: *ExecState, flags: Flags) !?MatchResult {
        const start_offset = if (flags.sticky or flags.global) state.last_index else 0;
        var steps: u64 = 0;

        var thread_stack = std.ArrayList(Thread).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer thread_stack.deinit(self.allocator);

        var search_start: u32 = start_offset;
        while (search_start <= input.len) : (search_start += 1) {
            var saves = [_]u32{0} ** SAVE_SLOTS;
            saves[0] = search_start;
            saves[1] = search_start;

            try thread_stack.append(self.allocator, .{
                .pc = 0,
                .input_pos = search_start,
                .saves = saves,
            });

            while (thread_stack.items.len > 0) {
                if (steps >= state.max_steps) {
                    return error.StepLimitExceeded;
                }
                steps += 1;

                var thread = thread_stack.pop().?;
                const result = self.runThread(input, &thread, &thread_stack, flags);
                switch (result) {
                    .matched => {
                        const end_pos = thread.saves[1];
                        if (flags.global or flags.sticky) {
                            if (end_pos > search_start) {
                                state.last_index = end_pos;
                            } else {
                                state.last_index = search_start + 1;
                            }
                        }
                        return try buildMatchResult(self, thread.saves, search_start, end_pos, flags.has_indices);
                    },
                    .running => {
                        try thread_stack.append(self.allocator, thread);
                    },
                    .failed => {},
                }
            }

            if (flags.sticky) {
                state.last_index = 0;
                return null;
            }

            if (search_start >= input.len) break;
        }

        if (flags.global) state.last_index = 0;
        return null;
    }

    const StepResult = enum {
        matched,
        running,
        failed,
    };

    fn runThread(self: *const Vm, input: []const u8, thread: *Thread, stack: *std.ArrayList(Thread), flags: Flags) StepResult {
        var pc = thread.pc;
        while (pc < self.program.instructions.items.len) {
            const inst = self.program.instructions.items[pc];

            switch (inst.opcode) {
                .match => {
                    thread.saves[1] = thread.input_pos;
                    return .matched;
                },
                .fail => {
                    return .failed;
                },
                .char => {
                    const cp = inst.operand1;
                    if (thread.input_pos >= input.len) return .failed;
                    const ch = input[thread.input_pos];
                    if (charsEqual(ch, @as(u21, @intCast(cp)), flags.ignore_case)) {
                        pc += 1;
                        thread.input_pos += 1;
                    } else {
                        return .failed;
                    }
                },
                .any => {
                    if (thread.input_pos >= input.len) return .failed;
                    const ch = input[thread.input_pos];
                    if (ch == '\n' or ch == '\r') {
                        if (!flags.dot_all) return .failed;
                    }
                    pc += 1;
                    thread.input_pos += 1;
                },
                .class => {
                    if (thread.input_pos >= input.len) return .failed;
                    const class_idx = inst.operand1;
                    if (class_idx >= self.program.class_data.items.len) return .failed;
                    const class_info = self.program.class_data.items[class_idx];
                    const ch = input[thread.input_pos];
                    var in_class = false;
                    for (class_info.ranges) |r| {
                        if (flags.ignore_case) {
                            const lower_ch = std.ascii.toLower(ch);
                            const lower_start = std.ascii.toLower(@as(u8, @intCast(r.start)));
                            const lower_end = std.ascii.toLower(@as(u8, @intCast(r.end)));
                            if (lower_ch >= lower_start and lower_ch <= lower_end) {
                                in_class = true;
                                break;
                            }
                        } else {
                            if (ch >= r.start and ch <= r.end) {
                                in_class = true;
                                break;
                            }
                        }
                    }
                    if (class_info.negated) in_class = !in_class;
                    if (in_class) {
                        pc += 1;
                        thread.input_pos += 1;
                    } else {
                        return .failed;
                    }
                },
                .jmp => {
                    pc = inst.operand1;
                },
                .split => {
                    stack.append(self.allocator, .{
                        .pc = inst.operand2,
                        .input_pos = thread.input_pos,
                        .saves = thread.saves,
                    }) catch return .failed;
                    pc = inst.operand1;
                },
                .save => {
                    const slot = inst.operand1;
                    if (slot < SAVE_SLOTS) {
                        thread.saves[slot] = thread.input_pos;
                    }
                    pc += 1;
                },
                .assert_bol => {
                    const is_start = thread.input_pos == 0;
                    const at_newline = if (flags.multiline and thread.input_pos > 0)
                        input[thread.input_pos - 1] == '\n'
                    else
                        false;
                    if (!is_start and !at_newline) return .failed;
                    pc += 1;
                },
                .assert_eol => {
                    const is_end = thread.input_pos >= input.len;
                    const at_newline = if (flags.multiline and thread.input_pos < input.len)
                        input[thread.input_pos] == '\n'
                    else
                        false;
                    if (!is_end and !at_newline) return .failed;
                    pc += 1;
                },
                .assert_wb => {
                    const inverted = inst.operand1 != 0;
                    const left_w = thread.input_pos > 0 and isWordChar(input[thread.input_pos - 1]);
                    const right_w = thread.input_pos < input.len and isWordChar(input[thread.input_pos]);
                    const is_boundary = left_w != right_w;
                    if (inverted) {
                        if (is_boundary) return .failed;
                    } else {
                        if (!is_boundary) return .failed;
                    }
                    pc += 1;
                },
                .look_start => {
                    const positive = inst.operand1 != 0;
                    const is_forward = inst.operand2 != 0;

                    if (is_forward) {
                        const saved_pos = thread.input_pos;
                        var look_thread = Thread{
                            .pc = pc + 1,
                            .input_pos = thread.input_pos,
                            .saves = thread.saves,
                        };
                        var look_stack = std.ArrayList(Thread).initCapacity(self.allocator, 0) catch return .failed;
                        defer look_stack.deinit(self.allocator);

                        const result = runLookaroundInternal(self, input, &look_thread, &look_stack, flags);
                        if (result == .matched) {
                            if (!positive) return .failed;
                            thread.input_pos = saved_pos;
                            pc = look_thread.pc;
                        } else {
                            if (positive) return .failed;
                            pc = skipLookEnd(self, pc + 1);
                        }
                    } else {
                        // ---- LOOKBEHIND (backward) ----
                        const saved_pos = thread.input_pos;
                        var found: bool = false;
                        var trial_pos: u32 = 0;
                        while (trial_pos <= saved_pos) : (trial_pos += 1) {
                            var lb_thread = Thread{
                                .pc = pc + 1,
                                .input_pos = trial_pos,
                                .saves = thread.saves,
                            };
                            var lb_stack = std.ArrayList(Thread).initCapacity(self.allocator, 0) catch return .failed;
                            defer lb_stack.deinit(self.allocator);
                            const result = runLookaroundInternal(self, input, &lb_thread, &lb_stack, flags);
                            if (result == .matched and lb_thread.input_pos == saved_pos) {
                                found = true;
                                break;
                            }
                        }
                        if (found) {
                            if (!positive) return .failed;
                            thread.input_pos = saved_pos;
                            pc = skipLookEnd(self, pc + 1);
                        } else {
                            if (positive) return .failed;
                            pc = skipLookEnd(self, pc + 1);
                        }
                    }
                },
                .look_end => {
                    pc += 1;
                },
                .backref => {
                    const cap_idx = inst.operand1;
                    const start_slot = cap_idx * 2;
                    const end_slot = cap_idx * 2 + 1;
                    const cap_start = thread.saves[start_slot];
                    const cap_end = thread.saves[end_slot];
                    if (cap_end <= cap_start) return .failed;
                    const cap_text = input[cap_start..cap_end];
                    if (thread.input_pos + cap_text.len > input.len) return .failed;
                    if (!std.mem.startsWith(u8, input[thread.input_pos..], cap_text)) return .failed;
                    thread.input_pos += @as(u32, @intCast(cap_text.len));
                    pc += 1;
                },
            }
        }
        return .failed;
    }

    fn skipLookEnd(self: *const Vm, start_pc: u32) u32 {
        var p: u32 = start_pc;
        var depth: u32 = 1;
        while (p < self.program.instructions.items.len) {
            if (self.program.instructions.items[p].opcode == .look_start) {
                depth += 1;
            } else if (self.program.instructions.items[p].opcode == .look_end) {
                depth -= 1;
                if (depth == 0) return p + 1;
            }
            p += 1;
        }
        return p;
    }

    fn runLookaroundInternal(self: *const Vm, input: []const u8, thread: *Thread, stack: *std.ArrayList(Thread), flags: Flags) StepResult {
        while (true) {
            var pc = thread.pc;
            while (pc < self.program.instructions.items.len) {
                const inst = self.program.instructions.items[pc];
                if (inst.opcode == .look_end) {
                    thread.saves[1] = thread.input_pos;
                    thread.pc = pc + 1;
                    return .matched;
                }
                if (inst.opcode == .match) {
                    thread.saves[1] = thread.input_pos;
                    return .matched;
                }
                switch (inst.opcode) {
                    .match => unreachable,
                    .fail => break,
                    .char => {
                        const cp = inst.operand1;
                        if (thread.input_pos >= input.len) break;
                        const ch = input[thread.input_pos];
                        if (charsEqual(ch, @as(u21, @intCast(cp)), flags.ignore_case)) {
                            pc += 1;
                            thread.input_pos += 1;
                        } else {
                            break;
                        }
                    },
                    .any => {
                        if (thread.input_pos >= input.len) break;
                        const ch = input[thread.input_pos];
                        if (ch == '\n' or ch == '\r') {
                            if (!flags.dot_all) break;
                        }
                        pc += 1;
                        thread.input_pos += 1;
                    },
                    .class => {
                        if (thread.input_pos >= input.len) break;
                        const class_idx = inst.operand1;
                        if (class_idx >= self.program.class_data.items.len) break;
                        const class_info = self.program.class_data.items[class_idx];
                        const ch = input[thread.input_pos];
                        var in_class = false;
                        for (class_info.ranges) |r| {
                            if (flags.ignore_case) {
                                const lower_ch = std.ascii.toLower(ch);
                                const lower_start = std.ascii.toLower(@as(u8, @intCast(r.start)));
                                const lower_end = std.ascii.toLower(@as(u8, @intCast(r.end)));
                                if (lower_ch >= lower_start and lower_ch <= lower_end) {
                                    in_class = true;
                                    break;
                                }
                            } else {
                                if (ch >= r.start and ch <= r.end) {
                                    in_class = true;
                                    break;
                                }
                            }
                        }
                        if (class_info.negated) in_class = !in_class;
                        if (in_class) {
                            pc += 1;
                            thread.input_pos += 1;
                        } else {
                            break;
                        }
                    },
                    .jmp => {
                        pc = inst.operand1;
                    },
                    .split => {
                        stack.append(self.allocator, .{
                            .pc = inst.operand2,
                            .input_pos = thread.input_pos,
                            .saves = thread.saves,
                        }) catch return .failed;
                        pc = inst.operand1;
                    },
                    .save => {
                        const slot = inst.operand1;
                        if (slot < SAVE_SLOTS) {
                            thread.saves[slot] = thread.input_pos;
                        }
                        pc += 1;
                    },
                    .assert_bol => {
                        const is_start = thread.input_pos == 0;
                        const at_newline = if (flags.multiline and thread.input_pos > 0)
                            input[thread.input_pos - 1] == '\n'
                        else
                            false;
                        if (!is_start and !at_newline) break;
                        pc += 1;
                    },
                    .assert_eol => {
                        const is_end = thread.input_pos >= input.len;
                        const at_newline = if (flags.multiline and thread.input_pos < input.len)
                            input[thread.input_pos] == '\n'
                        else
                            false;
                        if (!is_end and !at_newline) break;
                        pc += 1;
                    },
                    .assert_wb => {
                        const inverted = inst.operand1 != 0;
                        const left_w = thread.input_pos > 0 and isWordChar(input[thread.input_pos - 1]);
                        const right_w = thread.input_pos < input.len and isWordChar(input[thread.input_pos]);
                        const is_boundary = left_w != right_w;
                        if (inverted) {
                            if (is_boundary) break;
                        } else {
                            if (!is_boundary) break;
                        }
                        pc += 1;
                    },
                    .backref => {
                        const cap_idx = inst.operand1;
                        const start_slot = cap_idx * 2;
                        const end_slot = cap_idx * 2 + 1;
                        const cap_start = thread.saves[start_slot];
                        const cap_end = thread.saves[end_slot];
                        if (cap_end <= cap_start) break;
                        const cap_text = input[cap_start..cap_end];
                        if (thread.input_pos + cap_text.len > input.len) break;
                        if (!std.mem.startsWith(u8, input[thread.input_pos..], cap_text)) break;
                        thread.input_pos += @as(u32, @intCast(cap_text.len));
                        pc += 1;
                    },
                    .look_start => {
                        thread.pc = pc;
                        const result = self.runThread(input, thread, stack, flags);
                        if (result == .matched) {
                            thread.pc = pc;
                            return .matched;
                        }
                        break;
                    },
                    .look_end => {
                        thread.pc = pc;
                        return .matched;
                    },
                }
            }
            if (stack.items.len > 0) {
                thread.* = stack.pop().?;
            } else {
                return .failed;
            }
        }
    }

    fn buildMatchResult(self: *const Vm, saves: [SAVE_SLOTS]u32, start: u32, end: u32, has_indices: bool) !MatchResult {
        const allocator = self.allocator;

        var captures = try allocator.alloc(Capture, self.group_count);
        for (0..self.group_count) |i| {
            const s = saves[i * 2 + 2];
            const e = saves[i * 2 + 3];
            if (e > s) {
                captures[i] = .{ .span = .{ .start = s, .end = e } };
            } else if (s != 0 and e == s) {
                captures[i] = .{ .span = .{ .start = s, .end = e } };
            } else {
                captures[i] = .{ .span = null };
            }
        }

        var named: ?[]NamedCapture = null;
        if (self.named_groups) |ng| {
            named = try allocator.alloc(NamedCapture, ng.len);
            for (ng, 0..) |entry, j| {
                const cap_idx = entry.index - 1;
                named.?[j] = .{
                    .name = entry.name,
                    .span = captures[cap_idx].span,
                };
            }
        }

        var indices: ?[]Span = null;
        if (has_indices) {
            indices = try allocator.alloc(Span, self.group_count + 1);
            indices.?[0] = .{ .start = start, .end = end };
            for (0..self.group_count) |i| {
                if (captures[i].span) |s| {
                    indices.?[i + 1] = s;
                } else {
                    indices.?[i + 1] = .{ .start = 0, .end = 0 };
                }
            }
        }

        return .{
            .span = .{ .start = start, .end = end },
            .captures = captures,
            .named = named,
            .indices = indices,
        };
    }

    fn isWordChar(ch: u8) bool {
        return switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '_' => true,
            else => false,
        };
    }

    fn charsEqual(a: u8, b: u21, ignore_case: bool) bool {
        if (ignore_case) {
            if (b <= 127) {
                return std.ascii.toLower(a) == std.ascii.toLower(@as(u8, @intCast(b)));
            }
        }
        return a == b;
    }
};

pub const Flags = struct {
    global: bool = false,
    ignore_case: bool = false,
    multiline: bool = false,
    dot_all: bool = false,
    unicode: bool = false,
    sticky: bool = false,
    has_indices: bool = false,
};
