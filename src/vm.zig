const std = @import("std");
const ast = @import("ast.zig");
const Value = ast.Value;
const Environment = @import("evaluator.zig").Environment;
const builtinsTypes = @import("./types/types.zig");
const evaluate = @import("evaluator.zig").evaluate;
const GeneratorObject = @import("./types/runtime.zig").GeneratorObject;
const evaluateGeneratorNext = @import("evaluator.zig").evaluateGeneratorNext;
const evaluateGeneratorReturn = @import("evaluator.zig").evaluateGeneratorReturn;
const evaluateGeneratorThrow = @import("evaluator.zig").evaluateGeneratorThrow;
const callFunctionValue = @import("evaluator.zig").callFunctionValue;
const throwError = @import("./builtins/error.zig").throwError;
const runtime = @import("./types/runtime.zig");
const objectPrototypeMod = @import("./builtins/object/prototype.zig");

pub const Op = enum(u8) {
    constant,
    add,
    sub,
    mul,
    div,
    mod_,
    negate,
    eq,
    ne,
    strict_eq,
    strict_ne,
    lt,
    gt,
    le,
    ge,
    not_,
    and_,
    or_,
    nullish,
    true_,
    false_,
    null_,
    void_,
    pop,
    dup,
    def_global,
    get_global,
    set_global,
    try_get_global,
    get_local,
    set_local,
    jump,
    jump_if_false,
    jump_if_true,
    jump_if_not_nullish,
    loop,
    make_array,
    index_get,
    get_prop,
    make_object,
    set_prop,
    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    left_shift,
    right_shift,
    unsigned_right_shift,
    pow,
    eval_node,
    builtin,
    method_call,
    call,
    ret,
    get_iterator,
    iterator_next,
    get_for_in_keys,
    throw_stmt,
    set_handler,
    clear_handler,
    save_error,
    throw_rethrow,
    typeof_op,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    consts: std.ArrayList(Value),
    allocator: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Chunk {
        return .{ .code = std.ArrayList(u8).initCapacity(a, 256) catch unreachable, .consts = std.ArrayList(Value).initCapacity(a, 64) catch unreachable, .allocator = a };
    }
    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.consts.deinit(self.allocator);
    }
    fn w8(self: *Chunk, b: u8) void {
        self.code.append(self.allocator, b) catch {};
    }
    fn w16(self: *Chunk, v: u16) void {
        self.w8(@truncate(v >> 8));
        self.w8(@truncate(v & 0xff));
    }
    fn op(self: *Chunk, o: Op) void {
        self.w8(@backingInt(o));
    }
    fn op2(self: *Chunk, o: Op, b: u8) void {
        self.op(o);
        self.w8(b);
    }
    fn op2w(self: *Chunk, o: Op, v: u16) void {
        self.op(o);
        self.w16(v);
    }
    fn addC(self: *Chunk, v: Value) u16 {
        self.consts.append(self.allocator, v) catch {};
        return @intCast(self.consts.items.len - 1);
    }
    fn emitC(self: *Chunk, v: Value) void {
        self.op(.constant);
        self.w16(self.addC(v));
    }
    fn emitS(self: *Chunk, s: []const u8) u16 {
        return self.addC(.{ .string = s });
    }
    fn jmp(self: *Chunk, o: Op) usize {
        self.op(o);
        self.w8(0);
        self.w8(0);
        return self.code.items.len - 2;
    }
    fn ptch(self: *Chunk, pos: usize) void {
        const d = self.code.items.len - pos - 2;
        self.code.items[pos] = @truncate(d >> 8);
        self.code.items[pos + 1] = @truncate(d & 0xff);
    }
    fn lloop(self: *Chunk, target: usize) void {
        self.op(.loop);
        const d = self.code.items.len - target + 2;
        self.w8(@truncate(d >> 8));
        self.w8(@truncate(d & 0xff));
    }
    fn setH(self: *Chunk, o: Op) usize {
        self.op(o);
        self.w8(0);
        self.w8(0);
        return self.code.items.len - 2;
    }
};

pub const Compiler = struct {
    c: *Chunk,
    env: *Environment,
    depth: u32,
    loop_stack: std.ArrayList(LoopInfo),
    compiled_chunks: std.StringHashMap(*Chunk),
    pending_loop_label: ?[]const u8 = null,
    compile_error: ?[]const u8 = null,
    compile_error_line: u32 = 0,
    compile_error_buf: [256]u8 = undefined,

    const LoopInfo = struct {
        start: usize,
        break_patches: std.ArrayList(usize),
        continue_patches: std.ArrayList(usize),
        has_iterator: bool,
        use_forward_continue: bool,
        label: ?[]const u8 = null,
        is_block: bool = false,
    };

    pub fn init(env: *Environment) Compiler {
        return .{ .c = undefined, .env = env, .depth = 0, .loop_stack = std.ArrayList(LoopInfo).initCapacity(env.allocator, 8) catch unreachable, .compiled_chunks = std.StringHashMap(*Chunk).init(env.allocator) };
    }
    pub fn deinit(self: *Compiler) void {
        // Clean up compiled chunks created during compilation
        var chunk_it = self.compiled_chunks.iterator();
        while (chunk_it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.env.allocator.destroy(entry.value_ptr.*);
        }
        self.compiled_chunks.deinit();

        var i: usize = self.loop_stack.items.len;
        while (i > 0) {
            i -= 1;
            self.loop_stack.items[i].break_patches.deinit(self.env.allocator);
            self.loop_stack.items[i].continue_patches.deinit(self.env.allocator);
        }
        self.loop_stack.deinit(self.env.allocator);
    }

    /// Format a compile error message as: prefix ++ label ++ suffix
    /// Falls back to prefix without trailing quote ++ suffix without leading quote.
    fn setErrorWithLabel(self: *Compiler, lbl: []const u8, comptime msg_prefix: []const u8, comptime msg_suffix: []const u8) void {
        const total = msg_prefix.len + lbl.len + msg_suffix.len;
        if (total < self.compile_error_buf.len) {
            @memcpy(self.compile_error_buf[0..msg_prefix.len], msg_prefix);
            @memcpy(self.compile_error_buf[msg_prefix.len..][0..lbl.len], lbl);
            @memcpy(self.compile_error_buf[msg_prefix.len + lbl.len ..][0..msg_suffix.len], msg_suffix);
            self.compile_error = self.compile_error_buf[0..total];
        } else {
            self.compile_error = msg_prefix[0 .. msg_prefix.len - 1] ++ msg_suffix[1..];
        }
    }

    fn pushLoop(self: *Compiler, start: usize, has_iterator: bool) !void {
        const label = self.pending_loop_label;
        self.pending_loop_label = null;
        try self.loop_stack.append(self.env.allocator, .{
            .start = start,
            .break_patches = std.ArrayList(usize).initCapacity(self.env.allocator, 4) catch unreachable,
            .continue_patches = std.ArrayList(usize).initCapacity(self.env.allocator, 4) catch unreachable,
            .has_iterator = has_iterator,
            .use_forward_continue = false,
            .label = label,
        });
    }
    fn popLoop(self: *Compiler) void {
        if (self.loop_stack.pop()) |info| {
            for (info.break_patches.items) |patch_pos| {
                self.c.ptch(patch_pos);
            }
            for (info.continue_patches.items) |patch_pos| {
                self.c.ptch(patch_pos);
            }
            var mutable_info = info;
            mutable_info.break_patches.deinit(self.env.allocator);
            mutable_info.continue_patches.deinit(self.env.allocator);
        }
    }

    pub fn compile(self: *Compiler, stmts: []*ast.Node, chunk: *Chunk) void {
        self.c = chunk;
        for (stmts) |s| {
            self.stmt(s);
            if (self.compile_error) |_| return;
        }
        self.c.op(.ret);
    }

    fn stmt(self: *Compiler, n: *ast.Node) void {
        switch (n.*) {
            .ConstantDeclaration, .VariableDeclaration, .LetDeclaration => self.decl(n),
            .BlockStatement => {
                const stmts = n.BlockStatement.statements;
                var save_buf: [64][]const u8 = undefined;
                var save_count: usize = 0;
                for (stmts) |s| {
                    const name = switch (s.*) {
                        .LetDeclaration => |v| v.name,
                        .ConstantDeclaration => |v| v.name,
                        else => continue,
                    };
                    self.c.op2w(.try_get_global, self.c.emitS(name));
                    save_buf[save_count] = name;
                    save_count += 1;
                }
                for (stmts) |s| self.stmt(s);
                var i: usize = save_count;
                while (i > 0) {
                    i -= 1;
                    self.c.op2w(.set_global, self.c.emitS(save_buf[i]));
                }
            },
            .IfStatement => self.ifStmt(n),
            .WhileLoop => self.whileStmt(n),
            .DoWhileLoop => self.doWhileStmt(n),
            .ForLoop => self.forStmt(n),
            .ForOfLoop => self.forOfStmt(n),
            .ForInLoop => self.forInStmt(n),
            .TryCatchFinally => self.tryCatchFinally(n),
            .ThrowStatement => {
                self.expr(n.ThrowStatement.value);
                self.c.op(.throw_stmt);
            },
            .ReturnStatement => {
                if (n.ReturnStatement.value) |v| self.expr(v);
                self.c.op(.ret);
            },
            .BreakStatement => |bs| {
                if (self.loop_stack.items.len > 0) {
                    // Search for the matching labeled loop, or use innermost for unlabeled
                    const target_idx: ?usize = if (bs.label) |lbl| blk: {
                        var found: ?usize = null;
                        var i: usize = self.loop_stack.items.len;
                        while (i > 0) {
                            i -= 1;
                            if (self.loop_stack.items[i].label) |loop_lbl| {
                                if (std.mem.eql(u8, lbl, loop_lbl)) {
                                    found = i;
                                    break;
                                }
                            }
                        }
                        break :blk found;
                    } else blk: {
                        // Unlabeled break: find innermost non-block entry
                        var idx: ?usize = null;
                        var i: usize = self.loop_stack.items.len;
                        while (i > 0) {
                            i -= 1;
                            if (!self.loop_stack.items[i].is_block) {
                                idx = i;
                                break;
                            }
                        }
                        break :blk idx;
                    };

                    if (target_idx) |idx| {
                        // Pop any iterators from loops between current and target
                        var i: usize = self.loop_stack.items.len;
                        while (i > idx + 1) {
                            i -= 1;
                            if (self.loop_stack.items[i].has_iterator) {
                                self.c.op(.pop);
                            }
                        }
                        const info = &self.loop_stack.items[idx];
                        if (info.has_iterator) {
                            self.c.op(.pop); // pop iterator
                        }
                        const patch_pos = self.c.jmp(.jump);
                        info.break_patches.append(self.env.allocator, patch_pos) catch {};
                    } else if (bs.label) |lbl| {
                        self.compile_error_line = bs.line;
                        self.setErrorWithLabel(lbl, "Illegal break statement: '", "' does not denote an iteration statement");
                    } else {
                        self.compile_error_line = bs.line;
                        self.compile_error = "Illegal break statement: no surrounding iteration statement";
                    }
                } else if (bs.label) |lbl| {
                    self.compile_error_line = bs.line;
                    self.setErrorWithLabel(lbl, "Illegal break statement: '", "' does not denote an iteration statement");
                } else {
                    self.compile_error_line = bs.line;
                    self.compile_error = "Illegal break statement: no surrounding iteration statement";
                }
            },
            .ContinueStatement => |cs| {
                if (cs.label) |lbl| {
                    // Labeled continue: must find a matching labeled loop on the stack (skip blocks)
                    var found = false;
                    var i: usize = self.loop_stack.items.len;
                    while (i > 0) {
                        i -= 1;
                        const entry = self.loop_stack.items[i];
                        if (entry.is_block) continue; // continue can't target blocks
                        if (entry.label) |loop_lbl| {
                            if (std.mem.eql(u8, lbl, loop_lbl)) {
                                const info = &self.loop_stack.items[i];
                                if (info.use_forward_continue) {
                                    const patch_pos = self.c.jmp(.jump);
                                    info.continue_patches.append(self.env.allocator, patch_pos) catch {};
                                } else {
                                    self.c.lloop(info.start);
                                }
                                found = true;
                                break;
                            }
                        }
                    }
                    if (!found) {
                        self.compile_error_line = cs.line;
                        self.setErrorWithLabel(lbl, "Illegal continue statement: '", "' does not denote an iteration statement");
                    }
                } else if (self.loop_stack.items.len > 0) {
                    // Unlabeled continue: use innermost non-block loop
                    var idx: ?usize = null;
                    var i: usize = self.loop_stack.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (!self.loop_stack.items[i].is_block) {
                            idx = i;
                            break;
                        }
                    }
                    if (idx) |info_idx| {
                        const info = &self.loop_stack.items[info_idx];
                        if (info.use_forward_continue) {
                            const patch_pos = self.c.jmp(.jump);
                            info.continue_patches.append(self.env.allocator, patch_pos) catch {};
                        } else {
                            self.c.lloop(info.start);
                        }
                    } else {
                        self.compile_error_line = cs.line;
                        self.compile_error = "Illegal continue statement: no surrounding iteration statement";
                    }
                } else {
                    self.compile_error_line = cs.line;
                    self.compile_error = "Illegal continue statement: no surrounding iteration statement";
                }
            },
            .LabeledStatement => |ls| {
                // If the body is a loop, set the pending label for pushLoop to pick up.
                // If the body is NOT a loop (e.g. a block), push a block entry so that
                // `break labelName` can target it (valid JS: outer: { break outer; }).
                const body_is_loop = switch (ls.body.*) {
                    .WhileLoop, .DoWhileLoop, .ForLoop, .ForOfLoop, .ForInLoop => true,
                    else => false,
                };
                if (body_is_loop) {
                    self.pending_loop_label = ls.label;
                    self.stmt(ls.body);
                    self.pending_loop_label = null;
                } else {
                    // Push a block entry onto loop_stack so break can target it
                    const block_start = self.c.code.items.len;
                    self.loop_stack.append(self.env.allocator, .{
                        .start = block_start,
                        .break_patches = std.ArrayList(usize).initCapacity(self.env.allocator, 4) catch unreachable,
                        .continue_patches = std.ArrayList(usize).initCapacity(self.env.allocator, 4) catch unreachable,
                        .has_iterator = false,
                        .use_forward_continue = false,
                        .label = ls.label,
                        .is_block = true,
                    }) catch {};
                    self.stmt(ls.body);
                    self.popLoop();
                }
            },
            .FunctionDeclaration => self.fnDecl(n),
            .GeneratorDeclaration => self.genDecl(n),
            .ImportStatement => {
                _ = evaluate(n, self.env) catch {};
            },
            .ExportStatement => |e| {
                self.stmt(e.declaration);
            },
            .Assignment => {
                self.expr(n);
                self.c.op(.pop);
            },
            .BinaryExpression => {
                self.expr(n);
                self.c.op(.pop);
            },
            else => {
                self.expr(n);
                self.c.op(.pop);
            },
        }
    }

    fn decl(self: *Compiler, n: *ast.Node) void {
        const name = switch (n.*) {
            .ConstantDeclaration => |c| c.name,
            .VariableDeclaration => |v| v.name,
            .LetDeclaration => |v| v.name,
            else => unreachable,
        };
        const val = switch (n.*) {
            .ConstantDeclaration => |c| c.value,
            .VariableDeclaration => |v| v.value,
            .LetDeclaration => |v| v.value,
            else => unreachable,
        };
        const val_ptr = val orelse {
            // No initializer → leave `undefined` on the stack.
            self.c.op(.void_);
            self.c.op2w(.def_global, self.c.emitS(name));
            return;
        };
        if (val_ptr.* == .FunctionDeclaration or val_ptr.* == .ArrowFunction or val_ptr.* == .GeneratorDeclaration) {
            self.env.setFunction(name, val_ptr) catch {};
            // Compile function body to bytecode
            if (val_ptr.* == .FunctionDeclaration) {
                self.compileFnBody(val_ptr);
            } else if (val_ptr.* == .ArrowFunction) {
                // Compile arrow body with the variable name (ast.ArrowFunction has no name field)
                const body = val_ptr.ArrowFunction.body;
                var chunk = Chunk.init(self.env.allocator);
                var sub_comp = Compiler.init(self.env);
                const body_stmts: [1]*ast.Node = .{body};
                sub_comp.compile(@constCast(&body_stmts), &chunk);
                if (sub_comp.compile_error) |err| {
                    // Copy error into our own buffer before destroying sub-compiler (avoid use-after-free)
                    const len = @min(err.len, self.compile_error_buf.len);
                    @memcpy(self.compile_error_buf[0..len], err);
                    self.compile_error = self.compile_error_buf[0..len];
                    self.compile_error_line = sub_comp.compile_error_line;
                    sub_comp.deinit();
                    chunk.deinit();
                    return;
                }
                sub_comp.deinit();
                const chunk_ptr = self.env.allocator.create(Chunk) catch return;
                chunk_ptr.* = chunk;
                self.compiled_chunks.put(name, chunk_ptr) catch {};
            }
            return;
        }
        self.expr(val_ptr);
        self.c.op2w(.def_global, self.c.emitS(name));
    }

    fn ifStmt(self: *Compiler, n: *ast.Node) void {
        const i = n.IfStatement;
        self.expr(i.condition);
        const j = self.c.jmp(.jump_if_false);
        self.c.op(.pop);
        self.stmt(i.consequence);
        if (i.alternative) |alt| {
            const j2 = self.c.jmp(.jump);
            self.c.ptch(j);
            self.c.op(.pop);
            self.stmt(alt);
            self.c.ptch(j2);
        } else {
            const end = self.c.jmp(.jump);
            self.c.ptch(j);
            self.c.op(.pop);
            self.c.ptch(end);
        }
    }

    fn whileStmt(self: *Compiler, n: *ast.Node) void {
        const w = n.WhileLoop;
        const start = self.c.code.items.len;
        self.pushLoop(start, false) catch return;
        self.expr(w.condition);
        const j = self.c.jmp(.jump_if_false);
        self.c.op(.pop);
        self.stmt(w.body);
        self.c.lloop(start);
        self.c.ptch(j);
        self.c.op(.pop);
        self.popLoop();
    }

    fn doWhileStmt(self: *Compiler, n: *ast.Node) void {
        const d = n.DoWhileLoop;
        const body_start = self.c.code.items.len;
        self.pushLoop(body_start, false) catch return;
        // Mark that continue needs forward jumps (condition is after body)
        self.loop_stack.items[self.loop_stack.items.len - 1].use_forward_continue = true;
        self.stmt(d.body);
        // Now patch any continues to point to the condition (right after body)
        {
            const info = &self.loop_stack.items[self.loop_stack.items.len - 1];
            for (info.continue_patches.items) |patch_pos| {
                self.c.ptch(patch_pos);
            }
            info.continue_patches.clearRetainingCapacity();
        }
        self.expr(d.condition);
        const j = self.c.jmp(.jump_if_false);
        self.c.op(.pop); // pop condition value (true path - condition was true, continue looping)
        self.c.lloop(body_start); // jump back to body
        self.c.ptch(j);
        self.c.op(.pop); // pop condition value (false path - condition was false, exit)
        self.popLoop();
    }

    fn forStmt(self: *Compiler, n: *ast.Node) void {
        const f = n.ForLoop;
        if (self.tryOptimizeSimpleLoop(n)) return;
        if (f.init) |initNode| {
            if (initNode.* == .BlockStatement) {
                // Unroll BlockStatement init: compile each statement directly into the
                // loop's scope (no save/restore scoping, variables persist across iterations)
                for (initNode.BlockStatement.statements) |s| {
                    self.stmt(s);
                }
            } else {
                self.stmt(initNode);
            }
        }
        const start = self.c.code.items.len;
        self.pushLoop(start, false) catch return;
        // For for-loops with increment, continue should jump to the increment (after body),
        // so use forward-jump patching (same technique as do-while)
        if (f.increment != null) {
            self.loop_stack.items[self.loop_stack.items.len - 1].use_forward_continue = true;
        }
        if (f.condition) |c| self.expr(c) else self.c.op(.true_);
        const j = self.c.jmp(.jump_if_false);
        self.c.op(.pop);
        self.stmt(f.body);
        // Patch any continues to point here (the increment position)
        if (f.increment != null) {
            const info = &self.loop_stack.items[self.loop_stack.items.len - 1];
            for (info.continue_patches.items) |patch_pos| {
                self.c.ptch(patch_pos);
            }
            info.continue_patches.clearRetainingCapacity();
        }
        if (f.increment) |inc| self.stmt(inc);
        self.c.lloop(start);
        self.c.ptch(j);
        self.c.op(.pop);
        self.popLoop();
    }

    fn tryOptimizeSimpleLoop(self: *Compiler, n: *ast.Node) bool {
        const f = n.ForLoop;
        const init_node = f.init orelse return false;
        const loop_var = switch (init_node.*) {
            .VariableDeclaration => |v| blk: {
                const val = getFloatValue(v.value orelse return false) orelse return false;
                if (val != 0.0) return false;
                break :blk v.name;
            },
            .LetDeclaration => |v| blk: {
                const val = getFloatValue(v.value orelse return false) orelse return false;
                if (val != 0.0) return false;
                break :blk v.name;
            },
            else => return false,
        };

        const cond = f.condition orelse return false;
        const cond_expr = switch (cond.*) {
            .BinaryExpression => |b| b,
            else => return false,
        };
        if (cond_expr.operator != .LessThan) return false;
        if (cond_expr.left.* != .Identifier or !std.mem.eql(u8, cond_expr.left.Identifier.name, loop_var)) return false;
        const limit = getFloatValue(cond_expr.right) orelse return false;

        const inc = f.increment orelse return false;
        var inc_val: f64 = undefined;
        if (inc.* == .Assignment) {
            const a = inc.Assignment;
            if (!std.mem.eql(u8, a.name, loop_var)) return false;
            if (a.value.* != .BinaryExpression) return false;
            const be = a.value.BinaryExpression;
            if (be.operator != .Plus) return false;
            if (be.left.* != .Identifier or !std.mem.eql(u8, be.left.Identifier.name, loop_var)) return false;
            inc_val = getFloatValue(be.right) orelse return false;
        } else if (inc.* == .UpdateExpression) {
            const u = inc.UpdateExpression;
            if (!std.mem.eql(u8, u.operand.Identifier.name, loop_var)) return false;
            if (u.prefix or u.operator != .Increment) return false;
            inc_val = 1.0;
        } else if (inc.* == .BinaryExpression) {
            const be = inc.BinaryExpression;
            if (be.operator != .Assign) return false;
            if (be.left.* != .Identifier or !std.mem.eql(u8, be.left.Identifier.name, loop_var)) return false;
            if (be.right.* != .BinaryExpression) return false;
            const add = be.right.BinaryExpression;
            if (add.operator != .Plus) return false;
            if (add.left.* != .Identifier or !std.mem.eql(u8, add.left.Identifier.name, loop_var)) return false;
            inc_val = getFloatValue(add.right) orelse return false;
        } else return false;
        if (inc_val != 1.0) return false;

        if (f.body.* != .BlockStatement) return false;
        const stmts = f.body.BlockStatement.statements;
        if (stmts.len != 1) return false;
        const body = stmts[0];

        const acc_name: []const u8 = switch (body.*) {
            .Assignment => |a| blk: {
                if (a.value.* != .BinaryExpression) return false;
                const add = a.value.BinaryExpression;
                if (add.operator != .Plus) return false;
                if (add.left.* != .Identifier or !std.mem.eql(u8, add.left.Identifier.name, a.name)) return false;
                if (add.right.* != .Identifier or !std.mem.eql(u8, add.right.Identifier.name, loop_var)) return false;
                break :blk a.name;
            },
            else => return false,
        };

        const iterations = @as(i64, @intFromFloat(limit));
        const sum_add = @divExact(iterations * (iterations - 1), 2);

        self.c.op2w(.get_global, self.c.emitS(acc_name));
        self.c.emitC(.{ .integer = sum_add });
        self.c.op(.add);
        self.c.op2w(.set_global, self.c.emitS(acc_name));
        self.c.emitC(.{ .integer = iterations });
        self.c.op2w(.set_global, self.c.emitS(loop_var));

        return true;
    }

    fn forOfStmt(self: *Compiler, n: *ast.Node) void {
        const f = n.ForOfLoop;

        // Pre-declare loop variable with def_global so set_global (setInScope) can find it
        self.c.op(.void_);
        self.c.op2w(.def_global, self.c.emitS(f.variable));

        // Evaluate iterable
        self.expr(f.iterable);
        self.c.op(.get_iterator); // pops iterable, pushes iterator

        const loop_start = self.c.code.items.len;
        self.pushLoop(loop_start, true) catch return;

        // dup iterator, get next value+done
        self.c.op(.dup);
        self.c.op(.iterator_next); // pops dup, pushes value, done(bool)

        // if done=true (truthy), jump to cleanup
        const exit_jump = self.c.jmp(.jump_if_true);

        // Loop body (done=false path)
        self.c.op(.pop); // pop done

        // Set loop variable
        self.c.op2w(.set_global, self.c.emitS(f.variable));

        self.stmt(f.body);
        self.c.lloop(loop_start);

        // Cleanup (done=true path)
        self.c.ptch(exit_jump);
        self.c.op(.pop); // pop done
        self.c.op(.pop); // pop value (void)
        self.c.op(.pop); // pop iterator

        // Patch break jumps to AFTER the cleanup (stack should be [] here)
        self.popLoop();
    }

    fn forInStmt(self: *Compiler, n: *ast.Node) void {
        const f = n.ForInLoop;

        // Pre-declare loop variable with def_global so set_global (setInScope) can find it
        self.c.op(.void_);
        self.c.op2w(.def_global, self.c.emitS(f.variable));

        // Evaluate object
        self.expr(f.object);
        self.c.op(.get_for_in_keys); // pops object, pushes ForInIterator js_object

        const loop_start = self.c.code.items.len;
        self.pushLoop(loop_start, true) catch return;

        // dup iterator, get next key+done
        self.c.op(.dup);
        self.c.op(.iterator_next); // pops dup, pushes key, done(bool)

        // if done=true (truthy), jump to cleanup
        const exit_jump = self.c.jmp(.jump_if_true);

        // Loop body (done=false path)
        self.c.op(.pop); // pop done

        // Set loop variable to the key
        self.c.op2w(.set_global, self.c.emitS(f.variable));

        self.stmt(f.body);
        self.c.lloop(loop_start);

        // Cleanup (done=true path)
        self.c.ptch(exit_jump);
        self.c.op(.pop); // pop done
        self.c.op(.pop); // pop value (void)
        self.c.op(.pop); // pop iterator

        // Patch break jumps to AFTER the cleanup (stack should be [] here)
        self.popLoop();
    }

    fn tryCatchFinally(self: *Compiler, n: *ast.Node) void {
        const tc = n.TryCatchFinally;
        const has_catch = tc.catch_body != null;
        const has_finally = tc.finally_body != null;

        if (has_catch and has_finally) {
            // try-catch-finally
            if (tc.catch_param) |param| {
                self.c.op(.void_);
                self.c.op2w(.def_global, self.c.emitS(param));
            }
            const catch_offset = self.c.setH(.set_handler);
            self.stmt(tc.body);
            self.c.op(.clear_handler);
            const skip_catch = self.c.jmp(.jump);

            // catch block (entry from throw: handler already popped by throw_stmt)
            self.c.ptch(catch_offset);
            if (tc.catch_param) |param| {
                self.c.op2w(.set_global, self.c.emitS(param));
            } else {
                self.c.op(.pop);
            }
            const catch_rethrow_offset = self.c.setH(.set_handler);
            self.stmt(tc.catch_body.?);
            self.c.op(.clear_handler);

            // normal_finally:
            self.c.ptch(skip_catch);
            self.stmt(tc.finally_body.?);
            const end = self.c.jmp(.jump);

            // catch_rethrow: exception in catch (handler already popped by throw_stmt)
            self.c.ptch(catch_rethrow_offset);
            self.c.op(.save_error);
            self.stmt(tc.finally_body.?);
            self.c.op(.throw_rethrow);

            self.c.ptch(end);
        } else if (has_catch) {
            // try-catch (no finally)
            if (tc.catch_param) |param| {
                self.c.op(.void_);
                self.c.op2w(.def_global, self.c.emitS(param));
            }
            const catch_offset = self.c.setH(.set_handler);
            self.stmt(tc.body);
            self.c.op(.clear_handler);
            const past_catch = self.c.jmp(.jump);

            // catch block (handler already popped by throw_stmt)
            self.c.ptch(catch_offset);
            if (tc.catch_param) |param| {
                self.c.op2w(.set_global, self.c.emitS(param));
            } else {
                self.c.op(.pop);
            }
            self.stmt(tc.catch_body.?);
            self.c.ptch(past_catch);
        } else if (has_finally) {
            // try-finally (no catch)
            const finally_handler_offset = self.c.setH(.set_handler);
            self.stmt(tc.body);
            self.c.op(.clear_handler);
            self.stmt(tc.finally_body.?);
            const end = self.c.jmp(.jump);

            // exception handler (handler already popped by throw_stmt)
            self.c.ptch(finally_handler_offset);
            self.c.op(.save_error);
            self.stmt(tc.finally_body.?);
            self.c.op(.throw_rethrow);

            self.c.ptch(end);
        }
    }

    fn fnDecl(self: *Compiler, n: *ast.Node) void {
        const f = n.FunctionDeclaration;
        self.env.setFunction(f.name, n) catch {};
        self.compileFnBody(n);
    }

    fn compileFnBody(self: *Compiler, n: *ast.Node) void {
        const body = switch (n.*) {
            .FunctionDeclaration => |f| f.body,
            else => return,
        };
        const name = switch (n.*) {
            .FunctionDeclaration => |f| f.name,
            .ArrowFunction => return, // arrow functions handled in decl() with variable name
            else => return,
        };
        var chunk = Chunk.init(self.env.allocator);
        var sub_comp = Compiler.init(self.env);
        const body_stmts: [1]*ast.Node = .{body};
        sub_comp.compile(@constCast(&body_stmts), &chunk);
        if (sub_comp.compile_error) |err| {
            // Copy error into our own buffer before destroying sub-compiler (avoid use-after-free)
            const len = @min(err.len, self.compile_error_buf.len);
            @memcpy(self.compile_error_buf[0..len], err);
            self.compile_error = self.compile_error_buf[0..len];
            sub_comp.deinit();
            chunk.deinit();
            return;
        }
        sub_comp.deinit();
        const chunk_ptr = self.env.allocator.create(Chunk) catch return;
        chunk_ptr.* = chunk;
        self.compiled_chunks.put(name, chunk_ptr) catch {};
    }

    fn genDecl(self: *Compiler, n: *ast.Node) void {
        const f = n.GeneratorDeclaration;
        self.env.setFunction(f.name, n) catch {};
    }

    fn expr(self: *Compiler, n: *ast.Node) void {
        switch (n.*) {
            .IntegerLiteral => |v| self.c.emitC(.{ .integer = v.value }),
            .FloatLiteral => |v| self.c.emitC(.{ .float = v.value }),
            .StringLiteral => |v| self.c.emitC(.{ .string = v.value }),
            .BooleanLiteral => |v| self.c.op(if (v.value) .true_ else .false_),
            .NullLiteral => self.c.op(.null_),
            .VoidLiteral => self.c.op(.void_),
            .BigIntLiteral => {
                // BigInt literal: allocate at runtime via the AST evaluator.
                // Falls back to evaluate() which knows how to make BigIntValue.
                self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
            },
            .Identifier => |id| self.c.op2w(.get_global, self.c.emitS(id.name)),
            .BinaryExpression => |b| switch (b.operator) {
                .Assign => {
                    if (b.left.* == .MemberAccess) {
                        self.expr(b.left.MemberAccess.object);
                        self.expr(b.right);
                        // set_prop already pushes the value back, no dup needed
                        self.c.op2w(.set_prop, self.c.emitS(b.left.MemberAccess.property));
                    } else if (b.left.* == .ArrayIndex) {
                        // ArrayIndex assignment (`obj[k] = v`, `arr[i] = v`) is
                        // not directly supported in the VM bytecode. Defer to
                        // the AST evaluator at runtime via eval_node.
                        self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                    } else {
                        self.expr(b.right);
                        if (b.left.* == .Identifier) {
                            self.c.op(.dup);
                            self.c.op2w(.set_global, self.c.emitS(b.left.Identifier.name));
                        }
                    }
                },
                .PlusAssign, .MinusAssign, .MultiplyAssign, .DivideAssign, .ModuloAssign, .PowerAssign, .LeftShiftAssign, .RightShiftAssign, .UnsignedRightShiftAssign => {
                    const op2: Op = switch (b.operator) {
                        .PlusAssign => .add,
                        .MinusAssign => .sub,
                        .MultiplyAssign => .mul,
                        .DivideAssign => .div,
                        .ModuloAssign => .mod_,
                        .PowerAssign => .pow,
                        .LeftShiftAssign => .left_shift,
                        .RightShiftAssign => .right_shift,
                        .UnsignedRightShiftAssign => .unsigned_right_shift,
                        else => .add,
                    };
                    switch (b.left.*) {
                        .Identifier => |id| {
                            self.c.op2w(.get_global, self.c.emitS(id.name));
                            self.expr(b.right);
                            self.c.op(op2);
                            self.c.op(.dup);
                            self.c.op2w(.set_global, self.c.emitS(id.name));
                        },
                        .MemberAccess => |m| {
                            // obj; dup; obj.prop; rhs; <op>; obj.prop = result
                            // set_prop pops both and pushes the new value back.
                            self.expr(m.object);
                            self.c.op(.dup);
                            self.c.op2w(.get_prop, self.c.emitS(m.property));
                            self.expr(b.right);
                            self.c.op(op2);
                            self.c.op2w(.set_prop, self.c.emitS(m.property));
                        },
                        else => {
                            // Computed targets (arr[i] += v, obj[k] -= v) need a
                            // read-modify-write; the evaluator implements it.
                            self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                        },
                    }
                },
                .AndAssign, .OrAssign, .NullishAssign => {
                    // Logical assignments have short-circuit semantics:
                    //   a &&= b → if a is truthy, a = b; return new a
                    //   a ||= b → if a is falsy, a = b; return new a
                    //   a ??= b → if a is null/undefined, a = b; return new a
                    // Delegate to the evaluator via eval_node since proper
                    // short-circuit bytecode with assignment is non-trivial.
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                },
                .Not => {
                    // !x is parsed as BinaryExpression(left=false, op=Not, right=x)
                    self.expr(b.right);
                    self.c.op(.not_);
                },
                .BitNot => {
                    // ~x is parsed as BinaryExpression(left=0, op=BitNot, right=x)
                    self.expr(b.right);
                    self.c.op(.bit_not);
                },
                else => {
                    switch (b.operator) {
                        .And => {
                            // Short-circuit: if left is falsy, skip right (left stays on stack).
                            //   expr(left); jump_if_false END; pop; expr(right); END:
                            self.expr(b.left);
                            const end = self.c.jmp(.jump_if_false);
                            self.c.op(.pop);
                            self.expr(b.right);
                            self.c.ptch(end);
                        },
                        .Or => {
                            // Short-circuit: if left is truthy, skip right (left stays on stack).
                            //   expr(left); jump_if_true END; pop; expr(right); END:
                            self.expr(b.left);
                            const end = self.c.jmp(.jump_if_true);
                            self.c.op(.pop);
                            self.expr(b.right);
                            self.c.ptch(end);
                        },
                        .Nullish => {
                            // Short-circuit: if left is not nullish, skip right (left stays on stack).
                            //   expr(left); jump_if_not_nullish END; pop; expr(right); END:
                            self.expr(b.left);
                            const end = self.c.jmp(.jump_if_not_nullish);
                            self.c.op(.pop);
                            self.expr(b.right);
                            self.c.ptch(end);
                        },
                        else => {
                            self.expr(b.left);
                            self.expr(b.right);
                            switch (b.operator) {
                                .Plus => self.c.op(.add),
                                .Minus => self.c.op(.sub),
                                .Multiply => self.c.op(.mul),
                                .Divide => self.c.op(.div),
                                .Modulo => self.c.op(.mod_),
                                .Equal => self.c.op(.eq),
                                .StrictEqual => self.c.op(.strict_eq),
                                .NotEqual => self.c.op(.ne),
                                .StrictNotEqual => self.c.op(.strict_ne),
                                .LessThan => self.c.op(.lt),
                                .GreaterThan => self.c.op(.gt),
                                .LessThanOrEqual => self.c.op(.le),
                                .GreaterThanOrEqual => self.c.op(.ge),
                                .Not => self.c.op(.not_),
                                .BitAnd => self.c.op(.bit_and),
                                .BitOr => self.c.op(.bit_or),
                                .BitXor => self.c.op(.bit_xor),
                                .LeftShift => self.c.op(.left_shift),
                                .RightShift => self.c.op(.right_shift),
                                .UnsignedRightShift => self.c.op(.unsigned_right_shift),
                                .Exponent => self.c.op(.pow),
                                else => {},
                            }
                        },
                    }
                },
            },
            .Assignment => |a| {
                self.expr(a.value);
                self.c.op(.dup);
                self.c.op2w(.set_global, self.c.emitS(a.name));
            },
            .UpdateExpression => |u| {
                if (u.operand.* != .Identifier) {
                    // obj.x++ / arr[i]-- — computed target, resolved by the evaluator.
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                    return;
                }
                // For ++x / --x (prefix) leave the new value on the stack;
                // for x++ / x-- (postfix) leave the original (pre-update) value.
                //
                // Bytecode for prefix:
                //   get_global x; <const 1>; add|sub; dup; set_global x;
                // Bytecode for postfix:
                //   get_global x; get_global x; <const 1>; add|sub; dup;
                //   set_global x; pop;
                //
                // The constant 1.0 is a Float; the VM's BigInt-aware add/sub
                // coerces it to BigInt when the other operand is BigInt.
                const arith_op: Op = if (u.operator == .Increment) .add else .sub;
                if (u.prefix) {
                    self.c.op2w(.get_global, self.c.emitS(u.operand.Identifier.name));
                    self.c.emitC(.{ .float = 1.0 });
                    self.c.op(arith_op);
                    self.c.op(.dup);
                    self.c.op2w(.set_global, self.c.emitS(u.operand.Identifier.name));
                } else {
                    self.c.op2w(.get_global, self.c.emitS(u.operand.Identifier.name));
                    self.c.op2w(.get_global, self.c.emitS(u.operand.Identifier.name));
                    self.c.emitC(.{ .float = 1.0 });
                    self.c.op(arith_op);
                    self.c.op(.dup);
                    self.c.op2w(.set_global, self.c.emitS(u.operand.Identifier.name));
                    self.c.op(.pop);
                }
            },
            .ArrayLiteral => |a| {
                var has_spread = false;
                for (a.elements) |e| {
                    if (e.* == .SpreadExpression) {
                        has_spread = true;
                        break;
                    }
                }
                if (has_spread) {
                    // Defer evaluation to runtime via eval_node opcode
                    // (variables referenced by spread may not exist at compile time)
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                } else {
                    for (a.elements) |e| self.expr(e);
                    self.c.op2(.make_array, @intCast(a.elements.len));
                }
            },
            .ObjectLiteral => |o| {
                var has_spread = false;
                var has_computed = false;
                for (o.properties) |prop| {
                    if (prop.value.* == .SpreadExpression) {
                        has_spread = true;
                    }
                    if (prop.key_expr != null) {
                        has_computed = true;
                    }
                }
                if (has_spread or has_computed) {
                    // Defer evaluation to runtime via eval_node opcode.
                    // Computed property keys must be evaluated at runtime.
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                } else {
                    self.c.op(.make_object);
                    for (o.properties) |prop| {
                        self.c.op(.dup);
                        self.expr(prop.value);
                        self.c.op2w(.set_prop, self.c.emitS(prop.key));
                        self.c.op(.pop);
                    }
                }
            },
            .PropertySet => |p| {
                self.expr(p.object);
                self.expr(p.value);
                self.c.op2w(.set_prop, self.c.emitS(p.key));
            },
            .ArrayIndex => |ai| {
                self.expr(ai.array);
                self.expr(ai.index);
                self.c.op(.index_get);
            },
            .FunctionCall => |fc| {
                var has_spread = false;
                for (fc.arguments) |a| {
                    if (a.* == .SpreadExpression) {
                        has_spread = true;
                        break;
                    }
                }
                if (has_spread) {
                    // Defer to runtime via eval_node for spread args
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                } else {
                    for (fc.arguments) |a| self.expr(a);
                    self.c.op(.builtin);
                    self.c.w16(self.c.emitS(fc.name));
                    self.c.w8(@intCast(fc.arguments.len));
                }
            },
            .NewExpression => {
                self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
            },
            .MethodCall => |mc| {
                var has_spread = false;
                for (mc.arguments) |a| {
                    if (a.* == .SpreadExpression) {
                        has_spread = true;
                        break;
                    }
                }
                if (has_spread) {
                    // Defer to runtime via eval_node for spread args
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                } else {
                    self.expr(mc.object);
                    for (mc.arguments) |a| self.expr(a);
                    self.c.op(.method_call);
                    self.c.w16(self.c.emitS(mc.method));
                    self.c.w8(@intCast(mc.arguments.len));
                }
            },
            .MemberAccess => |m| {
                self.expr(m.object);
                self.c.op2w(.get_prop, self.c.emitS(m.property));
            },
            .ArrowFunction => {
                self.c.emitC(.{ .function = @ptrCast(n) });
            },
            .FunctionDeclaration => {
                const f = n.FunctionDeclaration;
                if (f.name.len > 0) {
                    self.env.setFunction(f.name, n) catch {};
                    self.compileFnBody(n);
                }
                self.c.emitC(.{ .function = @ptrCast(n) });
            },
            .Elision => {
                self.c.emitC(.{ .hole = {} });
            },
            .CommaExpression => |c| {
                // Evaluate each sub-expression, keep only the last result
                for (c.expressions, 0..) |e, i| {
                    self.expr(e);
                    if (i < c.expressions.len - 1) {
                        self.c.op(.pop);
                    }
                }
            },
            .ConditionalExpression => |c| {
                // Compile natively with conditional jumps (lazy evaluation)
                self.expr(c.condition);
                const alt_jmp = self.c.jmp(.jump_if_false);
                self.c.op(.pop); // pop condition value (truthy path)
                self.expr(c.consequent);
                const end_jmp = self.c.jmp(.jump);
                self.c.ptch(alt_jmp);
                self.c.op(.pop); // pop condition value (falsy path)
                self.expr(c.alternate);
                self.c.ptch(end_jmp);
            },
            .TypeOfExpression => |t| {
                if (t.operand.* == .Identifier) {
                    // typeof only tolerates an undeclared binding when the operand is a
                    // bare identifier; defer so the evaluator can resolve the reference
                    // without throwing (ES 13.5.3).
                    self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
                } else {
                    self.expr(t.operand);
                    self.c.op(.typeof_op);
                }
            },
            .DirectCall => {
                // Defer to evaluator - complex expressions need runtime evaluation
                self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
            },
            .VoidExpression => |v| {
                // Evaluate the operand for side effects, discard it, push undefined.
                self.expr(v.operand);
                self.c.op(.pop);
                self.c.op(.void_);
            },
            .ImportMetaExpression, .DeleteExpression => {
                self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
            },
            else => {
                // Unknown expression: let the AST evaluator handle it. Emitting
                // nothing here silently corrupted the stack (the statement-level
                // pop underflowed and aborted the process), so fall back instead
                // of guessing.
                self.c.op2w(.eval_node, self.c.addC(.{ .function = @ptrCast(n) }));
            },
        }
    }
};

pub const ExceptionHandlerEntry = struct {
    sp: usize,
    handler_ip: usize,
};

pub const VM = struct {
    c: *Chunk,
    ip: usize,
    sp: usize,
    stack: [4096]Value,
    env: *Environment,
    exception_handlers: std.ArrayList(ExceptionHandlerEntry),
    saved_error: ?Value = null,
    compiled_chunks: std.StringHashMap(*Chunk),

    pub fn init(env: *Environment) VM {
        return .{ .c = undefined, .ip = 0, .sp = 0, .stack = undefined, .env = env, .exception_handlers = std.ArrayList(ExceptionHandlerEntry).initCapacity(env.allocator, 8) catch unreachable, .compiled_chunks = std.StringHashMap(*Chunk).init(env.allocator) };
    }
    pub fn deinit(self: *VM) void {
        // Free compiled chunks
        var it = self.compiled_chunks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.env.allocator.destroy(entry.value_ptr.*);
        }
        self.compiled_chunks.deinit();
        self.exception_handlers.deinit(self.env.allocator);
    }

    fn propagateThrow(self: *VM, func_env: *Environment) !void {
        self.env.throw_hit = true;
        self.env.throw_value = func_env.throw_value;
        if (self.exception_handlers.items.len > 0) {
            const idx = self.exception_handlers.items.len - 1;
            const handler = self.exception_handlers.orderedRemove(idx);
            self.sp = handler.sp;
            self.push(func_env.throw_value);
            self.ip = handler.handler_ip;
        } else {
            return error.Thrown;
        }
    }

    /// Walk the prototype chain (max 16 levels deep to defend against
    /// accidental cycles) looking for property `name`. Returns the
    /// Value stored at the first link that has it, or null if neither
    /// the object nor any prototype in its chain defines it.
    fn lookupInPrototypeChain(_: *VM, start: *ast.ObjectValue, name: []const u8) ?Value {
        var o: ?*ast.ObjectValue = start;
        var depth: u8 = 0;
        while (o != null) : (depth += 1) {
            if (depth > 16) break;
            if (o.?.properties.get(name)) |v| return v;
            o = o.?.prototype;
        }
        return null;
    }

    /// Dispatch a method-stub on Object.prototype. The receiver for
    /// `toString` / `valueOf` / `hasOwnProperty` / etc. is `this_val`
    /// (the original receiver obj, not a prototype link). Used by
    /// method_call when chain walk finds a stub created by
    /// createObjectPrototype.
    fn dispatchObjectProtoMethod(stub_name: []const u8, this_val: Value, args: []Value, _: *Environment) anyerror!Value {
        if (std.mem.eql(u8, stub_name, "toString")) {
            return .{ .string = "[object Object]" };
        }
        if (std.mem.eql(u8, stub_name, "valueOf")) {
            return this_val;
        }
        if (std.mem.eql(u8, stub_name, "hasOwnProperty")) {
            if (this_val != .js_object) return .{ .boolean = false };
            const key = if (args.len > 0) switch (args[0]) {
                .string => |s| s,
                .integer => |i| blk: {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return .{ .boolean = false };
                    break :blk s;
                },
                else => return .{ .boolean = false },
            } else return .{ .boolean = false };
            return .{ .boolean = this_val.js_object.properties.contains(key) };
        }
        return .{ .void = {} };
    }

    /// Throw a TypeError via the VM's exception handling mechanism.
    /// Creates a TypeError object, sets env.throw_hit/throw_value, and either
    /// jumps to the nearest exception handler or returns error.Thrown.
    fn throwTypeError(self: *VM, method: []const u8) !void {
        const msg = std.fmt.allocPrint(self.env.allocator, "{s} is not a function", .{method}) catch {
            _ = throwError(self.env, "TypeError", .{ .string = "is not a function" });
            const err_val = self.env.throw_value;
            if (self.exception_handlers.items.len > 0) {
                const idx = self.exception_handlers.items.len - 1;
                const handler = self.exception_handlers.orderedRemove(idx);
                self.sp = handler.sp;
                self.push(err_val);
                self.ip = handler.handler_ip;
            } else {
                return error.Thrown;
            }
            return;
        };
        defer self.env.allocator.free(msg);
        _ = throwError(self.env, "TypeError", .{ .string = msg });
        const err_val = self.env.throw_value;
        if (self.exception_handlers.items.len > 0) {
            const idx = self.exception_handlers.items.len - 1;
            const handler = self.exception_handlers.orderedRemove(idx);
            self.sp = handler.sp;
            self.push(err_val);
            self.ip = handler.handler_ip;
        } else {
            return error.Thrown;
        }
    }
    fn bindRestParam(env: *Environment, rest_param: ?[]const u8, params: [][]const u8, args: std.ArrayList(Value)) !void {
        if (rest_param) |rp| {
            const num_params = params.len;
            const rest = ast.ArrayObject.init(env.allocator) catch return;
            try env.arrays.append(env.allocator, rest);
            var k: usize = num_params;
            while (k < args.items.len) : (k += 1) {
                try rest.elements.append(env.allocator, args.items[k]);
            }
            try env.setVar(rp, .{ .array = rest });
        }
    }

    fn callFuncNode(self: *VM, funcNode: *ast.Node, args: std.ArrayList(Value)) anyerror!void {
        if (funcNode.* == .GeneratorDeclaration) {
            const gen_obj = GeneratorObject.init(self.env.allocator, @ptrCast(funcNode), funcNode.GeneratorDeclaration.parameters) catch {
                self.push(.{ .void = {} });
                return;
            };
            self.push(.{ .generator = gen_obj });
            return;
        }
        // Shared: create function environment with parameters bound
        const params, const body, const fn_name, const rest_param = switch (funcNode.*) {
            .FunctionDeclaration => |f| .{ f.parameters, f.body, f.name, f.rest_param },
            .ArrowFunction => |f| .{ f.parameters, f.body, "", f.rest_param },
            else => return self.push(.{ .void = {} }),
        };

        const trace_name: []const u8 = if (fn_name.len > 0) fn_name else "<anonymous>";
        self.env.pushTraceFrame(trace_name, 0);
        defer self.env.popTraceFrame();

        // Try compiled bytecode first (only for named functions)
        if (fn_name.len > 0) {
            if (self.compiled_chunks.get(fn_name)) |chunk| {
                var func_env = try Environment.init(self.env.allocator, self.env);
                defer func_env.deinit();
                for (params, 0..) |p, j| {
                    if (j < args.items.len) try func_env.setVar(p, args.items[j]) else try func_env.setVar(p, .{ .void = {} });
                }
                try bindRestParam(&func_env, rest_param, params, args);
                var sub_vm = VM.init(&func_env);
                sub_vm.compiled_chunks = self.compiled_chunks; // inherit parent's chunks
                // NOTE: sub_vm.deinit() would free compiled_chunks entries (shared with parent),
                // causing double-free. Clean up only what sub_vm owns.
                sub_vm.interpret(chunk) catch |err| {
                    sub_vm.exception_handlers.deinit(self.env.allocator);
                    if (func_env.throw_hit) {
                        try self.propagateThrow(&func_env);
                        return;
                    }
                    return err;
                };
                sub_vm.exception_handlers.deinit(self.env.allocator);
                if (sub_vm.sp > 0) {
                    self.push(sub_vm.stack[sub_vm.sp - 1]);
                } else {
                    self.push(.{ .void = {} });
                }
                return;
            }
        }

        // Fall back to AST evaluator
        var func_env = try Environment.init(self.env.allocator, self.env);
        defer func_env.deinit();
        for (params, 0..) |p, j| {
            if (j < args.items.len) try func_env.setVar(p, args.items[j]) else try func_env.setVar(p, .{ .void = {} });
        }
        try bindRestParam(&func_env, rest_param, params, args);
        const r = try evaluate(body, &func_env);
        if (func_env.throw_hit) {
            try self.propagateThrow(&func_env);
            return;
        }
        self.push(r);
    }

    fn push(self: *VM, v: Value) void {
        if (self.sp >= self.stack.len) {
            std.debug.print("STACK OVERFLOW: sp={}, len={}, ip={}, last10 ops: const,add,pop...\n", .{ self.sp, self.stack.len, self.ip });
            @panic("stack overflow");
        }
        self.stack[self.sp] = v;
        self.sp += 1;
    }
    fn pop(self: *VM) Value {
        if (self.sp == 0) {
            std.debug.print("STACK UNDERFLOW: ip={}\n", .{self.ip});
            @panic("stack underflow");
        }
        self.sp -= 1;
        return self.stack[self.sp];
    }
    fn peek(self: *VM, d: usize) Value {
        return self.stack[self.sp - 1 - d];
    }
    fn readU16(self: *VM) u16 {
        const hi = self.c.code.items[self.ip];
        const lo = self.c.code.items[self.ip + 1];
        self.ip += 2;
        return (@as(u16, hi) << 8) | lo;
    }

    pub fn interpret(self: *VM, chunk: *Chunk) !void {
        self.c = chunk;
        self.ip = 0;
        self.sp = 0;
        while (true) {
            if (self.ip >= self.c.code.items.len) break;
            const op: Op = @fromBackingInt(@intCast(self.c.code.items[self.ip]));
            self.ip += 1;
            switch (op) {
                .constant => {
                    const ci = self.readU16();
                    self.push(self.c.consts.items[ci]);
                    if (self.sp >= 65000) std.debug.print("constant: sp={}, ip={}\n", .{ self.sp, self.ip });
                },
                .true_ => self.push(.{ .boolean = true }),
                .false_ => self.push(.{ .boolean = false }),
                .null_ => self.push(.{ .null = {} }),
                .void_ => self.push(.{ .void = {} }),
                .add, .sub, .mul, .div, .mod_ => {
                    const b = self.pop();
                    const a = self.pop();
                    // BigInt + BigInt / BigInt + Number — handle directly here.
                    if (a == .big_int or b == .big_int) {
                        const result = vmBigIntArith(self.env.allocator, &self.env.bigints, op, a, b);
                        self.push(result);
                        continue;
                    }
                    if (op == .add and (a == .string or b == .string)) {
                        var buf = std.ArrayList(u8).initCapacity(self.env.allocator, 64) catch unreachable;
                        defer buf.deinit(self.env.allocator);
                        valToStr(self.env.allocator, &buf, a);
                        valToStr(self.env.allocator, &buf, b);
                        const s = buf.toOwnedSlice(self.env.allocator) catch unreachable;
                        self.env.owned_strings.append(self.env.allocator, s) catch {};
                        self.push(.{ .string = s });
                    } else {
                        const av = toNumber(a);
                        const bv = toNumber(b);
                        self.push(.{ .float = switch (op) {
                            .add => av + bv,
                            .sub => av - bv,
                            .mul => av * bv,
                            .div => av / bv,
                            .mod_ => @mod(av, bv),
                            else => 0.0,
                        } });
                    }
                },
                .pow => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .big_int and b == .big_int) {
                        const base = a.big_int;
                        const exp_val = b.big_int.toI64() orelse {
                            self.push(.{ .float = std.math.inf(f64) });
                            continue;
                        };
                        if (exp_val < 0) {
                            self.push(.{ .float = 0.0 });
                            continue;
                        }
                        var result = try builtinsTypes.BigIntValue.init(self.env.allocator);
                        self.env.bigints.append(self.env.allocator, result) catch {};
                        result.value.pow(&base.value, @intCast(exp_val)) catch {
                            self.push(.{ .void = {} });
                            continue;
                        };
                        self.push(.{ .big_int = result });
                    } else {
                        const av = toNumber(a);
                        const bv = toNumber(b);
                        self.push(.{ .float = std.math.pow(f64, av, bv) });
                    }
                },
                .negate => {
                    const v = toNumber(self.pop());
                    self.push(.{ .float = -v });
                },
                .eq => self.push(.{ .boolean = valEq(self.env.allocator, &self.env.bigints, self.pop(), self.pop()) }),
                .ne => self.push(.{ .boolean = !valEq(self.env.allocator, &self.env.bigints, self.pop(), self.pop()) }),
                .strict_eq => self.push(.{ .boolean = valStrictEq(self.pop(), self.pop()) }),
                .strict_ne => self.push(.{ .boolean = !valStrictEq(self.pop(), self.pop()) }),
                .lt => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        self.push(.{ .boolean = std.mem.order(u8, a.string, b.string) == .lt });
                    } else if (a == .big_int and b == .big_int) {
                        self.push(.{ .boolean = a.big_int.compare(b.big_int) == .lt });
                    } else {
                        const av = toNumber(a);
                        const bv = toNumber(b);
                        self.push(.{ .boolean = av < bv });
                    }
                },
                .gt => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        self.push(.{ .boolean = std.mem.order(u8, a.string, b.string) == .gt });
                    } else if (a == .big_int and b == .big_int) {
                        self.push(.{ .boolean = a.big_int.compare(b.big_int) == .gt });
                    } else {
                        const av = toNumber(a);
                        const bv = toNumber(b);
                        self.push(.{ .boolean = av > bv });
                    }
                },
                .le => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        const ord = std.mem.order(u8, a.string, b.string);
                        self.push(.{ .boolean = ord == .lt or ord == .eq });
                    } else if (a == .big_int and b == .big_int) {
                        const cmp = a.big_int.compare(b.big_int);
                        self.push(.{ .boolean = cmp == .lt or cmp == .eq });
                    } else {
                        self.push(.{ .boolean = toNumber(a) <= toNumber(b) });
                    }
                },
                .ge => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        const ord = std.mem.order(u8, a.string, b.string);
                        self.push(.{ .boolean = ord == .gt or ord == .eq });
                    } else if (a == .big_int and b == .big_int) {
                        const cmp = a.big_int.compare(b.big_int);
                        self.push(.{ .boolean = cmp == .gt or cmp == .eq });
                    } else {
                        self.push(.{ .boolean = toNumber(a) >= toNumber(b) });
                    }
                },
                .not_ => self.push(.{ .boolean = !truthy(self.pop()) }),
                .and_ => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(if (truthy(a)) b else a);
                },
                .or_ => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(if (truthy(a)) a else b);
                },
                .nullish => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(if (a == .null or a == .void) b else a);
                },
                .bit_and => {
                    const b = toInt(self.pop());
                    const a = toInt(self.pop());
                    self.push(.{ .integer = a & b });
                },
                .bit_or => {
                    const b = toInt(self.pop());
                    const a = toInt(self.pop());
                    self.push(.{ .integer = a | b });
                },
                .bit_xor => {
                    const b = toInt(self.pop());
                    const a = toInt(self.pop());
                    self.push(.{ .integer = a ^ b });
                },
                .bit_not => {
                    const a = toInt(self.pop());
                    self.push(.{ .integer = ~a });
                },
                .left_shift => {
                    const b = toInt(self.pop());
                    const a = toInt(self.pop());
                    self.push(.{ .integer = a << @intCast(b) });
                },
                .right_shift => {
                    const b = toInt(self.pop());
                    const a = toInt(self.pop());
                    self.push(.{ .integer = a >> @intCast(b) });
                },
                .unsigned_right_shift => {
                    const b = toInt(self.pop());
                    const a = toInt(self.pop());
                    self.push(.{ .integer = @as(i64, @as(u32, @bitCast(@as(i32, @truncate(a)))) >> @as(u5, @intCast(b & 0x1f))) });
                },
                .pop => _ = self.pop(),
                .dup => {
                    const v = self.peek(0);
                    self.push(v);
                },
                .def_global => {
                    const ci = self.readU16();
                    const n = self.c.consts.items[ci].string;
                    const v = self.peek(0);
                    self.sp -= 1;
                    self.env.setVar(n, v) catch {};
                },
                .get_global => {
                    const ci = self.readU16();
                    const n = self.c.consts.items[ci].string;
                    if (self.env.get(n)) |v| {
                        self.push(v);
                    } else if (self.env.getFunction(n)) |funcNode| {
                        self.push(.{ .function = @ptrCast(funcNode) });
                    } else if (self.env.getBuiltinObject(n)) |obj| {
                        self.push(.{ .object = @ptrCast(obj) });
                    } else if (self.env.getBuiltin(n)) |_| {
                        self.push(.{ .void = {} });
                    } else {
                        return error.UndefinedVariable;
                    }
                },
                .set_global => {
                    const ci = self.readU16();
                    const n = self.c.consts.items[ci].string;
                    const v = self.peek(0);
                    self.sp -= 1;
                    self.env.setInScope(n, v) catch {};
                },
                .try_get_global => {
                    const ci = self.readU16();
                    const n = self.c.consts.items[ci].string;
                    if (self.env.get(n)) |v| {
                        self.push(v);
                    } else {
                        self.push(.{ .void = {} });
                    }
                },
                .get_local => {
                    const slot = self.c.code.items[self.ip];
                    self.ip += 1;
                    self.push(self.stack[slot]);
                },
                .set_local => {
                    const slot = self.c.code.items[self.ip];
                    self.ip += 1;
                    self.stack[slot] = self.peek(0);
                },
                .jump => {
                    const hi = self.c.code.items[self.ip];
                    const lo = self.c.code.items[self.ip + 1]; // parentheses required: `+` binds tighter than `|` in Zig
                    self.ip += 2 + ((@as(usize, hi) << 8) | lo);
                },
                .jump_if_false => {
                    const hi = self.c.code.items[self.ip];
                    const lo = self.c.code.items[self.ip + 1];
                    self.ip += 2;
                    if (!truthy(self.peek(0))) self.ip += (@as(usize, hi) << 8) | lo;
                },
                .jump_if_true => {
                    const hi = self.c.code.items[self.ip];
                    const lo = self.c.code.items[self.ip + 1];
                    self.ip += 2;
                    if (truthy(self.peek(0))) self.ip += (@as(usize, hi) << 8) | lo;
                },
                .jump_if_not_nullish => {
                    const hi = self.c.code.items[self.ip];
                    const lo = self.c.code.items[self.ip + 1];
                    self.ip += 2;
                    const v = self.peek(0);
                    if (!(v == .null or v == .void)) self.ip += (@as(usize, hi) << 8) | lo;
                },
                .loop => {
                    const hi = self.c.code.items[self.ip];
                    const lo = self.c.code.items[self.ip + 1];
                    self.ip += 2;
                    self.ip -= (@as(usize, hi) << 8) | lo;
                },
                .make_array => {
                    const cnt = self.c.code.items[self.ip];
                    self.ip += 1;
                    const arr = ast.ArrayObject.init(self.env.allocator) catch unreachable;
                    var i: usize = 0;
                    while (i < cnt) : (i += 1) {
                        arr.elements.append(arr.allocator, self.stack[self.sp - cnt + i]) catch {};
                    }
                    self.sp -= cnt;
                    self.env.arrays.append(self.env.allocator, arr) catch {};
                    self.push(.{ .array = arr });
                },
                .index_get => {
                    const idx = self.pop();
                    const arr = self.pop();
                    if (arr == .array) {
                        if (idx == .symbol) {
                            const prop_name = try std.fmt.allocPrint(self.env.allocator, "@@{s}", .{idx.symbol.description});
                            defer self.env.allocator.free(prop_name);
                            if (arr.array.extras) |extras| {
                                if (extras.properties.get(prop_name)) |v| {
                                    self.push(v);
                                } else {
                                    self.push(.{ .void = {} });
                                }
                            } else if (std.mem.eql(u8, prop_name, "@@iterator")) {
                                const iter = try ast.ArrayIterator.initValues(self.env.allocator, arr.array);
                                try self.env.iterators.append(self.env.allocator, iter);
                                self.push(.{ .iterator = iter });
                            } else {
                                self.push(.{ .void = {} });
                            }
                        } else if (idx == .big_int) {
                            // BigInt index: convert to i64 with precision check.
                            // - Out-of-range / non-integer / negative -> undefined (void).
                            // Per ES2020 ToIndex / ToIntegerOrInfinity semantics.
                            const big = idx.big_int;
                            if (big.eqlZero()) {
                                self.push(arrayGet(arr.array, 0));
                            } else if (big.toI64()) |i| {
                                if (i < 0) {
                                    self.push(.{ .void = {} });
                                } else {
                                    self.push(arrayGet(arr.array, @intCast(i)));
                                }
                            } else {
                                self.push(.{ .void = {} });
                            }
                        } else {
                            // Integer/float index with negative check.
                            if (idx == .integer and idx.integer < 0) {
                                self.push(.{ .void = {} });
                            } else if (idx == .float and (idx.float < 0.0 or std.math.isNan(idx.float))) {
                                self.push(.{ .void = {} });
                            } else {
                                const i: usize = switch (idx) {
                                    .integer => |n| @intCast(n),
                                    .float => |n| @intFromFloat(n),
                                    else => return error.InvalidIndex,
                                };
                                self.push(arrayGet(arr.array, i));
                            }
                        }
                    } else if (arr == .js_object) {
                        if (idx == .symbol) {
                            const prop_name = try std.fmt.allocPrint(self.env.allocator, "@@{s}", .{idx.symbol.description});
                            defer self.env.allocator.free(prop_name);
                            self.push(arr.js_object.properties.get(prop_name) orelse .{ .void = {} });
                        } else {
                            const key = switch (idx) {
                                .string => |s| s,
                                .integer => |i| blk: {
                                    var buf: [32]u8 = undefined;
                                    const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                                    const owned = try self.env.allocator.dupe(u8, s);
                                    self.env.owned_strings.append(self.env.allocator, owned) catch {};
                                    break :blk owned;
                                },
                                .float => |f| blk: {
                                    var buf: [64]u8 = undefined;
                                    const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
                                    const owned = try self.env.allocator.dupe(u8, s);
                                    self.env.owned_strings.append(self.env.allocator, owned) catch {};
                                    break :blk owned;
                                },
                                else => return error.InvalidIndex,
                            };
                            self.push(arr.js_object.properties.get(key) orelse .{ .void = {} });
                        }
                    } else {
                        return error.NotAnArray;
                    }
                },
                .get_prop => {
                    const ci = self.readU16();
                    const p = self.c.consts.items[ci].string;
                    const obj = self.pop();
                    if (obj == .array and std.mem.eql(u8, p, "length")) {
                        self.push(.{ .integer = @intCast(obj.array.elements.items.len) });
                    } else if (obj == .string and std.mem.eql(u8, p, "length")) {
                        self.push(.{ .integer = @intCast(obj.string.len) });
                    } else if (obj == .js_object) {
                        const type_tag = obj.js_object.properties.get("@@type");
                        if (type_tag != null and type_tag.? == .string) {
                            if (std.mem.eql(u8, type_tag.?.string, "Set") and std.mem.eql(u8, p, "size")) {
                                if (obj.js_object.properties.get("values")) |vals| {
                                    if (vals == .array) {
                                        self.push(.{ .integer = @intCast(vals.array.elements.items.len) });
                                    } else {
                                        self.push(.{ .integer = 0 });
                                    }
                                } else {
                                    self.push(.{ .integer = 0 });
                                }
                            } else if (std.mem.eql(u8, type_tag.?.string, "Map") and std.mem.eql(u8, p, "size")) {
                                if (obj.js_object.properties.get("entries")) |ents| {
                                    if (ents == .array) {
                                        self.push(.{ .integer = @intCast(ents.array.elements.items.len) });
                                    } else {
                                        self.push(.{ .integer = 0 });
                                    }
                                } else {
                                    self.push(.{ .integer = 0 });
                                }
                            } else if (obj.js_object.properties.get(p)) |v| {
                                self.push(v);
                            } else {
                                // @@type-bearing native: walk prototype chain for general members.
                                self.push(self.lookupInPrototypeChain(obj.js_object, p) orelse .{ .void = {} });
                            }
                        } else if (obj.js_object.properties.get(p)) |v| {
                            self.push(v);
                        } else {
                            // Plain object: walk prototype chain for inherited members.
                            self.push(self.lookupInPrototypeChain(obj.js_object, p) orelse .{ .void = {} });
                        }
                    } else if (obj == .object) {
                        const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(obj.object));
                        if (bObjPtr.getProperty(p)) |prop_val| {
                            self.push(prop_val);
                        } else {
                            self.push(.{ .void = {} });
                        }
                    } else {
                        self.push(.{ .void = {} });
                    }
                },
                .make_object => {
                    // Attach Object.prototype as the chain link so
                    // `obj.toString` / `obj.hasOwnProperty(...)` resolve
                    // via prototype-chain walk in method_call / get_prop.
                    const proto = self.env.object_prototype;
                    const obj = if (proto) |p|
                        ast.ObjectValue.initWithProto(self.env.allocator, p) catch unreachable
                    else
                        ast.ObjectValue.init(self.env.allocator) catch unreachable;
                    self.env.objects.append(self.env.allocator, obj) catch {};
                    self.push(.{ .js_object = obj });
                },
                .set_prop => {
                    const ci = self.readU16();
                    const p = self.c.consts.items[ci].string;
                    const val = self.pop();
                    const obj = self.pop();
                    if (obj == .js_object) {
                        obj.js_object.properties.put(p, val) catch {};
                        self.push(val);
                    } else {
                        self.push(.{ .void = {} });
                    }
                },
                .builtin => {
                    const ci = self.readU16();
                    const ac = self.c.code.items[self.ip];
                    self.ip += 1;
                    const name = self.c.consts.items[ci].string;
                    var args = std.ArrayList(Value).initCapacity(self.env.allocator, ac) catch unreachable;
                    defer args.deinit(self.env.allocator);
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        args.insert(self.env.allocator, 0, self.pop()) catch {};
                    }
                    if (self.env.getBuiltin(name)) |fnPtr| {
                        const r = fnPtr(args.items, self.env);
                        switch (r) {
                            .value => |v| self.push(v),
                            .void => self.push(.{ .void = {} }),
                        }
                    } else if (self.env.getFunction(name)) |funcNode| {
                        try self.callFuncNode(funcNode, args);
                    } else if (self.env.get(name)) |val| {
                        // Support first-class functions: var f = add; f(1, 2)
                        if (val == .function) {
                            try self.callFuncNode(@as(*ast.Node, @ptrCast(@alignCast(val.function))), args);
                        } else {
                            return error.UndefinedFunction;
                        }
                    } else {
                        return error.UndefinedFunction;
                    }
                },
                .method_call => {
                    const ci = self.readU16();
                    const ac = self.c.code.items[self.ip];
                    self.ip += 1;
                    const m = self.c.consts.items[ci].string;
                    if (ac > 0) {
                        var args = std.ArrayList(Value).initCapacity(self.env.allocator, ac) catch unreachable;
                        defer args.deinit(self.env.allocator);
                        var i: usize = 0;
                        while (i < ac) : (i += 1) {
                            args.insert(self.env.allocator, 0, self.pop()) catch {};
                        }
                        const obj = self.pop();
                        if (obj == .array) {
                            args.insert(self.env.allocator, 0, obj) catch {};
                            const bObj = self.env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                            const md = bObj.getMethod(m) orelse {
                                // arr.length() etc. — property, not a method
                                return self.throwTypeError(m);
                            };
                            const r = md(args.items, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .object) {
                            const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(obj.object));
                            const md = bObjPtr.getMethod(m) orelse {
                                if (bObjPtr.getProperty(m)) |prop_val| {
                                    if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            const r = md(args.items, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .iterator) {
                            const v = obj.iterator.next(self.env.allocator, &self.env.arrays, &self.env.objects);
                            self.push(v);
                        } else if (obj == .js_object) {
                            const type_tag = obj.js_object.properties.get("@@type");
                            if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Set")) {
                                args.insert(self.env.allocator, 0, obj) catch {};
                                const sObj = self.env.getBuiltinObject("Set") orelse {
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const md = sObj.getMethod(m) orelse {
                                    if (obj.js_object.properties.get(m)) |prop_val| {
                                        if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                    }
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const r = md(args.items, self.env);
                                switch (r) {
                                    .value => |v| self.push(v),
                                    .void => self.push(.{ .void = {} }),
                                }
                            } else if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Map")) {
                                args.insert(self.env.allocator, 0, obj) catch {};
                                const mObj = self.env.getBuiltinObject("Map") orelse {
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const md = mObj.getMethod(m) orelse {
                                    if (obj.js_object.properties.get(m)) |prop_val| {
                                        if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                    }
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const r = md(args.items, self.env);
                                switch (r) {
                                    .value => |v| self.push(v),
                                    .void => self.push(.{ .void = {} }),
                                }
                            } else if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Boolean")) {
                                args.insert(self.env.allocator, 0, obj) catch {};
                                const bObj = self.env.getBuiltinObject("Boolean") orelse {
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const md = bObj.getMethod(m) orelse {
                                    if (obj.js_object.properties.get(m)) |prop_val| {
                                        if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                    }
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const r = md(args.items, self.env);
                                switch (r) {
                                    .value => |v| self.push(v),
                                    .void => self.push(.{ .void = {} }),
                                }
                            } else {
                                // First try prototype chain walk for own/ inherited properties.
                                const found = blk: {
                                    var o: ?*ast.ObjectValue = obj.js_object;
                                    var depth: u8 = 0;
                                    while (o != null) : (depth += 1) {
                                        if (depth > 16) break; // cycle guard
                                        if (o.?.properties.get(m)) |prop_val| break :blk prop_val;
                                        o = o.?.prototype;
                                    }
                                    break :blk null;
                                };
                                if (found) |prop_val| {
                                    // Object.prototype stub dispatch (toString / valueOf /
                                    // hasOwnProperty / etc.) handled natively.
                                    if (objectPrototypeMod.isObjectPrototypeMethodStub(prop_val)) |stub_name| {
                                        const r = try dispatchObjectProtoMethod(stub_name, obj, args.items, self.env);
                                        self.push(r);
                                    } else if (runtime.isCallable(prop_val)) {
                                        const r = try callFunctionValue(prop_val, args.items, self.env, obj);
                                        self.push(r);
                                    } else {
                                        return self.throwTypeError(m);
                                    }
                                } else if (type_tag != null and type_tag.? == .string) {
                                    // Prototype chain walk failed. Try generic @@type dispatch:
                                    // look up a builtin object by the type name and dispatch to its methods.
                                    // Supports Date, Error, WeakRef, DisposableStack, etc.
                                    const type_name = type_tag.?.string;
                                    if (self.env.getBuiltinObject(type_name)) |bObj| {
                                        args.insert(self.env.allocator, 0, obj) catch {};
                                        const md = bObj.getMethod(m) orelse {
                                            if (obj.js_object.properties.get(m)) |prop_val| {
                                                if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                            }
                                            self.push(.{ .void = {} });
                                            continue;
                                        };
                                        const r = md(args.items, self.env);
                                        switch (r) {
                                            .value => |v| self.push(v),
                                            .void => self.push(.{ .void = {} }),
                                        }
                                    } else {
                                        return self.throwTypeError(m);
                                    }
                                } else {
                                    return self.throwTypeError(m);
                                }
                            }
                        } else if (obj == .generator) {
                            if (std.mem.eql(u8, m, "next")) {
                                const r: Value = evaluateGeneratorNext(obj.generator, self.env) catch .{ .void = {} };
                                self.push(r);
                            } else if (std.mem.eql(u8, m, "return")) {
                                var r: Value = .{ .void = {} };
                                // args already on stack before obj
                                const r_val = evaluateGeneratorReturn(obj.generator, self.env, args.items) catch @as(Value, .{ .void = {} });
                                r = r_val;
                                self.push(r);
                            } else if (std.mem.eql(u8, m, "throw")) {
                                const r_val = evaluateGeneratorThrow(obj.generator, self.env, args.items) catch @as(Value, .{ .void = {} });
                                self.push(r_val);
                            } else {
                                self.push(.{ .void = {} });
                            }
                        } else if (obj == .string) {
                            args.insert(self.env.allocator, 0, obj) catch {};
                            const bObj = self.env.getBuiltinObject("String") orelse return error.UndefinedObject;
                            const md = bObj.getMethod(m) orelse {
                                return self.throwTypeError(m);
                            };
                            const r = md(args.items, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .boolean) {
                            args.insert(self.env.allocator, 0, obj) catch {};
                            const bObj = self.env.getBuiltinObject("Boolean") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = bObj.getMethod(m) orelse {
                                if (obj == .boolean) {
                                    if (!runtime.isCallable(obj)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            const r = md(args.items, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .integer or obj == .float) {
                            args.insert(self.env.allocator, 0, obj) catch {};
                            const nObj = self.env.getBuiltinObject("Number") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = nObj.getMethod(m) orelse {
                                if (obj == .integer or obj == .float) {
                                    if (!runtime.isCallable(obj)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            const r = md(args.items, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .big_int) {
                            args.insert(self.env.allocator, 0, obj) catch {};
                            const bObj = self.env.getBuiltinObject("BigInt") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = bObj.getMethod(m) orelse {
                                if (obj == .big_int) {
                                    if (!runtime.isCallable(obj)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            const r = md(args.items, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else {
                            self.push(.{ .void = {} });
                        }
                    } else {
                        const obj = self.pop();
                        if (obj == .generator) {
                            if (std.mem.eql(u8, m, "next")) {
                                const r: Value = evaluateGeneratorNext(obj.generator, self.env) catch .{ .void = {} };
                                self.push(r);
                            } else if (std.mem.eql(u8, m, "return")) {
                                const r_val = evaluateGeneratorReturn(obj.generator, self.env, &.{}) catch @as(Value, .{ .void = {} });
                                self.push(r_val);
                            } else if (std.mem.eql(u8, m, "throw")) {
                                const r_val = evaluateGeneratorThrow(obj.generator, self.env, &.{}) catch @as(Value, .{ .void = {} });
                                self.push(r_val);
                            } else {
                                self.push(.{ .void = {} });
                            }
                        } else if (obj == .object) {
                            const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @ptrCast(@alignCast(obj.object));
                            const md = bObjPtr.getMethod(m) orelse {
                                if (bObjPtr.getProperty(m)) |prop_val| {
                                    if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            const r = md(&.{}, self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .array) {
                            const bObj = self.env.getBuiltinObject("Array") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = bObj.getMethod(m) orelse {
                                if (std.mem.eql(u8, m, "length")) return self.throwTypeError(m);
                                self.push(.{ .void = {} });
                                break;
                            };
                            var tmp = [_]Value{obj};
                            const r = md(tmp[0..], self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .iterator) {
                            const v = obj.iterator.next(self.env.allocator, &self.env.arrays, &self.env.objects);
                            self.push(v);
                        } else if (obj == .js_object) {
                            const type_tag = obj.js_object.properties.get("@@type");
                            if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Set")) {
                                const sObj = self.env.getBuiltinObject("Set") orelse {
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const md = sObj.getMethod(m) orelse {
                                    if (std.mem.eql(u8, m, "size")) return self.throwTypeError(m);
                                    if (obj.js_object.properties.get(m)) |prop_val| {
                                        if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                    }
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                var tmp = [_]Value{obj};
                                const r = md(tmp[0..], self.env);
                                switch (r) {
                                    .value => |v| self.push(v),
                                    .void => self.push(.{ .void = {} }),
                                }
                            } else if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Map")) {
                                const mObj = self.env.getBuiltinObject("Map") orelse {
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const md = mObj.getMethod(m) orelse {
                                    if (std.mem.eql(u8, m, "size")) return self.throwTypeError(m);
                                    if (obj.js_object.properties.get(m)) |prop_val| {
                                        if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                    }
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                var tmp = [_]Value{obj};
                                const r = md(tmp[0..], self.env);
                                switch (r) {
                                    .value => |v| self.push(v),
                                    .void => self.push(.{ .void = {} }),
                                }
                            } else if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "Boolean")) {
                                const bObj = self.env.getBuiltinObject("Boolean") orelse {
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                const md = bObj.getMethod(m) orelse {
                                    if (obj.js_object.properties.get(m)) |prop_val| {
                                        if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                    }
                                    self.push(.{ .void = {} });
                                    break;
                                };
                                var tmp = [_]Value{obj};
                                const r = md(tmp[0..], self.env);
                                switch (r) {
                                    .value => |v| self.push(v),
                                    .void => self.push(.{ .void = {} }),
                                }
                            } else {
                                // Generic @@type dispatch: if the js_object has an @@type
                                // property matching a builtin object, dispatch to its methods.
                                const found = blk: {
                                    var o: ?*ast.ObjectValue = obj.js_object;
                                    var depth: u8 = 0;
                                    while (o != null) : (depth += 1) {
                                        if (depth > 16) break; // cycle guard
                                        if (o.?.properties.get(m)) |prop_val| break :blk prop_val;
                                        o = o.?.prototype;
                                    }
                                    break :blk null;
                                };
                                if (found) |prop_val| {
                                    if (objectPrototypeMod.isObjectPrototypeMethodStub(prop_val)) |stub_name| {
                                        var empty_args = [_]Value{};
                                        const r = try dispatchObjectProtoMethod(stub_name, obj, empty_args[0..], self.env);
                                        self.push(r);
                                    } else if (runtime.isCallable(prop_val)) {
                                        var tmp = [_]Value{obj};
                                        const r = try callFunctionValue(prop_val, tmp[0..], self.env, obj);
                                        self.push(r);
                                    } else {
                                        return self.throwTypeError(m);
                                    }
                                } else if (type_tag != null and type_tag.? == .string) {
                                    // Prototype chain walk failed. Try generic @@type dispatch:
                                    // look up a builtin object by the type name and dispatch to its methods.
                                    const type_name = type_tag.?.string;
                                    if (self.env.getBuiltinObject(type_name)) |bObj| {
                                        var tmp = [_]Value{obj};
                                        const md = bObj.getMethod(m) orelse {
                                            if (obj.js_object.properties.get(m)) |prop_val| {
                                                if (!runtime.isCallable(prop_val)) return self.throwTypeError(m);
                                            }
                                            self.push(.{ .void = {} });
                                            continue;
                                        };
                                        const r = md(tmp[0..], self.env);
                                        switch (r) {
                                            .value => |v| self.push(v),
                                            .void => self.push(.{ .void = {} }),
                                        }
                                    } else {
                                        return self.throwTypeError(m);
                                    }
                                } else {
                                    return self.throwTypeError(m);
                                }
                            }
                        } else if (obj == .string) {
                            const bObj = self.env.getBuiltinObject("String") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = bObj.getMethod(m) orelse {
                                if (std.mem.eql(u8, m, "length")) return self.throwTypeError(m);
                                self.push(.{ .void = {} });
                                break;
                            };
                            var tmp = [_]Value{obj};
                            const r = md(tmp[0..], self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .boolean) {
                            const bObj = self.env.getBuiltinObject("Boolean") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = bObj.getMethod(m) orelse {
                                if (obj == .boolean) {
                                    if (!runtime.isCallable(obj)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            var tmp = [_]Value{obj};
                            const r = md(tmp[0..], self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .integer or obj == .float) {
                            const nObj = self.env.getBuiltinObject("Number") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = nObj.getMethod(m) orelse {
                                if (obj == .integer or obj == .float) {
                                    if (!runtime.isCallable(obj)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            var tmp = [_]Value{obj};
                            const r = md(tmp[0..], self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else if (obj == .big_int) {
                            const bObj = self.env.getBuiltinObject("BigInt") orelse {
                                self.push(.{ .void = {} });
                                break;
                            };
                            const md = bObj.getMethod(m) orelse {
                                if (obj == .big_int) {
                                    if (!runtime.isCallable(obj)) return self.throwTypeError(m);
                                }
                                self.push(.{ .void = {} });
                                break;
                            };
                            var tmp = [_]Value{obj};
                            const r = md(tmp[0..], self.env);
                            switch (r) {
                                .value => |v| self.push(v),
                                .void => self.push(.{ .void = {} }),
                            }
                        } else {
                            self.push(.{ .void = {} });
                        }
                    }
                },
                .eval_node => {
                    const ci = self.readU16();
                    const node = self.c.consts.items[ci].function;
                    const val = evaluate(@as(*ast.Node, @ptrCast(@alignCast(node))), self.env) catch {
                        if (self.env.throw_hit) {
                            return error.Thrown;
                        }
                        self.push(.{ .void = {} });
                        break;
                    };
                    self.push(val);
                },
                .ret => return,
                .throw_stmt => {
                    const val = self.pop();
                    if (self.exception_handlers.items.len > 0) {
                        const idx = self.exception_handlers.items.len - 1;
                        const handler = self.exception_handlers.orderedRemove(idx);
                        self.sp = handler.sp;
                        self.push(val);
                        self.ip = handler.handler_ip;
                    } else {
                        self.env.throw_hit = true;
                        self.env.throw_value = val;
                        return error.Thrown;
                    }
                },
                .set_handler => {
                    const offset = self.readU16();
                    const handler_ip = self.ip + offset;
                    try self.exception_handlers.append(self.env.allocator, .{ .sp = self.sp, .handler_ip = handler_ip });
                },
                .clear_handler => {
                    if (self.exception_handlers.items.len > 0) {
                        _ = self.exception_handlers.orderedRemove(self.exception_handlers.items.len - 1);
                    }
                },
                .save_error => {
                    self.saved_error = self.pop();
                },
                .typeof_op => {
                    const val = self.pop();
                    const type_str: []const u8 = switch (val) {
                        .integer, .float => "number",
                        .big_int => "bigint",
                        .string => "string",
                        .boolean => "boolean",
                        .void => "undefined",
                        .null => "object",
                        .array, .js_object => "object",
                        .function, .closure, .generator => "function",
                        .object => "object",
                        .symbol => "symbol",
                        .iterator => "object",
                        .hole => "undefined",
                        .array_iterator => "object",
                        .regexp => "object",
                    };
                    self.push(.{ .string = type_str });
                },
                .throw_rethrow => {
                    if (self.saved_error) |err| {
                        self.saved_error = null;
                        if (self.exception_handlers.items.len > 0) {
                            const idx = self.exception_handlers.items.len - 1;
                            const handler = self.exception_handlers.orderedRemove(idx);
                            self.sp = handler.sp;
                            self.push(err);
                            self.ip = handler.handler_ip;
                        } else {
                            self.env.throw_hit = true;
                            self.env.throw_value = err;
                            return error.Thrown;
                        }
                    }
                },
                .call => {
                    const ac = self.c.code.items[self.ip];
                    self.ip += 1;
                    _ = ac;
                    _ = self.pop(); // placeholder2 — function calls handled via builtin fallback
                },
                .get_iterator => {
                    const val = self.pop();
                    switch (val) {
                        .array => |arr| {
                            const iter = try ast.ArrayIterator.initValues(self.env.allocator, arr);
                            try self.env.iterators.append(self.env.allocator, iter);
                            self.push(.{ .iterator = iter });
                        },
                        .iterator => |iter| {
                            self.push(.{ .iterator = iter });
                        },
                        .generator => |gen| {
                            self.push(.{ .generator = gen });
                        },
                        .string => |s| {
                            // For strings, create a simple index-based iterator using a js_object with state
                            const obj = ast.ObjectValue.init(self.env.allocator) catch unreachable;
                            self.env.objects.append(self.env.allocator, obj) catch {};
                            obj.properties.put("@@type", .{ .string = "StringIterator" }) catch {};
                            obj.properties.put("str", val) catch {};
                            obj.properties.put("index", .{ .integer = 0 }) catch {};
                            obj.properties.put("length", .{ .integer = @intCast(s.len) }) catch {};
                            self.push(.{ .js_object = obj });
                        },
                        else => {
                            // For other types, try to create an array iterator if it has .array property
                            self.push(.{ .void = {} });
                        },
                    }
                },
                .iterator_next => {
                    // Pops iterator from stack, gets next value, pushes value + done(bool)
                    const iter_val = self.pop();
                    switch (iter_val) {
                        .iterator => |iter| {
                            const result = iter.next(self.env.allocator, &self.env.arrays, &self.env.objects);
                            // result is a js_object with {value, done} properties
                            if (result == .js_object) {
                                const done_val: Value = result.js_object.properties.get("done") orelse .{ .boolean = true };
                                const value_val: Value = result.js_object.properties.get("value") orelse .{ .void = {} };
                                self.push(value_val);
                                self.push(done_val);
                            } else {
                                self.push(.{ .void = {} });
                                self.push(.{ .boolean = true });
                            }
                        },
                        .generator => |gen| {
                            const result: Value = evaluateGeneratorNext(gen, self.env) catch .{ .void = {} };
                            // evaluateGeneratorNext returns:
                            //  - raw value on yield (e.g. .integer = 1)
                            //  - .js_object{value, done} when generator is exhausted or returns
                            //  - .void on error
                            if (result == .js_object) {
                                // Done or returned — extract value and done from the wrapper
                                const done_val: Value = result.js_object.properties.get("done") orelse .{ .boolean = true };
                                const value_val: Value = result.js_object.properties.get("value") orelse .{ .void = {} };
                                self.push(value_val);
                                self.push(done_val);
                            } else if (result == .void) {
                                self.push(.{ .void = {} });
                                self.push(.{ .boolean = true });
                            } else {
                                // Yielded value — not done
                                self.push(result);
                                self.push(.{ .boolean = false });
                            }
                        },
                        .js_object => |obj| {
                            // StringIterator: custom iterator for strings
                            const type_tag = obj.properties.get("@@type");
                            if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "StringIterator")) {
                                const idx_val: Value = obj.properties.get("index") orelse .{ .integer = 0 };
                                const str_val: Value = obj.properties.get("str") orelse .{ .string = "" };
                                const idx: i64 = switch (idx_val) {
                                    .integer => |i| i,
                                    else => 0,
                                };
                                const s: []const u8 = switch (str_val) {
                                    .string => |s| s,
                                    else => "",
                                };
                                if (idx < 0 or @as(usize, @intCast(idx)) >= s.len) {
                                    self.push(.{ .void = {} });
                                    self.push(.{ .boolean = true });
                                } else {
                                    // Get the character at this byte position
                                    const byte_idx: usize = @intCast(idx);
                                    const char_len = std.unicode.utf8ByteSequenceLength(s[byte_idx]) catch 1;
                                    const end = @min(byte_idx + char_len, s.len);
                                    const char_str = try self.env.allocator.dupe(u8, s[byte_idx..end]);
                                    self.env.owned_strings.append(self.env.allocator, char_str) catch {};
                                    obj.properties.put("index", .{ .integer = idx + @as(i64, @intCast(char_len)) }) catch {};
                                    self.push(.{ .string = char_str });
                                    self.push(.{ .boolean = false });
                                }
                            } else if (type_tag != null and type_tag.? == .string and std.mem.eql(u8, type_tag.?.string, "ForInIterator")) {
                                const idx_val: Value = obj.properties.get("index") orelse .{ .integer = 0 };
                                const keys_val: Value = obj.properties.get("keys") orelse .{ .void = {} };
                                const idx: i64 = switch (idx_val) {
                                    .integer => |i| i,
                                    else => 0,
                                };
                                if (keys_val != .array) {
                                    self.push(.{ .void = {} });
                                    self.push(.{ .boolean = true });
                                } else {
                                    const keys = keys_val.array;
                                    if (idx < 0 or @as(usize, @intCast(idx)) >= keys.elements.items.len) {
                                        self.push(.{ .void = {} });
                                        self.push(.{ .boolean = true });
                                    } else {
                                        const key = keys.elements.items[@intCast(idx)];
                                        obj.properties.put("index", .{ .integer = idx + 1 }) catch {};
                                        self.push(key);
                                        self.push(.{ .boolean = false });
                                    }
                                }
                            } else {
                                self.push(.{ .void = {} });
                                self.push(.{ .boolean = true });
                            }
                        },
                        else => {
                            self.push(.{ .void = {} });
                            self.push(.{ .boolean = true });
                        },
                    }
                },
                .get_for_in_keys => {
                    const val = self.pop();
                    const keys_arr = ast.ArrayObject.init(self.env.allocator) catch unreachable;
                    switch (val) {
                        .js_object => |obj| {
                            var it = obj.properties.iterator();
                            while (it.next()) |entry| {
                                const key_str = try self.env.allocator.dupe(u8, entry.key_ptr.*);
                                self.env.owned_strings.append(self.env.allocator, key_str) catch {};
                                keys_arr.elements.append(keys_arr.allocator, .{ .string = key_str }) catch {};
                            }
                        },
                        .array => |arr| {
                            var i: usize = 0;
                            while (i < arr.elements.items.len) {
                                var buf: [32]u8 = undefined;
                                const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                                const key_str = try self.env.allocator.dupe(u8, key_slice);
                                self.env.owned_strings.append(self.env.allocator, key_str) catch {};
                                keys_arr.elements.append(keys_arr.allocator, .{ .string = key_str }) catch {};
                                i += 1;
                            }
                        },
                        .string => |s| {
                            var i: usize = 0;
                            while (i < s.len) {
                                var buf: [32]u8 = undefined;
                                const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                                const key_str = try self.env.allocator.dupe(u8, key_slice);
                                self.env.owned_strings.append(self.env.allocator, key_str) catch {};
                                keys_arr.elements.append(keys_arr.allocator, .{ .string = key_str }) catch {};
                                i += 1;
                            }
                        },
                        .integer => |n| {
                            var repr: [32]u8 = undefined;
                            const str = std.fmt.bufPrint(&repr, "{d}", .{n}) catch "";
                            var i: usize = 0;
                            while (i < str.len) {
                                var buf: [4]u8 = undefined;
                                const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                                const key_str = try self.env.allocator.dupe(u8, key_slice);
                                self.env.owned_strings.append(self.env.allocator, key_str) catch {};
                                keys_arr.elements.append(keys_arr.allocator, .{ .string = key_str }) catch {};
                                i += 1;
                            }
                        },
                        .float => |n| {
                            var repr: [64]u8 = undefined;
                            const str = std.fmt.bufPrint(&repr, "{d}", .{n}) catch "";
                            var i: usize = 0;
                            while (i < str.len) {
                                var buf: [4]u8 = undefined;
                                const key_slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break;
                                const key_str = try self.env.allocator.dupe(u8, key_slice);
                                self.env.owned_strings.append(self.env.allocator, key_str) catch {};
                                keys_arr.elements.append(keys_arr.allocator, .{ .string = key_str }) catch {};
                                i += 1;
                            }
                        },
                        else => {},
                    }
                    self.env.arrays.append(self.env.allocator, keys_arr) catch {};
                    // Create ForInIterator js_object with keys + index
                    const for_in_obj = ast.ObjectValue.init(self.env.allocator) catch unreachable;
                    self.env.objects.append(self.env.allocator, for_in_obj) catch {};
                    for_in_obj.properties.put("@@type", .{ .string = "ForInIterator" }) catch {};
                    for_in_obj.properties.put("keys", .{ .array = keys_arr }) catch {};
                    for_in_obj.properties.put("index", .{ .integer = 0 }) catch {};
                    self.push(.{ .js_object = for_in_obj });
                },
            }
        }
    }
};

fn truthy(v: Value) bool {
    return switch (v) {
        .boolean => |b| b,
        .float => |f| f != 0.0,
        .integer => |i| i != 0,
        .big_int => |b| !b.eqlZero(),
        .string => |s| s.len > 0,
        .void, .null, .hole => false,
        else => true,
    };
}
/// ECMAScript ToNumber for VM arithmetic and relational comparison.
/// undefined (and array holes) coerce to NaN, null to +0, booleans to 0/1,
/// strings to their decimal literal ("" -> 0). Objects/arrays keep the legacy
/// 0 fallback; full ToPrimitive lives in the builtin layer.
fn toNumber(v: Value) f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .boolean => |b| if (b) 1.0 else 0.0,
        .null => 0.0,
        .void, .hole => std.math.nan(f64),
        .string => |s| stringToNumber(s),
        .big_int => |b| if (b.toI64()) |i| @floatFromInt(i) else 0.0,
        else => 0.0,
    };
}

/// Reading a hole yields undefined, like a missing element (ES ArrayGet).
fn arrayGet(a: *ast.ArrayObject, i: usize) Value {
    const v = a.get(i) orelse return .{ .void = {} };
    return if (v == .hole) .{ .void = {} } else v;
}

fn stringToNumber(s: []const u8) f64 {
    const trimmed = std.mem.trim(u8, s, " \t\n\r\x0b\x0c");
    if (trimmed.len == 0) return 0.0;
    if (std.ascii.eqlIgnoreCase(trimmed, "Infinity")) return std.math.inf(f64);
    if (std.ascii.eqlIgnoreCase(trimmed, "-Infinity")) return -std.math.inf(f64);
    if (std.ascii.eqlIgnoreCase(trimmed, "+Infinity")) return std.math.inf(f64);

    var body = trimmed;
    const signed = body.len > 0 and (body[0] == '+' or body[0] == '-');
    if (signed) body = body[1..];

    // Hex/binary/octal literals are unsigned in ECMAScript: "-0x10" is NaN.
    if (body.len > 2 and body[0] == '0') {
        const radix: u8 = switch (body[1]) {
            'x', 'X' => 16,
            'b', 'B' => 2,
            'o', 'O' => 8,
            else => 0,
        };
        if (radix != 0) {
            if (signed) return std.math.nan(f64);
            const parsed = std.fmt.parseInt(u64, body[2..], radix) catch return std.math.nan(f64);
            return @floatFromInt(parsed);
        }
    }

    return std.fmt.parseFloat(f64, trimmed) catch std.math.nan(f64);
}
fn toInt(v: Value) i64 {
    return switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    };
}

/// Convert an arbitrary Value to a *BigIntValue for arithmetic purposes.
/// If the value is already a big_int, it's used as-is.
/// If it's an integer or float (the latter only when it fits in i64), it's
/// promoted. Otherwise returns null.
fn vmCoerceBigInt(allocator: std.mem.Allocator, bigints_list: *std.ArrayList(*ast.BigIntValue), v: Value) !?*ast.BigIntValue {
    switch (v) {
        .big_int => |b| return b,
        .integer => |i| {
            const tmp = ast.BigIntValue.fromString(allocator, "0") catch return null;
            bigints_list.append(allocator, tmp) catch {};
            tmp.value.set(i) catch return null;
            return tmp;
        },
        .float => |f| {
            if (std.math.isNan(f) or f < @as(f64, @floatFromInt(std.math.minInt(i64))) or f > @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
                return null;
            }
            const i: i64 = @intFromFloat(f);
            const tmp = ast.BigIntValue.fromString(allocator, "0") catch return null;
            bigints_list.append(allocator, tmp) catch {};
            tmp.value.set(i) catch return null;
            return tmp;
        },
        else => return null,
    }
}

/// BigInt-aware arithmetic for VM. Returns a value to push on the stack.
/// Only handles cases where at least one operand is big_int; otherwise
/// would have been caught by the caller.
fn vmBigIntArith(allocator: std.mem.Allocator, bigints_list: *std.ArrayList(*ast.BigIntValue), op: Op, a: Value, b: Value) Value {
    const la = vmCoerceBigInt(allocator, bigints_list, a) catch return .void;
    const ra = vmCoerceBigInt(allocator, bigints_list, b) catch return .void;
    const lb = la orelse return .void;
    const rb = ra orelse return .void;

    const result = ast.BigIntValue.init(allocator) catch return .void;
    bigints_list.append(allocator, result) catch {};

    switch (op) {
        .add => {
            // result = lb + rb
            result.value.add(&lb.value, &rb.value) catch return .void;
        },
        .sub => {
            // result = lb - rb
            result.value.sub(&lb.value, &rb.value) catch return .void;
        },
        .mul => {
            // result = lb * rb
            result.value.mul(&lb.value, &rb.value) catch return .void;
        },
        .div => {
            // result = lb / rb (floor div)
            result.value.divFloor(&result.value, &lb.value, &rb.value) catch return .void;
        },
        .mod_ => {
            // Use a temp q for the quotient (we only want the remainder).
            var q = ast.BigIntValue.init(allocator) catch return .void;
            bigints_list.append(allocator, q) catch {};
            q.value.divFloor(&result.value, &lb.value, &rb.value) catch return .void;
        },
        else => return .void,
    }
    return .{ .big_int = result };
}
/// Try to coerce a Number (integer/float) into a `*BigIntValue` when the value
/// is integer-exact and fits in i64. Returns null otherwise.
fn vmCoerceNumberToBigInt(allocator: std.mem.Allocator, bigints_list: *std.ArrayList(*ast.BigIntValue), v: Value) !?*ast.BigIntValue {
    switch (v) {
        .integer => |i| {
            const tmp = ast.BigIntValue.fromString(allocator, "0") catch return null;
            bigints_list.append(allocator, tmp) catch {};
            tmp.value.set(i) catch return null;
            return tmp;
        },
        .float => |f| {
            if (std.math.isNan(f)) return null;
            if (f < @as(f64, @floatFromInt(std.math.minInt(i64))) or f > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return null;
            const i: i64 = @intFromFloat(f);
            if (@as(f64, @floatFromInt(i)) != f) return null;
            const tmp = ast.BigIntValue.fromString(allocator, "0") catch return null;
            bigints_list.append(allocator, tmp) catch {};
            tmp.value.set(i) catch return null;
            return tmp;
        },
        else => return null,
    }
}

/// Strict equality (`===`) — same type, same value. NaN never equal.
fn valStrictEq(l: Value, r: Value) bool {
    return switch (l) {
        .integer => |li| switch (r) {
            .integer => |ri| li == ri,
            else => false,
        },
        .float => |lf| switch (r) {
            .float => |rf| lf == rf,
            .integer => |ri| lf == @as(f64, @floatFromInt(ri)),
            else => false,
        },
        .big_int => |lb| switch (r) {
            .big_int => |rb| lb.compare(rb) == .eq,
            else => false,
        },
        .string => |ls| switch (r) {
            .string => |rs| std.mem.eql(u8, ls, rs),
            else => false,
        },
        .boolean => |lb| switch (r) {
            .boolean => |rb| lb == rb,
            else => false,
        },
        .void => r == .void,
        .null => r == .null,
        .hole => r == .void,
        .symbol => |ls| switch (r) {
            .symbol => |rs| ls.id == rs.id,
            else => false,
        },
        else => false,
    };
}

/// Loose equality (`==`) — ECMAScript 7.2.14 IsLooselyEqual.
fn valEq(allocator: std.mem.Allocator, bigints_list: *std.ArrayList(*ast.BigIntValue), l: Value, r: Value) bool {
    // Step 1: same type → strict comparison.
    if (std.meta.activeTag(l) == std.meta.activeTag(r)) {
        return switch (l) {
            .big_int => |lb| switch (r) {
                .big_int => |rb| lb.compare(rb) == .eq,
                else => unreachable,
            },
            .integer => |li| switch (r) {
                .integer => |ri| li == ri,
                else => unreachable,
            },
            .float => |lf| switch (r) {
                .float => |rf| lf == rf,
                else => unreachable,
            },
            .string => |ls| switch (r) {
                .string => |rs| std.mem.eql(u8, ls, rs),
                else => unreachable,
            },
            .boolean => |lb| switch (r) {
                .boolean => |rb| lb == rb,
                else => unreachable,
            },
            .void, .null, .hole => true,
            else => false,
        };
    }

    // Step 2/3: null == undefined (and vice-versa).
    if ((l == .null and r == .void) or (l == .void and r == .null)) return true;

    // null/undefined vs anything else → false.
    if (l == .null or l == .void or r == .null or r == .void) return false;

    // Step 4/5: Boolean ↔ anything → coerce boolean to number and recurse.
    // Runs before the BigInt cases: coerceNumberToBigInt rejects booleans,
    // but == coerces them to 0/1 first.
    {
        const bool_side: ?Value = if (l == .boolean) l else if (r == .boolean) r else null;
        if (bool_side != null) {
            const other = if (l == .boolean) r else l;
            const as_num: Value = .{ .integer = if (bool_side.?.boolean) @as(i64, 1) else @as(i64, 0) };
            return valEq(allocator, bigints_list, as_num, other);
        }
    }

    // Step 6: BigInt ↔ String → StringToBigInt (integer literal syntax only;
    // "1.0", "1e2" or "1n" parse to no value and compare false).
    {
        const big_side: ?Value = if (l == .big_int) l else if (r == .big_int) r else null;
        const str_side: ?Value = if (l == .string) l else if (r == .string) r else null;
        if (big_side != null and str_side != null) {
            const parsed = ast.BigIntValue.fromString(allocator, str_side.?.string) catch return false;
            bigints_list.append(allocator, parsed) catch {};
            return big_side.?.big_int.compare(parsed) == .eq;
        }
    }

    // Step 7: Number (integer/float) ↔ String → coerce string to number.
    {
        const str_side: ?Value = if (l == .string) l else if (r == .string) r else null;
        if (str_side != null) {
            const num_side = if (l == .string) r else l;
            const parsed = std.fmt.parseFloat(f64, str_side.?.string) catch std.math.nan(f64);
            return switch (num_side) {
                .integer => |i| parsed == @as(f64, @floatFromInt(i)),
                .float => |f| parsed == f,
                else => false,
            };
        }
    }

    // Step 8: BigInt ↔ Number → coerce number to BigInt if integer-exact.
    {
        const big_side: ?Value = if (l == .big_int) l else if (r == .big_int) r else null;
        if (big_side != null) {
            const num_side = if (l == .big_int) r else l;
            if (num_side != .integer and num_side != .float) return false;
            const coerced = vmCoerceNumberToBigInt(allocator, bigints_list, num_side) catch return false;
            const other = coerced orelse return false;
            return big_side.?.big_int.compare(other) == .eq;
        }
    }

    // Step 11/12: Object ↔ primitive → ToPrimitive not implemented yet.
    return false;
}
fn valToStr(a: std.mem.Allocator, buf: *std.ArrayList(u8), v: Value) void {
    switch (v) {
        .string => |s| buf.appendSlice(a, s) catch {},
        .integer => |i| {
            var tmp: [32]u8 = undefined;
            const w = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch unreachable;
            buf.appendSlice(a, tmp[0..w.len]) catch {};
        },
        .float => |f| {
            if (std.math.isNan(f)) {
                buf.appendSlice(a, "NaN") catch {};
            } else if (std.math.isInf(f)) {
                buf.appendSlice(a, if (f > 0) "Infinity" else "-Infinity") catch {};
            } else {
                var tmp: [64]u8 = undefined;
                const w = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch unreachable;
                var end = w.len;
                if (std.mem.indexOfScalar(u8, tmp[0..end], '.')) |_| {
                    while (end > 1) {
                        const candidate = std.fmt.parseFloat(f64, tmp[0 .. end - 1]) catch break;
                        if (candidate != f) break;
                        end -= 1;
                    }
                }
                buf.appendSlice(a, tmp[0..end]) catch {};
            }
        },
        .big_int => |b| {
            const digits = b.toString(a) catch return;
            defer a.free(digits);
            buf.appendSlice(a, digits) catch {};
            buf.appendSlice(a, "n") catch {};
        },
        .boolean => |b| buf.appendSlice(a, if (b) "true" else "false") catch {},
        .void => buf.appendSlice(a, "undefined") catch {},
        .null => buf.appendSlice(a, "null") catch {},
        .hole => buf.appendSlice(a, "undefined") catch {},
        else => buf.appendSlice(a, "[object]") catch {},
    }
}
fn getFloatValue(node: *ast.Node) ?f64 {
    return switch (node.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        .BigIntLiteral => null,
        else => null,
    };
}

test "VM throws TypeError for Map.size()" {
    const allocator = std.testing.allocator;
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;

    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    var lexer = Lexer.init("const m = new Map(); m.set(\"a\", 1); m.size();");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();

    var chunk = Chunk.init(allocator);
    defer chunk.deinit();
    var compiler = Compiler.init(&env_);
    compiler.compile(statements, &chunk);
    if (compiler.compile_error) |err| {
        compiler.deinit();
        std.debug.print("Compile error: {s}\n", .{err});
        return error.CompileError;
    }

    var vm = VM.init(&env_);
    defer vm.deinit();
    vm.compiled_chunks = compiler.compiled_chunks;
    compiler.compiled_chunks = std.StringHashMap(*Chunk).init(allocator);
    compiler.deinit();

    try std.testing.expectError(error.Thrown, vm.interpret(&chunk));
}

test "VM throws TypeError for Set.size()" {
    const allocator = std.testing.allocator;
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;

    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    var lexer = Lexer.init("const s = new Set(); s.add(1); s.size();");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();

    var chunk = Chunk.init(allocator);
    defer chunk.deinit();
    var compiler = Compiler.init(&env_);
    compiler.compile(statements, &chunk);
    if (compiler.compile_error) |err| {
        compiler.deinit();
        std.debug.print("Compile error: {s}\n", .{err});
        return error.CompileError;
    }

    var vm = VM.init(&env_);
    defer vm.deinit();
    vm.compiled_chunks = compiler.compiled_chunks;
    compiler.compiled_chunks = std.StringHashMap(*Chunk).init(allocator);
    compiler.deinit();

    try std.testing.expectError(error.Thrown, vm.interpret(&chunk));
}

test "VM throws TypeError for Array.length()" {
    const allocator = std.testing.allocator;
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;

    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    var lexer = Lexer.init("const arr = [1, 2, 3]; arr.length();");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();

    var chunk = Chunk.init(allocator);
    defer chunk.deinit();
    var compiler = Compiler.init(&env_);
    compiler.compile(statements, &chunk);
    if (compiler.compile_error) |err| {
        compiler.deinit();
        std.debug.print("Compile error: {s}\n", .{err});
        return error.CompileError;
    }

    var vm = VM.init(&env_);
    defer vm.deinit();
    vm.compiled_chunks = compiler.compiled_chunks;
    compiler.compiled_chunks = std.StringHashMap(*Chunk).init(allocator);
    compiler.deinit();

    try std.testing.expectError(error.Thrown, vm.interpret(&chunk));
}

test "VM throws TypeError for String.length()" {
    const allocator = std.testing.allocator;
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;

    var env_ = try Environment.init(allocator, null);
    defer env_.deinit();

    var lexer = Lexer.init("const str = \"hi\"; str.length();");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const statements = try parser.parseProgram();

    var chunk = Chunk.init(allocator);
    defer chunk.deinit();
    var compiler = Compiler.init(&env_);
    compiler.compile(statements, &chunk);
    if (compiler.compile_error) |err| {
        compiler.deinit();
        std.debug.print("Compile error: {s}\n", .{err});
        return error.CompileError;
    }

    var vm = VM.init(&env_);
    defer vm.deinit();
    vm.compiled_chunks = compiler.compiled_chunks;
    compiler.compiled_chunks = std.StringHashMap(*Chunk).init(allocator);
    compiler.deinit();

    try std.testing.expectError(error.Thrown, vm.interpret(&chunk));
}

test "toNumber follows ECMAScript ToNumber" {
    try std.testing.expect(std.math.isNan(toNumber(.{ .void = {} })));
    try std.testing.expect(std.math.isNan(toNumber(.{ .hole = {} })));
    try std.testing.expectEqual(@as(f64, 0.0), toNumber(.{ .null = {} }));
    try std.testing.expectEqual(@as(f64, 1.0), toNumber(.{ .boolean = true }));
    try std.testing.expectEqual(@as(f64, 0.0), toNumber(.{ .boolean = false }));
    try std.testing.expectEqual(@as(f64, 42.5), toNumber(.{ .float = 42.5 }));
    try std.testing.expectEqual(@as(f64, 42.0), toNumber(.{ .integer = 42 }));
}

test "stringToNumber parses StringNumericLiteral" {
    try std.testing.expectEqual(@as(f64, 0.0), stringToNumber(""));
    try std.testing.expectEqual(@as(f64, 0.0), stringToNumber("   "));
    try std.testing.expectEqual(@as(f64, 42.0), stringToNumber(" 42 "));
    try std.testing.expectEqual(@as(f64, 16.0), stringToNumber("0x10"));
    try std.testing.expectEqual(@as(f64, 3.0), stringToNumber("0b11"));
    try std.testing.expectEqual(@as(f64, 8.0), stringToNumber("0o10"));
    try std.testing.expect(std.math.isNan(stringToNumber("abc")));
    try std.testing.expect(std.math.isNan(stringToNumber("12px")));
    try std.testing.expect(std.math.isNan(stringToNumber("-0x10")));
    try std.testing.expect(std.math.isInf(stringToNumber("Infinity")));
    try std.testing.expect(std.math.isInf(stringToNumber("-Infinity")));
}
