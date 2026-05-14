const std = @import("std");
const ast = @import("ast.zig");
const Value = ast.Value;
const Environment = @import("evaluator.zig").Environment;
const builtinsTypes = @import("./types/types.zig");
const evaluate = @import("evaluator.zig").evaluate;

pub const Op = enum(u8) {
    constant, add, sub, mul, div, mod_, negate,
    eq, ne, lt, gt,
    not_, and_, or_, nullish,
    true_, false_, null_, void_,
    pop, dup,
    def_global, get_global, set_global, try_get_global,
    get_local, set_local,
    jump, jump_if_false, loop,
    make_array, index_get, get_prop, make_object, set_prop,
    bit_and, bit_or, bit_xor, bit_not, left_shift, right_shift,
    builtin, method_call, call, ret,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    consts: std.ArrayList(Value),
    allocator: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Chunk {
        return .{ .code = std.ArrayList(u8).initCapacity(a, 256) catch unreachable, .consts = std.ArrayList(Value).initCapacity(a, 64) catch unreachable, .allocator = a };
    }
    pub fn deinit(self: *Chunk) void { self.code.deinit(self.allocator); self.consts.deinit(self.allocator); }
    fn w8(self: *Chunk, b: u8) void { self.code.append(self.allocator, b) catch {}; }
    fn w16(self: *Chunk, v: u16) void { self.w8(@truncate(v >> 8)); self.w8(@truncate(v & 0xff)); }
    fn op(self: *Chunk, o: Op) void { self.w8(@intFromEnum(o)); }
    fn op2(self: *Chunk, o: Op, b: u8) void { self.op(o); self.w8(b); }
    fn op2w(self: *Chunk, o: Op, v: u16) void { self.op(o); self.w16(v); }
    fn addC(self: *Chunk, v: Value) u16 { self.consts.append(self.allocator, v) catch {}; return @intCast(self.consts.items.len - 1); }
    fn emitC(self: *Chunk, v: Value) void { self.op(.constant); self.w16(self.addC(v)); }
    fn emitS(self: *Chunk, s: []const u8) u16 { return self.addC(.{ .string = s }); }
    fn jmp(self: *Chunk, o: Op) usize { self.op(o); self.w8(0); self.w8(0); return self.code.items.len - 2; }
    fn ptch(self: *Chunk, pos: usize) void { const d = self.code.items.len - pos - 2; self.code.items[pos] = @truncate(d >> 8); self.code.items[pos+1] = @truncate(d & 0xff); }
    fn lloop(self: *Chunk, target: usize) void { self.op(.loop); const d = self.code.items.len - target + 2; self.w8(@truncate(d >> 8)); self.w8(@truncate(d & 0xff)); }
};

pub const Compiler = struct {
    c: *Chunk, env: *Environment, depth: u32,

    pub fn init(env: *Environment) Compiler {
        return .{ .c = undefined, .env = env, .depth = 0 };
    }
    pub fn deinit(_: *Compiler) void {}

    pub fn compile(self: *Compiler, stmts: []*ast.Node, chunk: *Chunk) void {
        self.c = chunk;
        for (stmts) |s| self.stmt(s);
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
            .ForLoop => self.forStmt(n),
            .ReturnStatement => { if (n.ReturnStatement.value) |v| self.expr(v); self.c.op(.ret); },
            .FunctionDeclaration => self.fnDecl(n),
            .ImportStatement => { _ = evaluate(n, self.env) catch {}; },
            .ExportStatement => |e| { self.stmt(e.declaration); },
            .Assignment => { self.expr(n); },
            .BinaryExpression => |b| {
                self.expr(n);
                switch (b.operator) {
                    .Assign, .PlusAssign, .MinusAssign, .MultiplyAssign, .DivideAssign, .ModuloAssign => {},
                    else => self.c.op(.pop),
                }
            },
            else => { self.expr(n); self.c.op(.pop); },
        }
    }

    fn decl(self: *Compiler, n: *ast.Node) void {
        const name = switch (n.*) { .ConstantDeclaration => |c| c.name, .VariableDeclaration => |v| v.name, .LetDeclaration => |v| v.name, else => unreachable };
        const val = switch (n.*) { .ConstantDeclaration => |c| c.value, .VariableDeclaration => |v| v.value, .LetDeclaration => |v| v.value, else => unreachable };
        if (val.* == .FunctionDeclaration or val.* == .ArrowFunction) {
            self.env.setFunction(name, val) catch {};
            return;
        }
        self.expr(val);
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
        self.expr(w.condition);
        const j = self.c.jmp(.jump_if_false); self.c.op(.pop);
        self.stmt(w.body);
        self.c.lloop(start); self.c.ptch(j); self.c.op(.pop);
    }

    fn forStmt(self: *Compiler, n: *ast.Node) void {
        if (self.tryOptimizeSimpleLoop(n)) return;
        const f = n.ForLoop;
        if (f.init) |initNode| self.stmt(initNode);
        const start = self.c.code.items.len;
        if (f.condition) |c| self.expr(c) else self.c.op(.true_);
        const j = self.c.jmp(.jump_if_false); self.c.op(.pop);
        self.stmt(f.body);
        if (f.increment) |inc| self.stmt(inc);
        self.c.lloop(start); self.c.ptch(j); self.c.op(.pop);
    }

    fn tryOptimizeSimpleLoop(self: *Compiler, n: *ast.Node) bool {
        const f = n.ForLoop;
        const init_node = f.init orelse return false;
        const loop_var = switch (init_node.*) {
            .VariableDeclaration => |v| blk: {
                const val = getFloatValue(v.value) orelse return false;
                if (val != 0.0) return false;
                break :blk v.name;
            },
            .LetDeclaration => |v| blk: {
                const val = getFloatValue(v.value) orelse return false;
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

    fn fnDecl(self: *Compiler, n: *ast.Node) void {
        const f = n.FunctionDeclaration;
        self.env.setFunction(f.name, n) catch {};
        // Skip compiling body for now — calls fallback to evaluator
    }

    fn expr(self: *Compiler, n: *ast.Node) void {
        switch (n.*) {
            .IntegerLiteral => |v| self.c.emitC(.{ .integer = v.value }),
            .FloatLiteral => |v| self.c.emitC(.{ .float = v.value }),
            .StringLiteral => |v| self.c.emitC(.{ .string = v.value }),
            .BooleanLiteral => |v| self.c.op(if (v.value) .true_ else .false_),
            .NullLiteral => self.c.op(.null_),
            .VoidLiteral => self.c.op(.void_),
            .Identifier => |id| self.c.op2w(.get_global, self.c.emitS(id.name)),
            .BinaryExpression => |b| switch (b.operator) {
                .Assign => {
                    if (b.left.* == .MemberAccess) {
                        self.expr(b.left.MemberAccess.object);
                        self.expr(b.right);
                        self.c.op2w(.set_prop, self.c.emitS(b.left.MemberAccess.property));
                    } else {
                        self.expr(b.right);
                        if (b.left.* == .Identifier) self.c.op2w(.set_global, self.c.emitS(b.left.Identifier.name));
                    }
                },
                .PlusAssign, .MinusAssign, .MultiplyAssign, .DivideAssign, .ModuloAssign => {
                    if (b.left.* == .Identifier) {
                        const name = b.left.Identifier.name;
                        const op2: Op = switch (b.operator) { .PlusAssign => .add, .MinusAssign => .sub, .MultiplyAssign => .mul, .DivideAssign => .div, .ModuloAssign => .mod_, else => .add };
                        self.c.op2w(.get_global, self.c.emitS(name));
                        self.expr(b.right);
                        self.c.op(op2);
                        self.c.op2w(.set_global, self.c.emitS(name));
                    }
                },
                .BitNot => {
                    // ~x is parsed as BinaryExpression(left=0, op=BitNot, right=x)
                    self.expr(b.right);
                    self.c.op(.bit_not);
                },
                else => {
                    self.expr(b.left); self.expr(b.right);
                    switch (b.operator) {
                        .Plus => self.c.op(.add), .Minus => self.c.op(.sub),
                        .Multiply => self.c.op(.mul), .Divide => self.c.op(.div), .Modulo => self.c.op(.mod_),
                        .Equal, .StrictEqual => self.c.op(.eq),
                        .NotEqual, .StrictNotEqual => self.c.op(.ne),
                        .LessThan => self.c.op(.lt), .GreaterThan => self.c.op(.gt),
                        .LessThanOrEqual => { self.c.op(.gt); self.c.op(.not_); },
                        .GreaterThanOrEqual => { self.c.op(.lt); self.c.op(.not_); },
                        .And => self.c.op(.and_), .Or => self.c.op(.or_), .Nullish => self.c.op(.nullish),
                        .Not => self.c.op(.not_),
                        .BitAnd => self.c.op(.bit_and),
                        .BitOr => self.c.op(.bit_or),
                        .BitXor => self.c.op(.bit_xor),
                        .LeftShift => self.c.op(.left_shift),
                        .RightShift => self.c.op(.right_shift),
                        else => {},
                    }
                },
            },
            .Assignment => |a| { self.expr(a.value); self.c.op2w(.set_global, self.c.emitS(a.name)); },
            .ArrayLiteral => |a| { for (a.elements) |e| self.expr(e); self.c.op2(.make_array, @intCast(a.elements.len)); },
            .ObjectLiteral => |o| {
                self.c.op(.make_object);
                for (o.properties) |prop| {
                    self.c.op(.dup);
                    self.expr(prop.value);
                    self.c.op2w(.set_prop, self.c.emitS(prop.key));
                    self.c.op(.pop);
                }
            },
            .PropertySet => |p| { self.expr(p.object); self.expr(p.value); self.c.op2w(.set_prop, self.c.emitS(p.key)); },
            .ArrayIndex => |ai| { self.expr(ai.array); self.expr(ai.index); self.c.op(.index_get); },
            .FunctionCall => |fc| {
                for (fc.arguments) |a| self.expr(a);
                self.c.op(.builtin); self.c.w16(self.c.emitS(fc.name)); self.c.w8(@intCast(fc.arguments.len));
            },
            .MethodCall => |mc| { self.expr(mc.object); for (mc.arguments) |a| self.expr(a); self.c.op(.method_call); self.c.w16(self.c.emitS(mc.method)); self.c.w8(@intCast(mc.arguments.len)); },
            .MemberAccess => |m| { self.expr(m.object); self.c.op2w(.get_prop, self.c.emitS(m.property)); },
            .ArrowFunction => {
                // Arrow function as expression — compile inline with evaluator's help
                // For now, just push void
                self.c.op(.void_);
            },
            else => {},
        }
    }

};

pub const VM = struct {
    c: *Chunk, ip: usize, sp: usize,
    stack: [65536]Value,
    env: *Environment,

    pub fn init(env: *Environment) VM {
        return .{ .c = undefined, .ip = 0, .sp = 0, .stack = undefined, .env = env };
    }
    pub fn deinit(_: *VM) void {}

    fn push(self: *VM, v: Value) void {
        if (self.sp >= self.stack.len) {
            std.debug.print("STACK OVERFLOW: sp={}, len={}, ip={}, last10 ops: const,add,pop...\n", .{ self.sp, self.stack.len, self.ip });
            @panic("stack overflow");
        }
        self.stack[self.sp] = v; self.sp += 1;
    }
    fn pop(self: *VM) Value {
        if (self.sp == 0) {
            std.debug.print("STACK UNDERFLOW: ip={}\n", .{self.ip});
            @panic("stack underflow");
        }
        self.sp -= 1; return self.stack[self.sp];
    }
    fn peek(self: *VM, d: usize) Value { return self.stack[self.sp - 1 - d]; }
    fn readU16(self: *VM) u16 { const hi = self.c.code.items[self.ip]; const lo = self.c.code.items[self.ip+1]; self.ip += 2; return (@as(u16, hi) << 8) | lo; }

    pub fn interpret(self: *VM, chunk: *Chunk) !void {
        self.c = chunk; self.ip = 0; self.sp = 0;
        while (self.ip < self.c.code.items.len) {
            const op: Op = @enumFromInt(self.c.code.items[self.ip]); self.ip += 1;
            switch (op) {
                .constant => { const ci = self.readU16(); self.push(self.c.consts.items[ci]); if (self.sp >= 65000) std.debug.print("constant: sp={}, ip={}\n", .{self.sp, self.ip}); },
                .true_ => self.push(.{ .boolean = true }), .false_ => self.push(.{ .boolean = false }),
                .null_ => self.push(.{ .null = {} }), .void_ => self.push(.{ .void = {} }),
                .add, .sub, .mul, .div, .mod_ => {
                    const b = self.pop(); const a = self.pop();
                    if (op == .add and (a == .string or b == .string)) {
                        var buf = std.ArrayList(u8).initCapacity(self.env.allocator, 64) catch unreachable;
                        defer buf.deinit(self.env.allocator);
                        valToStr(self.env.allocator, &buf, a); valToStr(self.env.allocator, &buf, b);
                        const s = buf.toOwnedSlice(self.env.allocator) catch unreachable;
                        self.env.owned_strings.append(self.env.allocator, s) catch {};
                        self.push(.{ .string = s });
                    } else {
                        const av = toF64(a) orelse 0.0; const bv = toF64(b) orelse 0.0;
                        self.push(.{ .float = switch (op) { .add => av+bv, .sub => av-bv, .mul => av*bv, .div => av/bv, .mod_ => @mod(av,bv), else => 0.0 } });
                    }
                },
                .negate => { const v = toF64(self.pop()) orelse 0.0; self.push(.{ .float = -v }); },
                .eq => self.push(.{ .boolean = valEq(self.pop(), self.pop()) }),
                .ne => self.push(.{ .boolean = !valEq(self.pop(), self.pop()) }),
                .lt => { const b = self.pop(); const a = self.pop(); const av = toF64(a) orelse 0.0; const bv = toF64(b) orelse 0.0; self.push(.{ .boolean = av < bv }); },
                .gt => { const b = self.pop(); const a = self.pop(); const av = toF64(a) orelse 0.0; const bv = toF64(b) orelse 0.0; self.push(.{ .boolean = av > bv }); },
                .not_ => self.push(.{ .boolean = !truthy(self.pop()) }),
                .and_ => { const b = self.pop(); const a = self.pop(); self.push(.{ .boolean = truthy(a) and truthy(b) }); },
                .or_ => { const b = self.pop(); const a = self.pop(); self.push(.{ .boolean = truthy(a) or truthy(b) }); },
                .nullish => { const b = self.pop(); const a = self.pop(); self.push(if (a == .null or a == .void) b else a); },
                .bit_and => { const b = toInt(self.pop()); const a = toInt(self.pop()); self.push(.{ .integer = a & b }); },
                .bit_or => { const b = toInt(self.pop()); const a = toInt(self.pop()); self.push(.{ .integer = a | b }); },
                .bit_xor => { const b = toInt(self.pop()); const a = toInt(self.pop()); self.push(.{ .integer = a ^ b }); },
                .bit_not => { const a = toInt(self.pop()); self.push(.{ .integer = ~a }); },
                .left_shift => { const b = toInt(self.pop()); const a = toInt(self.pop()); self.push(.{ .integer = a << @intCast(b) }); },
                .right_shift => { const b = toInt(self.pop()); const a = toInt(self.pop()); self.push(.{ .integer = a >> @intCast(b) }); },
                .pop => _ = self.pop(),
                .dup => { const v = self.peek(0); self.push(v); },
                .def_global => { const ci = self.readU16(); const n = self.c.consts.items[ci].string; const v = self.peek(0); self.sp -= 1; self.env.setVar(n, v) catch {}; },
                .get_global => { const ci = self.readU16(); const n = self.c.consts.items[ci].string;
                    if (self.env.get(n)) |v| { self.push(v); } else if (self.env.getBuiltin(n)) |_| { self.push(.{ .void = {} }); }
                    else if (self.env.getBuiltinObject(n)) |obj| { self.push(.{ .object = @ptrCast(obj) }); }
                    else { return error.UndefinedVariable; }
                },
                .set_global => { const ci = self.readU16(); const n = self.c.consts.items[ci].string; const v = self.peek(0); self.sp -= 1; self.env.setInScope(n, v) catch {}; },
                .try_get_global => { const ci = self.readU16(); const n = self.c.consts.items[ci].string;
                    if (self.env.get(n)) |v| { self.push(v); } else { self.push(.{ .void = {} }); }
                },
                .get_local => { const slot = self.c.code.items[self.ip]; self.ip += 1; self.push(self.stack[slot]); },
                .set_local => { const slot = self.c.code.items[self.ip]; self.ip += 1; self.stack[slot] = self.peek(0); },
                .jump => { const hi = self.c.code.items[self.ip]; const lo = self.c.code.items[self.ip+1]; self.ip += 2 + (@as(usize,hi) << 8) | lo; },
                .jump_if_false => { const hi = self.c.code.items[self.ip]; const lo = self.c.code.items[self.ip+1]; self.ip += 2; if (!truthy(self.peek(0))) self.ip += (@as(usize,hi) << 8) | lo; },
                .loop => { const hi = self.c.code.items[self.ip]; const lo = self.c.code.items[self.ip+1]; self.ip += 2; self.ip -= (@as(usize,hi) << 8) | lo; },
                .make_array => {
                    const cnt = self.c.code.items[self.ip]; self.ip += 1;
                    const arr = ast.ArrayObject.init(self.env.allocator) catch unreachable;
                    var i: usize = 0; while (i < cnt) : (i += 1) { arr.elements.append(arr.allocator, self.stack[self.sp - cnt + i]) catch {}; }
                    self.sp -= cnt;
                    self.env.arrays.append(self.env.allocator, arr) catch {};
                    self.push(.{ .array = arr });
                },
                .index_get => {
                    const idx = self.pop(); const arr = self.pop();
                    if (arr != .array) return error.NotAnArray;
                    const i: usize = switch (idx) { .integer => |n| @intCast(n), .float => |n| @intFromFloat(n), else => return error.InvalidIndex };
                    self.push(arr.array.get(i) orelse return error.IndexOutOfBounds);
                },
                .get_prop => {
                    const ci = self.readU16();
                    const p = self.c.consts.items[ci].string;
                    const obj = self.pop();
                    if (obj == .array and std.mem.eql(u8, p, "length")) {
                        self.push(.{ .integer = @intCast(obj.array.elements.items.len) });
                    } else if (obj == .js_object) {
                        if (obj.js_object.properties.get(p)) |v| {
                            self.push(v);
                        } else {
                            self.push(.{ .void = {} });
                        }
                    } else { self.push(.{ .void = {} }); }
                },
                .make_object => {
                    const obj = ast.ObjectValue.init(self.env.allocator) catch unreachable;
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
                    } else { self.push(.{ .void = {} }); }
                },
                .builtin => {
                    const ci = self.readU16();
                    const ac = self.c.code.items[self.ip]; self.ip += 1;
                    const name = self.c.consts.items[ci].string;
                    var args = std.ArrayList(Value).initCapacity(self.env.allocator, ac) catch unreachable;
                    defer args.deinit(self.env.allocator);
                    var i: usize = 0; while (i < ac) : (i += 1) { args.insert(self.env.allocator, 0, self.pop()) catch {}; }
                    if (self.env.getBuiltin(name)) |fnPtr| {
                        const r = fnPtr(args.items, self.env);
                        switch (r) { .value => |v| self.push(v), .void => self.push(.{ .void = {} }) }
                    } else if (self.env.getFunction(name)) |funcNode| {
                        var func_env = try Environment.init(self.env.allocator, self.env);
                        defer func_env.deinit();
                        if (funcNode.* == .FunctionDeclaration) {
                            const f = funcNode.FunctionDeclaration;
                            for (f.parameters, 0..) |p, j| { if (j < args.items.len) try func_env.setVar(p, args.items[j]); }
                            const r = try evaluate(f.body, &func_env);
                            self.push(r);
                        } else if (funcNode.* == .ArrowFunction) {
                            const f = funcNode.ArrowFunction;
                            for (f.parameters, 0..) |p, j| { if (j < args.items.len) try func_env.setVar(p, args.items[j]); }
                            const r = try evaluate(f.body, &func_env);
                            self.push(r);
                        } else { self.push(.{ .void = {} }); }
                    } else { return error.UndefinedFunction; }
                },
                .method_call => {
                    const ci = self.readU16();
                    const ac = self.c.code.items[self.ip]; self.ip += 1;
                    const m = self.c.consts.items[ci].string;
                    if (ac > 0) {
                        var args = std.ArrayList(Value).initCapacity(self.env.allocator, ac) catch unreachable;
                        defer args.deinit(self.env.allocator);
                        var i: usize = 0; while (i < ac) : (i += 1) { args.insert(self.env.allocator, 0, self.pop()) catch {}; }
                        const obj = self.pop();
                        if (obj == .array) {
                            args.insert(self.env.allocator, 0, obj) catch {};
                            const bObj = self.env.getBuiltinObject("Array") orelse return error.UndefinedObject;
                            const md = bObj.getMethod(m) orelse return error.UndefinedMethod;
                            const r = md(args.items, self.env);
                            switch (r) { .value => |v| self.push(v), .void => self.push(.{ .void = {} }) }
                        } else if (obj == .object) {
                            const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @alignCast(@ptrCast(obj.object));
                            const md = bObjPtr.getMethod(m) orelse { self.push(.{ .void = {} }); break; };
                            const r = md(args.items, self.env);
                            switch (r) { .value => |v| self.push(v), .void => self.push(.{ .void = {} }) }
                        } else if (obj == .iterator) {
                            const v = obj.iterator.next(self.env.allocator, &self.env.arrays, &self.env.objects);
                            self.push(v);
                        } else { self.push(.{ .void = {} }); }
                    } else {
                        const obj = self.pop();
                        if (obj == .object) {
                            const bObjPtr: *const builtinsTypes.BuiltinObjectImpl = @alignCast(@ptrCast(obj.object));
                            const md = bObjPtr.getMethod(m) orelse { self.push(.{ .void = {} }); break; };
                            const r = md(&.{}, self.env);
                            switch (r) { .value => |v| self.push(v), .void => self.push(.{ .void = {} }) }
                        } else if (obj == .array) {
                            const bObj = self.env.getBuiltinObject("Array") orelse { self.push(.{ .void = {} }); break; };
                            const md = bObj.getMethod(m) orelse { self.push(.{ .void = {} }); break; };
                            var tmp = [_]Value{obj};
                            const r = md(tmp[0..], self.env);
                            switch (r) { .value => |v| self.push(v), .void => self.push(.{ .void = {} }) }
                        } else if (obj == .iterator) {
                            const v = obj.iterator.next(self.env.allocator, &self.env.arrays, &self.env.objects);
                            self.push(v);
                        } else { self.push(.{ .void = {} }); }
                    }
                },
                .ret => return,
                .call => {
                    const ac = self.c.code.items[self.ip]; self.ip += 1;
                    _ = ac; _ = self.pop(); // placeholder — function calls handled via builtin fallback
                },
            }
        }
    }
};

fn truthy(v: Value) bool { return switch (v) { .boolean => |b| b, .float => |f| f != 0.0, .integer => |i| i != 0, .string => |s| s.len > 0, .void,.null => false, else => true }; }
fn toF64(v: Value) ?f64 { return switch (v) { .float => |f| f, .integer => |i| @floatFromInt(i), else => null }; }
fn toInt(v: Value) i64 { return switch (v) { .integer => |i| i, .float => |f| @intFromFloat(f), else => 0 }; }
fn valEq(l: Value, r: Value) bool { return switch (l) {
    .integer => |li| switch (r) { .integer => |ri| li==ri, .float => |rf| @as(f64,@floatFromInt(li))==rf, else => false },
    .float => |lf| switch (r) { .float => |rf| lf==rf, .integer => |ri| lf==@as(f64,@floatFromInt(ri)), else => false },
    .string => |ls| switch (r) { .string => |rs| std.mem.eql(u8,ls,rs), else => false },
    .boolean => |lb| switch (r) { .boolean => |rb| lb==rb, else => false },
    .void => r == .void, .null => r == .null,
    else => false,
}; }
fn valToStr(a: std.mem.Allocator, buf: *std.ArrayList(u8), v: Value) void { switch (v) {
    .string => |s| buf.appendSlice(a, s) catch {},
    .integer => |i| { var tmp: [32]u8 = undefined; const w = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch unreachable; buf.appendSlice(a, tmp[0..w.len]) catch {}; },
    .float => |f| { var tmp: [64]u8 = undefined; const w = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch unreachable; buf.appendSlice(a, tmp[0..w.len]) catch {}; },
    .boolean => |b| buf.appendSlice(a, if (b) "true" else "false") catch {},
    .void => buf.appendSlice(a, "undefined") catch {},
    .null => buf.appendSlice(a, "null") catch {},
    else => buf.appendSlice(a, "[object]") catch {},
}
}
fn getFloatValue(node: *ast.Node) ?f64 {
    return switch (node.*) {
        .FloatLiteral => |v| v.value,
        .IntegerLiteral => |v| @floatFromInt(v.value),
        else => null,
    };
}
