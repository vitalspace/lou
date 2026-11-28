const std = @import("std");

const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;

/// `=`, every `op=` and `**` group to the right:
/// `a = b = 1` means `a = (b = 1)`, not `(a = b) = 1`.
fn isRightAssociative(token: TokenType) bool {
    return switch (token) {
        .Assign, .PlusAssign, .MinusAssign, .MultiplyAssign, .DivideAssign, .ModuloAssign, .PowerAssign, .AndAssign, .OrAssign, .NullishAssign, .LeftShiftAssign, .RightShiftAssign, .UnsignedRightShiftAssign, .Exponent => true,
        else => false,
    };
}

fn findTemplateExprEnd(raw: []const u8, start: usize) ?usize {
    var depth: usize = 1;
    var i = start;
    var quote: u8 = 0;
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (quote != 0) {
            if (c == '\\') {
                i += 1;
                continue;
            }
            if (c == quote) quote = 0;
            continue;
        }
        switch (c) {
            '\'', '"', '`' => quote = c,
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return null;
}

pub const Parser = struct {
    lexer: *Lexer,
    current_token: Token,
    peek_token: Token,
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    arena_child: std.mem.Allocator,
    dest_tmp_counter: u32 = 0,

    pub fn init(lexer: *Lexer, allocator: std.mem.Allocator) !Parser {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        var p = Parser{
            .lexer = lexer,
            .current_token = undefined,
            .peek_token = undefined,
            .allocator = arena.allocator(),
            .arena = arena,
            .arena_child = allocator,
        };
        p.nextToken();
        p.nextToken();
        return p;
    }

    fn isPropertyName(tok_type: TokenType) bool {
        return switch (tok_type) {
            .Identifier => true,
            .Const, .Var, .Let, .Null, .Undefined, .True, .False, .Fn, .Return, .If, .Else, .For, .While, .Do, .In, .Of, .Break, .Continue, .Switch, .Case, .Default, .Match, .Import, .From, .As, .Export, .TypeOf, .Yield, .New, .Delete, .InstanceOf, .Void, .Try, .Catch, .Finally, .Throw, .Using, .Await, .Async, .Class, .Extends, .Super, .Static, .Get, .Set => true,
            else => false,
        };
    }

    pub fn deinit(this: *Parser) void {
        this.arena.deinit();
        this.arena_child.destroy(this.arena);
    }

    pub fn parseExpression(this: *Parser) anyerror!*ast.Node {
        return try this.parsePrecedece(.lowest);
    }

    pub fn parseCommaExpression(this: *Parser) anyerror!*ast.Node {
        const expr = try this.parsePrecedece(.lowest);

        if (this.current_token.type == .Comma) {
            var expressions = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
            defer expressions.deinit(this.allocator);

            try expressions.append(this.allocator, expr);
            while (this.current_token.type == .Comma) {
                this.nextToken(); // consume ','
                const next = try this.parsePrecedece(.lowest);
                try expressions.append(this.allocator, next);
            }

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .CommaExpression = .{ .expressions = try expressions.toOwnedSlice(this.allocator) } };
            return node;
        }

        return expr;
    }

    pub fn parseProgram(this: *Parser) ![]*ast.Node {
        var statements = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 16);
        defer statements.deinit(this.allocator);

        while (this.current_token.type != .EOF) {
            const stmt = try this.parseStatement();
            try statements.append(this.allocator, stmt);
            if (this.current_token.type == .Semicolon) {
                this.nextToken();
            }
        }

        return try statements.toOwnedSlice(this.allocator);
    }

    pub fn parseStatement(this: *Parser) anyerror!*ast.Node {
        const result = stmt: {
            switch (this.current_token.type) {
                .Const => {
                    const first = try this.parseConstantDeclaration();
                    if (this.current_token.type != .Comma) break :stmt first;
                    var stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
                    defer stmts.deinit(this.allocator);
                    try stmts.append(this.allocator, first);
                    while (this.current_token.type == .Comma) {
                        this.nextToken(); // consume ','
                        const name = this.current_token.literal;
                        this.nextToken(); // consume identifier
                        this.nextToken(); // consume '='
                        const value = try this.parseExpression();
                        const n = try this.allocator.create(ast.Node);
                        n.* = .{ .ConstantDeclaration = .{ .name = name, .value = value } };
                        try stmts.append(this.allocator, n);
                    }
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .BlockStatement = .{ .statements = try stmts.toOwnedSlice(this.allocator), .is_scope = false } };
                    break :stmt node;
                },
                .Var => {
                    const first = try this.parseVariableDeclaration();
                    if (this.current_token.type != .Comma) break :stmt first;
                    var stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
                    defer stmts.deinit(this.allocator);
                    try stmts.append(this.allocator, first);
                    while (this.current_token.type == .Comma) {
                        this.nextToken(); // consume ','
                        const name = this.current_token.literal;
                        this.nextToken(); // consume identifier
                        this.nextToken(); // consume '='
                        const value = try this.parseExpression();
                        const n = try this.allocator.create(ast.Node);
                        n.* = .{ .VariableDeclaration = .{ .name = name, .value = value } };
                        try stmts.append(this.allocator, n);
                    }
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .BlockStatement = .{ .statements = try stmts.toOwnedSlice(this.allocator), .is_scope = false } };
                    break :stmt node;
                },
                .Let => {
                    const first = try this.parseLetDeclaration();
                    if (this.current_token.type != .Comma) break :stmt first;
                    var stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
                    defer stmts.deinit(this.allocator);
                    try stmts.append(this.allocator, first);
                    while (this.current_token.type == .Comma) {
                        this.nextToken(); // consume ','
                        const name = this.current_token.literal;
                        this.nextToken(); // consume identifier
                        this.nextToken(); // consume '='
                        const value = try this.parseExpression();
                        const n = try this.allocator.create(ast.Node);
                        n.* = .{ .LetDeclaration = .{ .name = name, .value = value } };
                        try stmts.append(this.allocator, n);
                    }
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .BlockStatement = .{ .statements = try stmts.toOwnedSlice(this.allocator), .is_scope = false } };
                    break :stmt node;
                },
                .For => break :stmt try this.parseForLoop(),
                .While => break :stmt try this.parseWhileLoop(),
                .Do => break :stmt try this.parseDoWhileLoop(),
                .Switch => break :stmt try this.parseSwitchStatement(),
                .If => break :stmt try this.parseIfStatement(),
                .Return => break :stmt try this.parseReturnStatement(),
                .Break => break :stmt try this.parseBreakStatement(),
                .Continue => break :stmt try this.parseContinueStatement(),
                .Try => break :stmt try this.parseTryStatement(),
                .Throw => break :stmt try this.parseThrowStatement(),
                .Fn => break :stmt try this.parseFunctionDeclaration(),
                .Async => {
                    if (this.isAsyncSyntaxStart()) break :stmt try this.parseAsyncFunctionOrArrow();
                    break :stmt try this.parseCommaExpression();
                },
                .Class => break :stmt try this.parseClass(true),
                .Import => break :stmt try this.parseImportStatement(),
                .Export => break :stmt try this.parseExportStatement(),
                .Semicolon => {
                    this.nextToken(); // consume ';'
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .VoidLiteral = .{} };
                    break :stmt node;
                },
                .Identifier => {
                    // Check for labeled statement: `identifier: statement`
                    if (this.peek_token.type == .Colon) {
                        const label = this.current_token.literal;
                        this.nextToken(); // consume identifier
                        this.nextToken(); // consume ':'
                        const body = try this.parseStatement();
                        const node = try this.allocator.create(ast.Node);
                        node.* = .{ .LabeledStatement = .{ .label = label, .body = body } };
                        break :stmt node;
                    } else if (this.peek_token.type == .Assign) {
                        const name = this.current_token.literal;
                        this.nextToken(); // consume identifier
                        this.nextToken(); // consume =
                        const value = try this.parseExpression();
                        const node = try this.allocator.create(ast.Node);
                        node.* = .{ .Assignment = .{
                            .name = name,
                            .value = value,
                        } };
                        break :stmt node;
                    } else if (this.peek_token.type == .Dot or this.peek_token.type == .LBracket) {
                        const expr = try this.parseCommaExpression();
                        if (this.current_token.type == .Assign) {
                            if (expr.* == .MemberAccess) {
                                const key = expr.MemberAccess.property;
                                const object = expr.MemberAccess.object;
                                this.allocator.destroy(expr);
                                this.nextToken(); // consume '='
                                const value = try this.parseExpression();
                                const node = try this.allocator.create(ast.Node);
                                node.* = .{ .PropertySet = .{ .object = object, .key = key, .value = value } };
                                break :stmt node;
                            }
                            return error.InvalidAssignmentTarget;
                        }
                        break :stmt expr;
                    } else {
                        break :stmt try this.parseCommaExpression();
                    }
                },
                .LBrace => break :stmt try this.parseBlockStatement(),
                .LBracket => {
                    // Try array destructuring assignment: [a, b] = expr
                    // Use backtracking: save state, try parsing as destructured assign;
                    // if it doesn't end with '=', backtrack and parse as expression.
                    const saved_lexer = this.lexer.*;
                    const saved_current = this.current_token;
                    const saved_peek = this.peek_token;

                    if (this.parseDestructuredAssign()) |result| {
                        break :stmt result;
                    } else |_| {
                        this.lexer.* = saved_lexer;
                        this.current_token = saved_current;
                        this.peek_token = saved_peek;
                        break :stmt try this.parseCommaExpression();
                    }
                },
                else => break :stmt try this.parseCommaExpression(),
            }
        };

        // Handle comma operator at statement level
        if (this.current_token.type == .Comma) {
            var exprs = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
            defer exprs.deinit(this.allocator);
            try exprs.append(this.allocator, result);
            while (this.current_token.type == .Comma) {
                this.nextToken(); // consume ','
                const next = try this.parseCommaExpression();
                try exprs.append(this.allocator, next);
            }
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .CommaExpression = .{ .expressions = try exprs.toOwnedSlice(this.allocator) } };
            return node;
        }

        return result;
    }

    fn genDestTempName(this: *Parser) ![]const u8 {
        var buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "_dest{d}", .{this.dest_tmp_counter});
        this.dest_tmp_counter += 1;
        return try this.allocator.dupe(u8, name);
    }

    fn makeIdentNode(this: *Parser, name: []const u8) !*ast.Node {
        const n = try this.allocator.create(ast.Node);
        n.* = .{ .Identifier = .{ .name = name } };
        return n;
    }

    /// Create a binding node: VariableDeclaration when decl_mode is true,
    /// Assignment when decl_mode is false.
    fn makeBindNode(this: *Parser, name: []const u8, value: *ast.Node, decl_mode: bool) !*ast.Node {
        const n = try this.allocator.create(ast.Node);
        if (decl_mode) {
            n.* = .{ .VariableDeclaration = .{ .name = name, .value = value } };
        } else {
            n.* = .{ .Assignment = .{ .name = name, .value = value } };
        }
        return n;
    }

    /// Parse a destructured declaration: const/let/var [a, b] = expr  or  const/let/var {x, y} = expr.
    /// Returns a BlockStatement containing VarDeclaration nodes for the temp and all bindings.
    fn parseDestructuredDecl(this: *Parser, decl_kind: TokenType) !*ast.Node {
        _ = decl_kind; // ignored — all destructured bindings use VariableDeclaration for correct scoping

        var stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 8);
        defer stmts.deinit(this.allocator);

        const temp_name = try this.genDestTempName();
        const temp_ident = try this.makeIdentNode(temp_name);

        // Parse the pattern recursively, using temp_ident as the source access
        try this.parseDestructuredPattern(temp_ident, &stmts, true);

        // Expect '='
        if (this.current_token.type != .Assign) return error.ExpectedAssign;
        this.nextToken();

        // Parse RHS
        const rhs = try this.parseExpression();

        // Build temp decl: var _dest0 = <rhs>
        const temp_decl = try this.allocator.create(ast.Node);
        temp_decl.* = .{ .VariableDeclaration = .{ .name = temp_name, .value = rhs } };

        // Build BlockStatement: [temp_decl, binding1, binding2, ...]
        var all_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, stmts.items.len + 1);
        defer all_stmts.deinit(this.allocator);
        try all_stmts.append(this.allocator, temp_decl);
        for (stmts.items) |s| try all_stmts.append(this.allocator, s);

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BlockStatement = .{ .statements = try all_stmts.toOwnedSlice(this.allocator) } };
        return node;
    }

    /// Parse a destructuring pattern (array or object) recursively.
    /// `source` is an expression node that evaluates to the value being destructured.
    /// When `decl_mode` is true, appends VariableDeclaration nodes to `stmts`
    /// (for const/let/var declarations). When false, appends Assignment nodes
    /// (for destructuring assignments like [a, b] = expr).
    fn parseDestructuredPattern(this: *Parser, source: *ast.Node, stmts: *std.ArrayList(*ast.Node), decl_mode: bool) !void {
        const is_array = this.current_token.type == .LBracket;
        this.nextToken(); // consume '[' or '{'

        if (is_array) {
            var idx: usize = 0;
            while (this.current_token.type != .RBracket) {
                // Elision: skip empty slots
                if (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                    idx += 1;
                    continue;
                }

                // Rest element: ...restName or ...nestedPattern
                if (this.current_token.type == .DotDotDot) {
                    this.nextToken(); // consume '...'

                    // Nested destructuring rest: ...[pat] or ...{pat}
                    if (this.current_token.type == .LBracket or this.current_token.type == .LBrace) {
                        // Create a temp for the sliced rest: _destN = source.slice(idx)
                        const rest_temp_name = try this.genDestTempName();
                        const rest_temp_ident = try this.makeIdentNode(rest_temp_name);

                        // Build source.slice(idx) call
                        const idx_node = try this.allocator.create(ast.Node);
                        idx_node.* = .{ .IntegerLiteral = .{ .value = @intCast(idx) } };
                        const slice_args = try this.allocator.alloc(*ast.Node, 1);
                        slice_args[0] = idx_node;
                        const slice_call = try this.allocator.create(ast.Node);
                        slice_call.* = .{ .MethodCall = .{
                            .object = source,
                            .method = "slice",
                            .arguments = slice_args,
                        } };

                        // Declare: var _destN = source.slice(idx)
                        const rest_temp_decl = try this.allocator.create(ast.Node);
                        rest_temp_decl.* = .{ .VariableDeclaration = .{ .name = rest_temp_name, .value = slice_call } };
                        try stmts.append(this.allocator, rest_temp_decl);

                        // Parse the nested destructuring pattern on the sliced rest
                        try this.parseDestructuredPattern(rest_temp_ident, stmts, decl_mode);

                        while (this.current_token.type == .Comma) this.nextToken();
                        break;
                    }

                    const bind_name = this.current_token.literal;
                    this.nextToken(); // consume name

                    // Build source.slice(idx) so rest gets only remaining elements
                    const idx_node = try this.allocator.create(ast.Node);
                    idx_node.* = .{ .IntegerLiteral = .{ .value = @intCast(idx) } };
                    const slice_args = try this.allocator.alloc(*ast.Node, 1);
                    slice_args[0] = idx_node;
                    const slice_call = try this.allocator.create(ast.Node);
                    slice_call.* = .{ .MethodCall = .{
                        .object = source,
                        .method = "slice",
                        .arguments = slice_args,
                    } };

                    const decl = try this.makeBindNode(bind_name, slice_call, decl_mode);
                    try stmts.append(this.allocator, decl);

                    while (this.current_token.type == .Comma) this.nextToken();
                    break;
                }

                // Nested pattern: [ or { at element position
                if (this.current_token.type == .LBracket or this.current_token.type == .LBrace) {
                    const idx_node = try this.allocator.create(ast.Node);
                    idx_node.* = .{ .IntegerLiteral = .{ .value = @intCast(idx) } };

                    // Build access: source[idx]
                    const sub_source = try this.allocator.create(ast.Node);
                    sub_source.* = .{ .ArrayIndex = .{ .array = source, .index = idx_node } };

                    // Create a temp to hold the sub-source so we can apply
                    // a whole-pattern default after the nested pattern is parsed.
                    const inner_temp_name = try this.genDestTempName();
                    const inner_temp_ident = try this.makeIdentNode(inner_temp_name);
                    const saved_stmts_len = stmts.items.len;
                    try this.parseDestructuredPattern(inner_temp_ident, stmts, decl_mode);

                    // Handle nested whole-pattern default: [a, [b, c] = defaultArr]
                    var nested_default: ?*ast.Node = null;
                    if (this.current_token.type == .Assign) {
                        this.nextToken(); // consume '='
                        nested_default = try this.parseExpression();
                    }

                    // Build: var _destN = sub_source ?? defaultValue  (or just sub_source)
                    const inner_value: *ast.Node = if (nested_default) |def| blk: {
                        const nullish = try this.allocator.create(ast.Node);
                        nullish.* = .{ .BinaryExpression = .{
                            .left = sub_source,
                            .operator = .Nullish,
                            .right = def,
                        } };
                        break :blk nullish;
                    } else sub_source;
                    const inner_decl = try this.allocator.create(ast.Node);
                    inner_decl.* = .{ .VariableDeclaration = .{ .name = inner_temp_name, .value = inner_value } };
                    try stmts.insert(this.allocator, saved_stmts_len, inner_decl);

                    idx += 1;

                    if (this.current_token.type == .Comma) {
                        this.nextToken();
                    } else if (this.current_token.type != .RBracket) {
                        return error.ExpectedCommaOrRBracket;
                    }
                    continue;
                }

                // Regular binding: name or name = default
                const bind_name = this.current_token.literal;
                this.nextToken(); // consume name

                // Check for default value: name = expr
                var default_val: ?*ast.Node = null;
                if (this.current_token.type == .Assign) {
                    this.nextToken();
                    default_val = try this.parseExpression();
                }

                // Build index literal
                const idx_node = try this.allocator.create(ast.Node);
                idx_node.* = .{ .IntegerLiteral = .{ .value = @intCast(idx) } };

                // Build access: source[idx]
                const access = try this.allocator.create(ast.Node);
                access.* = .{ .ArrayIndex = .{ .array = source, .index = idx_node } };

                // Apply default with ??
                const value = if (default_val) |dv| blk: {
                    const nullish = try this.allocator.create(ast.Node);
                    nullish.* = .{ .BinaryExpression = .{
                        .left = access,
                        .operator = .Nullish,
                        .right = dv,
                    } };
                    break :blk nullish;
                } else access;

                const decl = try this.makeBindNode(bind_name, value, decl_mode);
                try stmts.append(this.allocator, decl);

                idx += 1;

                if (this.current_token.type == .Comma) {
                    this.nextToken();
                } else if (this.current_token.type != .RBracket) {
                    return error.ExpectedCommaOrRBracket;
                }
            }
            this.nextToken(); // consume ']'
        } else {
            // Object pattern: { x, y: renamed, z = 10, ...rest }
            while (this.current_token.type != .RBrace) {
                // Rest element: ...restName
                if (this.current_token.type == .DotDotDot) {
                    this.nextToken(); // consume '...'
                    const bind_name = this.current_token.literal;
                    this.nextToken(); // consume name

                    const decl = try this.makeBindNode(bind_name, source, decl_mode);
                    try stmts.append(this.allocator, decl);

                    if (this.current_token.type == .Comma) this.nextToken();
                    continue;
                }

                // Parse property key
                if (!isPropertyName(this.current_token.type) and
                    this.current_token.type != .String and
                    this.current_token.type != .Integer and
                    this.current_token.type != .Float)
                {
                    return error.ExpectedPropertyName;
                }
                const prop_name = this.current_token.literal;
                this.nextToken(); // consume key

                if (this.current_token.type == .Colon) {
                    this.nextToken(); // consume ':'

                    // Nested pattern: { propName : { innerPat } } or { propName : [ innerPat ] }
                    if (this.current_token.type == .LBrace or this.current_token.type == .LBracket) {
                        // Build access: source.prop_name
                        const sub_source = try this.allocator.create(ast.Node);
                        sub_source.* = .{ .MemberAccess = .{ .object = source, .property = prop_name } };

                        // Create a temp to hold the sub-source so we can apply
                        // a whole-pattern default after the nested pattern is parsed.
                        const inner_temp_name = try this.genDestTempName();
                        const inner_temp_ident = try this.makeIdentNode(inner_temp_name);
                        const saved_stmts_len = stmts.items.len;
                        try this.parseDestructuredPattern(inner_temp_ident, stmts, decl_mode);

                        // Handle nested whole-pattern default: { a: { b, c } = defaultValue }
                        var nested_default: ?*ast.Node = null;
                        if (this.current_token.type == .Assign) {
                            this.nextToken(); // consume '='
                            nested_default = try this.parseExpression();
                        }

                        // Build: var _destN = sub_source ?? defaultValue  (or just sub_source)
                        const inner_value: *ast.Node = if (nested_default) |def| blk: {
                            const nullish = try this.allocator.create(ast.Node);
                            nullish.* = .{ .BinaryExpression = .{
                                .left = sub_source,
                                .operator = .Nullish,
                                .right = def,
                            } };
                            break :blk nullish;
                        } else sub_source;
                        const inner_decl = try this.allocator.create(ast.Node);
                        inner_decl.* = .{ .VariableDeclaration = .{ .name = inner_temp_name, .value = inner_value } };
                        try stmts.insert(this.allocator, saved_stmts_len, inner_decl);

                        if (this.current_token.type == .Comma) {
                            this.nextToken();
                        } else if (this.current_token.type != .RBrace) {
                            return error.ExpectedCommaOrRBrace;
                        }
                        continue;
                    }

                    // Rename: propName : bindName
                    const bind_name = this.current_token.literal;
                    this.nextToken(); // consume binding name

                    var default_val: ?*ast.Node = null;
                    if (this.current_token.type == .Assign) {
                        this.nextToken();
                        default_val = try this.parseExpression();
                    }

                    const access = try this.allocator.create(ast.Node);
                    access.* = .{ .MemberAccess = .{ .object = source, .property = prop_name } };

                    const value = if (default_val) |dv| blk: {
                        const nullish = try this.allocator.create(ast.Node);
                        nullish.* = .{ .BinaryExpression = .{
                            .left = access,
                            .operator = .Nullish,
                            .right = dv,
                        } };
                        break :blk nullish;
                    } else access;

                    const decl = try this.makeBindNode(bind_name, value, decl_mode);
                    try stmts.append(this.allocator, decl);

                    if (this.current_token.type == .Comma) {
                        this.nextToken();
                    } else if (this.current_token.type != .RBrace) {
                        return error.ExpectedCommaOrRBrace;
                    }
                    continue;
                }

                // Shorthand: { propName } — binding name = property name
                const bind_name = prop_name;

                var default_val: ?*ast.Node = null;
                if (this.current_token.type == .Assign) {
                    this.nextToken();
                    default_val = try this.parseExpression();
                }

                const access = try this.allocator.create(ast.Node);
                access.* = .{ .MemberAccess = .{ .object = source, .property = prop_name } };

                const value = if (default_val) |dv| blk: {
                    const nullish = try this.allocator.create(ast.Node);
                    nullish.* = .{ .BinaryExpression = .{
                        .left = access,
                        .operator = .Nullish,
                        .right = dv,
                    } };
                    break :blk nullish;
                } else access;

                const decl = try this.makeBindNode(bind_name, value, decl_mode);
                try stmts.append(this.allocator, decl);

                if (this.current_token.type == .Comma) {
                    this.nextToken();
                } else if (this.current_token.type != .RBrace) {
                    return error.ExpectedCommaOrRBrace;
                }
            }
            this.nextToken(); // consume '}'
        }
    }

    /// Parse a destructuring assignment: [a, b] = expr  or  ({x, y} = expr).
    /// The calling context has already determined this is a destructuring assignment
    /// (not a declaration or expression). Returns a BlockStatement containing:
    /// [var _dest0 = rhs, a = _dest0[0], b = _dest0[1], ...].
    fn parseDestructuredAssign(this: *Parser) !*ast.Node {
        var stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 8);
        defer stmts.deinit(this.allocator);

        const temp_name = try this.genDestTempName();
        const temp_ident = try this.makeIdentNode(temp_name);

        // Parse the pattern recursively (decl_mode=false for Assignment nodes)
        try this.parseDestructuredPattern(temp_ident, &stmts, false);

        // Expect '='
        if (this.current_token.type != .Assign) return error.ExpectedAssign;
        this.nextToken();

        // Parse RHS
        const rhs = try this.parseExpression();

        // Build temp decl: var _dest0 = <rhs>
        const temp_decl = try this.allocator.create(ast.Node);
        temp_decl.* = .{ .VariableDeclaration = .{ .name = temp_name, .value = rhs } };

        // Build BlockStatement: [temp_decl, binding1, binding2, ...]
        var all_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, stmts.items.len + 1);
        defer all_stmts.deinit(this.allocator);
        try all_stmts.append(this.allocator, temp_decl);
        for (stmts.items) |s| try all_stmts.append(this.allocator, s);
        // The RHS value (stored in temp) is the return value of the assignment expression.
        try all_stmts.append(this.allocator, temp_ident);

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BlockStatement = .{ .statements = try all_stmts.toOwnedSlice(this.allocator) } };
        return node;
    }

    /// Parse a parenthesized destructuring assignment: ({x, y} = expr) or ([a, b] = expr).
    /// Consumes '(', the pattern, '=', the RHS expression, and the closing ')'.
    fn parseParenthesizedDestructuredAssign(this: *Parser) !*ast.Node {
        this.nextToken(); // consume '('

        var stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 8);
        defer stmts.deinit(this.allocator);

        const temp_name = try this.genDestTempName();
        const temp_ident = try this.makeIdentNode(temp_name);

        // Parse the pattern recursively (decl_mode=false for Assignment nodes)
        try this.parseDestructuredPattern(temp_ident, &stmts, false);

        // Expect '=' (the pattern is directly followed by =, NOT by ')',
        // because in ({a} = expr) the closing ) is at the very end)
        if (this.current_token.type != .Assign) return error.ExpectedAssign;
        this.nextToken();

        // Parse RHS
        const rhs = try this.parseExpression();

        // Expect ')' — the closing paren of the parenthesized expression
        if (this.current_token.type != .RParen) return error.ExpectedRParen;
        this.nextToken(); // consume ')'

        // Build temp decl: var _dest0 = <rhs>
        const temp_decl = try this.allocator.create(ast.Node);
        temp_decl.* = .{ .VariableDeclaration = .{ .name = temp_name, .value = rhs } };

        // Build BlockStatement: [temp_decl, binding1, binding2, ..., temp_ident]
        var all_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, stmts.items.len + 2);
        defer all_stmts.deinit(this.allocator);
        try all_stmts.append(this.allocator, temp_decl);
        for (stmts.items) |s| try all_stmts.append(this.allocator, s);
        // The RHS value (stored in temp) is the return value of the assignment expression.
        try all_stmts.append(this.allocator, temp_ident);

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BlockStatement = .{ .statements = try all_stmts.toOwnedSlice(this.allocator) } };
        return node;
    }

    fn parseConstantDeclaration(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'const'
        if (this.current_token.type == .LBracket or this.current_token.type == .LBrace) {
            return this.parseDestructuredDecl(.Const);
        }
        const name = this.current_token.literal;
        this.nextToken(); // consume identifier
        this.nextToken(); // consume '='
        const value = try this.parseExpression();
        if (this.current_token.type == .Semicolon) this.nextToken();
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ConstantDeclaration = .{
            .name = name,
            .value = value,
        } };
        return node;
    }

    fn parseVariableDeclaration(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'var'
        if (this.current_token.type == .LBracket or this.current_token.type == .LBrace) {
            return this.parseDestructuredDecl(.Var);
        }
        const name = this.current_token.literal;
        this.nextToken(); // consume identifier
        this.nextToken(); // consume '='
        const value = try this.parseExpression();
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .VariableDeclaration = .{
            .name = name,
            .value = value,
        } };
        return node;
    }

    fn parseLetDeclaration(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'let'
        if (this.current_token.type == .LBracket or this.current_token.type == .LBrace) {
            return this.parseDestructuredDecl(.Let);
        }
        const name = this.current_token.literal;
        this.nextToken(); // consume identifier
        this.nextToken(); // consume '='
        const value = try this.parseExpression();
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .LetDeclaration = .{
            .name = name,
            .value = value,
        } };
        return node;
    }

    fn parseBlockStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume '{'
        var statements = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 8);
        defer statements.deinit(this.allocator);

        while (this.current_token.type != .RBrace and this.current_token.type != .EOF) {
            const stmt = try this.parseStatement();
            try statements.append(this.allocator, stmt);
            // Consume semicolon if present
            if (this.current_token.type == .Semicolon) {
                this.nextToken();
            }
        }

        this.nextToken(); // consume '}'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BlockStatement = .{
            .statements = try statements.toOwnedSlice(this.allocator),
        } };
        return node;
    }

    fn parsePrecedece(this: *Parser, precedence: ast.Precedence) !*ast.Node {
        var left = try this.parsePrimary();

        while (@backingInt(precedence) < @backingInt(ast.getTokenPrecedence(this.current_token.type))) {
            const op = this.current_token.type;
            this.nextToken();
            var next_precedence = ast.getTokenPrecedence(op);
            // Right-associative operators take their right-hand side one
            // precedence level lower, so the recursion binds to the right.
            if (isRightAssociative(op) and @backingInt(next_precedence) > 0) {
                next_precedence = @fromBackingInt(@intCast(@backingInt(next_precedence) - 1));
            }
            const right = try this.parsePrecedece(next_precedence);

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .BinaryExpression = .{
                .left = left,
                .operator = op,
                .right = right,
            } };

            left = node;
        }

        // Ternary operator: `condition ? consequent : alternate`.
        // We allow the ternary at `.lowest` and `.Assign` precedence levels.
        // At `.lowest` it acts as the top-level expression (all higher-precedence
        // binary operators have already been folded into `left`). At `.Assign` it
        // lets us parse the RHS of an assignment as a full ternary expression,
        // e.g. `q = (p % 2 == 0) ? q + 1 : q - 1` must parse as
        // `q = ((p % 2 == 0) ? q + 1 : q - 1)` rather than
        // `(q = (p % 2 == 0)) ? q + 1 : q - 1`.
        if (@backingInt(precedence) <= @backingInt(ast.Precedence.Assign) and this.current_token.type == .Question) {
            this.nextToken(); // consume '?'
            const consequent = try this.parsePrecedece(.lowest);
            if (this.current_token.type != .Colon) {
                ast.freeAst(this.allocator, consequent);
                ast.freeAst(this.allocator, left);
                return error.ExpectedColon;
            }
            this.nextToken(); // consume ':'
            const alternate = try this.parsePrecedece(.lowest);

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ConditionalExpression = .{
                .condition = left,
                .consequent = consequent,
                .alternate = alternate,
            } };
            return node;
        }

        return left;
    }

    fn parsePrimary(this: *Parser) !*ast.Node {
        var base: *ast.Node = undefined;
        switch (this.current_token.type) {
            .Integer => base = try this.parseIntegerLiteral(),
            .Float => base = try this.parseFloatLiteral(),
            .BigInt => base = try this.parseBigIntLiteral(),
            .String => base = try this.parseStringLiteral(),
            .TemplateString => base = try this.parseTemplateString(),
            .True => base = try this.parseBooleanLiteral(true),
            .False => base = try this.parseBooleanLiteral(false),
            .Null, .Undefined => {
                const node = try this.allocator.create(ast.Node);
                if (this.current_token.type == .Null) {
                    node.* = .{ .NullLiteral = .{} };
                } else {
                    node.* = .{ .VoidLiteral = .{} };
                }
                this.nextToken();
                base = node;
            },
            .LBracket => {
                // Try array destructuring assignment in expression context: [a, b] = expr
                // Use backtracking: save state, try parsing as destructured assign;
                // if it doesn't end with '=', backtrack and parse as array literal.
                const saved_lexer_expr = this.lexer.*;
                const saved_current_expr = this.current_token;
                const saved_peek_expr = this.peek_token;

                if (this.parseDestructuredAssign()) |result| {
                    return result;
                } else |_| {
                    this.lexer.* = saved_lexer_expr;
                    this.current_token = saved_current_expr;
                    this.peek_token = saved_peek_expr;
                    base = try this.parseArrayLiteral();
                }
            },
            .Class => base = try this.parseClass(false),
            .Super => {
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .Identifier = .{ .name = "super" } };
                this.nextToken();
                base = node;
            },
            .Regex => {
                // A regex literal is sugar for the RegExp constructor: the
                // pattern and flags are passed as raw strings so backslashes
                // keep their literal meaning.
                const pattern_token = this.current_token;
                this.nextToken(); // consume the regex literal
                const callee = try this.allocator.create(ast.Node);
                callee.* = .{ .Identifier = .{ .name = "RegExp" } };
                const args = try this.allocator.alloc(*ast.Node, 2);
                args[0] = try this.allocator.create(ast.Node);
                args[0].* = .{ .StringLiteral = .{ .value = pattern_token.literal } };
                args[1] = try this.allocator.create(ast.Node);
                args[1].* = .{ .StringLiteral = .{ .value = pattern_token.regex_flags } };
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .NewExpression = .{ .callee = callee, .arguments = args } };
                base = node;
            },
            .Identifier => {
                base = try this.parseIdentifier();
                // Detect single-param arrow: identifier followed immediately by `=>`.
                if (this.current_token.type == .Arrow) {
                    const param_name = base.Identifier.name;
                    this.nextToken(); // consume '=>'
                    const body = if (this.current_token.type == .LBrace) try this.parseBlockStatement() else try this.parseExpression();
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .ArrowFunction = .{
                        .parameters = try this.allocator.dupe([]const u8, &.{param_name}),
                        .body = body,
                    } };
                    return node;
                }
            },
            .LBrace => {
                base = try this.parseObjectLiteral();
            },
            .Fn => {
                base = try this.parseFunctionDeclaration();
            },
            .Yield => {
                base = try this.parseYieldExpression();
            },
            .Await => {
                this.nextToken(); // consume 'await'
                const value = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .AwaitExpression = .{ .value = value } };
                base = node;
            },
            .Async => {
                if (this.isAsyncSyntaxStart()) {
                    base = try this.parseAsyncFunctionOrArrow();
                } else {
                    this.nextToken(); // consume contextual keyword as identifier
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .Identifier = .{ .name = "async" } };
                    base = node;
                }
            },
            .New => {
                this.nextToken(); // consume 'new'
                // Parse just the callee identifier, not a full primary expression
                if (this.current_token.type != .Identifier) {
                    return error.ExpectedIdentifier;
                }
                const callee_name = this.current_token.literal;
                this.nextToken(); // consume identifier
                const callee = try this.allocator.create(ast.Node);
                callee.* = .{ .Identifier = .{ .name = callee_name } };
                var arguments: []*ast.Node = &.{};
                if (this.current_token.type == .LParen) {
                    this.nextToken(); // consume '('
                    var args = try this.parseCallArguments();
                    defer args.deinit(this.allocator);
                    arguments = try args.toOwnedSlice(this.allocator);
                    this.nextToken(); // consume ')'
                }
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .NewExpression = .{
                    .callee = callee,
                    .arguments = arguments,
                } };
                base = node;
            },
            .LParen => {
                // Try arrow function first; if it fails, try destructuring;
                // if that also fails, parse as grouped expression.
                const saved_lexer = this.lexer.*;
                const saved_current = this.current_token;
                const saved_peek = this.peek_token;

                if (this.parseArrowFunction()) |result| {
                    base = result;
                } else |_| {
                    this.lexer.* = saved_lexer;
                    this.current_token = saved_current;
                    this.peek_token = saved_peek;

                    // Try parenthesized destructuring: ({a, b} = expr) or ([a, b] = expr)
                    if (this.parseParenthesizedDestructuredAssign()) |result| {
                        return result;
                    } else |_| {
                        // Parse as grouped expression
                        this.lexer.* = saved_lexer;
                        this.current_token = saved_current;
                        this.peek_token = saved_peek;
                        this.nextToken(); // consume '('
                        base = try this.parseCommaExpression();
                        if (this.current_token.type != .RParen) {
                            return error.ExpectedRParen;
                        }
                        this.nextToken(); // consume ')'
                    }
                }
            },
            .Increment => {
                // Handle pre-increment operator like ++i, ++obj.x, ++arr[0]
                this.nextToken(); // consume '++'
                const operand = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .UpdateExpression = .{
                    .operand = operand,
                    .prefix = true,
                    .operator = .Increment,
                } };
                return node;
            },
            .Minus => {
                // Unary minus: -literal, -identifier, -(expr), etc.
                this.nextToken();
                if (this.current_token.type == .Integer) {
                    const node = try this.allocator.create(ast.Node);
                    const value = try std.fmt.parseInt(i64, this.current_token.literal, 10);
                    // `-0` must stay a negative zero float; negating the
                    // integer zero would lose the sign.
                    if (value == 0) {
                        node.* = .{ .FloatLiteral = .{ .value = -0.0 } };
                    } else {
                        node.* = .{ .IntegerLiteral = .{ .value = -value } };
                    }
                    this.nextToken();
                    return node;
                } else if (this.current_token.type == .Float) {
                    const node = try this.allocator.create(ast.Node);
                    const value = try std.fmt.parseFloat(f64, this.current_token.literal);
                    node.* = .{ .FloatLiteral = .{ .value = -value } };
                    this.nextToken();
                    return node;
                } else {
                    // Generic unary minus: build `0 - operand` so the runtime
                    // can rely on the existing BinaryExpression path. The
                    // operand itself is parsed as a primary expression so we
                    // support things like `-n`, `-obj.value`, `-arr[0]`,
                    // `-(a + b)`, etc.
                    const operand = try this.parsePrimary();
                    return try this.parseBinaryExpression(.{ .IntegerLiteral = .{ .value = 0 } }, .Minus, operand.*);
                }
            },
            .Decrement => {
                // Handle pre-decrement operator like --i, --obj.x, --arr[0]
                this.nextToken(); // consume '--'
                const operand = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .UpdateExpression = .{
                    .operand = operand,
                    .prefix = true,
                    .operator = .Decrement,
                } };
                return node;
            },
            .Not => {
                // Handle logical NOT operator like !x
                this.nextToken();
                const expr = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .BinaryExpression = .{
                    .left = try this.allocator.create(ast.Node),
                    .operator = .Not,
                    .right = expr,
                } };
                node.BinaryExpression.left.* = .{ .BooleanLiteral = .{ .value = false } };
                return node;
            },
            .Import => {
                // import.meta expression
                this.nextToken(); // consume 'import'
                if (this.current_token.type == .Dot and this.peek_token.type == .Identifier and
                    std.mem.eql(u8, this.peek_token.literal, "meta"))
                {
                    this.nextToken(); // consume '.'
                    this.nextToken(); // consume 'meta'
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .ImportMetaExpression = .{} };
                    base = node;
                } else {
                    // Dynamic import() not yet implemented
                    return error.UnexpectedToken;
                }
            },
            .TypeOf => {
                // Handle typeof operator: typeof expr
                this.nextToken(); // consume 'typeof'
                const expr = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .TypeOfExpression = .{ .operand = expr } };
                return node;
            },
            .Delete => {
                // Handle delete operator: delete obj.prop
                this.nextToken(); // consume 'delete'
                const expr = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .DeleteExpression = .{ .operand = expr } };
                return node;
            },
            .Void => {
                // Handle void operator: void expr
                this.nextToken(); // consume 'void'
                const expr = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .VoidExpression = .{ .operand = expr } };
                return node;
            },
            .BitNot => {
                // Handle bitwise NOT operator like ~x
                this.nextToken();
                const expr = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .BinaryExpression = .{
                    .left = try this.allocator.create(ast.Node),
                    .operator = .BitNot,
                    .right = expr,
                } };
                node.BinaryExpression.left.* = .{ .IntegerLiteral = .{ .value = 0 } };
                return node;
            },
            else => return error.UnexpectedToken,
        }

        // Postfix chain: .prop, [index], (args), ?.prop, ?.[index], ?.(args)
        while (true) {
            if (this.current_token.type == .QuestionDot) {
                base = try this.parseOptionalChainPostfix(base);
            } else if (this.current_token.type == .LBracket and base.* == .OptionalChain) {
                base = try this.parseChainIndexPostfix(base);
            } else if (this.current_token.type == .Dot and base.* == .OptionalChain) {
                base = try this.parseChainDotPostfix(base);
            } else if (this.current_token.type == .LBracket) {
                base = try this.parseArrayIndex(base);
            } else if (this.current_token.type == .Dot) {
                base = try this.parseMemberAccessOrCall(base);
            } else if (this.current_token.type == .LParen and base.* == .OptionalChain) {
                base = try this.parseChainCallPostfix(base);
            } else if (this.current_token.type == .LParen) {
                base = try this.parseFunctionCallFromBase(base);
            } else {
                break;
            }
        }

        // Post-increment: i++, obj.x++, arr[0]++
        if (this.current_token.type == .Increment and isValidLhs(base)) {
            this.nextToken(); // consume ++
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .UpdateExpression = .{
                .operand = base,
                .prefix = false,
                .operator = .Increment,
            } };
            return node;
        }

        // Post-decrement: i--, obj.x--, arr[0]--
        if (this.current_token.type == .Decrement and isValidLhs(base)) {
            this.nextToken(); // consume --
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .UpdateExpression = .{
                .operand = base,
                .prefix = false,
                .operator = .Decrement,
            } };
            return node;
        }

        return base;
    }

    fn isValidLhs(node: *const ast.Node) bool {
        return switch (node.*) {
            .Identifier, .MemberAccess, .ArrayIndex => true,
            else => false,
        };
    }

    fn parseBinaryExpression(this: *Parser, left: ast.Node, op: TokenType, right: ast.Node) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BinaryExpression = .{
            .left = try this.allocator.create(ast.Node),
            .operator = op,
            .right = try this.allocator.create(ast.Node),
        } };
        node.BinaryExpression.left.* = left;
        node.BinaryExpression.right.* = right;
        return node;
    }

    fn parseIntegerLiteral(this: *Parser) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        const literal = this.current_token.literal;
        // Detect base from prefix: 0x=hex, 0o=octal, 0b=binary, otherwise decimal
        const base: u8 = if (literal.len >= 2 and literal[0] == '0') switch (literal[1]) {
            'x', 'X' => 16,
            'o', 'O' => 8,
            'b', 'B' => 2,
            else => 10,
        } else 10;
        const digits = if (base != 10) literal[2..] else literal;
        const value = try std.fmt.parseInt(i64, digits, base);
        node.* = .{ .IntegerLiteral = .{ .value = value } };
        this.nextToken();
        return node;
    }

    fn parseFloatLiteral(this: *Parser) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        const value = try std.fmt.parseFloat(f64, this.current_token.literal);
        node.* = .{ .FloatLiteral = .{ .value = value } };
        this.nextToken();
        return node;
    }

    fn parseBigIntLiteral(this: *Parser) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        // Literal already has the trailing 'n' stripped by the lexer.
        const digits = try this.allocator.dupe(u8, this.current_token.literal);
        node.* = .{ .BigIntLiteral = .{ .value = digits } };
        this.nextToken();
        return node;
    }

    fn isHexDigit(c: u8) bool {
        return switch (c) {
            '0'...'9', 'a'...'f', 'A'...'F' => true,
            else => false,
        };
    }

    fn isHexDigits(slice: []const u8) bool {
        for (slice) |c| if (!isHexDigit(c)) return false;
        return true;
    }

    fn encodeSurrogate(cp: u21) [3]u8 {
        return [_]u8{
            @as(u8, 0xE0) | @as(u8, @intCast((cp >> 12) & 0x0F)),
            @as(u8, 0x80) | @as(u8, @intCast((cp >> 6) & 0x3F)),
            @as(u8, 0x80) | @as(u8, @intCast(cp & 0x3F)),
        };
    }

    fn parseStringLiteral(this: *Parser) !*ast.Node {
        const raw = this.current_token.literal;
        const node = try this.allocator.create(ast.Node);
        node.* = if (std.mem.indexOfScalar(u8, raw, '\\')) |_|
            .{ .StringLiteral = .{ .value = try this.processStringEscapes(raw) } }
        else
            .{ .StringLiteral = .{ .value = raw } };
        this.nextToken();
        return node;
    }

    /// Template literals are desugared into a left-associative `+` chain of
    /// string literals and expressions, so both engines work unchanged.
    fn parseTemplateString(this: *Parser) !*ast.Node {
        const raw = this.current_token.literal;
        if (std.mem.indexOf(u8, raw, "${") == null) {
            const node = try this.allocator.create(ast.Node);
            node.* = if (std.mem.indexOfScalar(u8, raw, '\\')) |_|
                .{ .StringLiteral = .{ .value = try this.processStringEscapes(raw) } }
            else
                .{ .StringLiteral = .{ .value = raw } };
            this.nextToken();
            return node;
        }

        var chain: ?*ast.Node = null;
        var lit_start: usize = 0;
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '\\') {
                i += if (i + 1 < raw.len) 2 else 1;
                continue;
            }
            if (raw[i] == '$' and i + 1 < raw.len and raw[i + 1] == '{') {
                chain = try this.templateAppendString(chain, raw[lit_start..i]);
                const expr_start = i + 2;
                const close = findTemplateExprEnd(raw, expr_start) orelse return error.UnterminatedTemplate;
                chain = try this.templateAppendExpression(chain, raw[expr_start..close]);
                i = close + 1;
                lit_start = i;
                continue;
            }
            i += 1;
        }
        chain = try this.templateAppendString(chain, raw[lit_start..]);
        this.nextToken();
        return chain.?;
    }

    fn templatePlus(this: *Parser, left: *ast.Node, right: *ast.Node) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BinaryExpression = .{ .left = left, .operator = .Plus, .right = right } };
        return node;
    }

    fn templateAppendString(this: *Parser, chain: ?*ast.Node, text: []const u8) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        node.* = if (std.mem.indexOfScalar(u8, text, '\\')) |_|
            .{ .StringLiteral = .{ .value = try this.processStringEscapes(text) } }
        else
            .{ .StringLiteral = .{ .value = text } };
        if (chain) |left| return try this.templatePlus(left, node);
        return node;
    }

    fn templateAppendExpression(this: *Parser, chain: ?*ast.Node, source: []const u8) !*ast.Node {
        var sub_lexer = Lexer.init(source);
        var sub = Parser{
            .lexer = &sub_lexer,
            .current_token = undefined,
            .peek_token = undefined,
            .allocator = this.allocator,
            .arena = this.arena,
            .arena_child = this.arena_child,
        };
        sub.nextToken();
        sub.nextToken();
        const expr = sub.parseCommaExpression() catch return error.InvalidTemplateExpression;
        if (sub.current_token.type != .EOF) return error.InvalidTemplateExpression;
        if (chain) |left| return try this.templatePlus(left, expr);
        const empty = try this.allocator.create(ast.Node);
        empty.* = .{ .StringLiteral = .{ .value = "" } };
        return try this.templatePlus(empty, expr);
    }

    fn processStringEscapes(this: *Parser, raw: []const u8) ![]const u8 {
        var buf = std.ArrayList(u8).initCapacity(this.allocator, raw.len) catch {
            return raw;
        };
        errdefer buf.deinit(this.allocator);
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '\\' and i + 1 < raw.len) {
                switch (raw[i + 1]) {
                    'n' => try buf.append(this.allocator, '\n'),
                    't' => try buf.append(this.allocator, '\t'),
                    'r' => try buf.append(this.allocator, '\r'),
                    '\\' => try buf.append(this.allocator, '\\'),
                    '\'' => try buf.append(this.allocator, '\''),
                    '"' => try buf.append(this.allocator, '"'),
                    '0' => try buf.append(this.allocator, 0),
                    'x' => {
                        if (i + 3 < raw.len and isHexDigits(raw[i + 2 .. i + 4])) {
                            const val = std.fmt.parseInt(u8, raw[i + 2 .. i + 4], 16) catch unreachable;
                            try buf.append(this.allocator, val);
                            i += 4;
                            continue;
                        }
                        try buf.append(this.allocator, '\\');
                        try buf.append(this.allocator, 'x');
                        i += 2;
                        continue;
                    },
                    'u' => {
                        // Handle \u{XXXXX} (braced code point)
                        if (i + 2 < raw.len and raw[i + 2] == '{') {
                            const close = std.mem.indexOfScalar(u8, raw[i + 3 ..], '}') orelse {
                                try buf.append(this.allocator, '\\');
                                try buf.append(this.allocator, 'u');
                                try buf.append(this.allocator, '{');
                                i += 3;
                                continue;
                            };
                            if (close > 0 and isHexDigits(raw[i + 3 .. i + 3 + close])) {
                                const cp = std.fmt.parseInt(u21, raw[i + 3 .. i + 3 + close], 16) catch unreachable;
                                var encoded: [4]u8 = undefined;
                                const len = std.unicode.utf8Encode(cp, &encoded) catch {
                                    try buf.append(this.allocator, '\\');
                                    try buf.append(this.allocator, 'u');
                                    try buf.append(this.allocator, '{');
                                    i += 3;
                                    continue;
                                };
                                try buf.appendSlice(this.allocator, encoded[0..len]);
                                i += 3 + close + 1;
                                continue;
                            }
                            try buf.append(this.allocator, '\\');
                            try buf.append(this.allocator, 'u');
                            try buf.append(this.allocator, '{');
                            i += 3;
                            continue;
                        }
                        if (i + 5 < raw.len and isHexDigits(raw[i + 2 .. i + 6])) {
                            const hi = std.fmt.parseInt(u21, raw[i + 2 .. i + 6], 16) catch unreachable;
                            if (hi >= 0xD800 and hi <= 0xDBFF and i + 11 < raw.len and raw[i + 6] == '\\' and raw[i + 7] == 'u' and isHexDigits(raw[i + 8 .. i + 12])) {
                                const lo = std.fmt.parseInt(u21, raw[i + 8 .. i + 12], 16) catch unreachable;
                                if (lo >= 0xDC00 and lo <= 0xDFFF) {
                                    const cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
                                    var encoded: [4]u8 = undefined;
                                    const len = std.unicode.utf8Encode(cp, &encoded) catch {
                                        try buf.append(this.allocator, '\\');
                                        try buf.append(this.allocator, 'u');
                                        i += 2;
                                        continue;
                                    };
                                    try buf.appendSlice(this.allocator, encoded[0..len]);
                                    i += 12;
                                    continue;
                                }
                            }
                            if (hi >= 0xD800 and hi <= 0xDFFF) {
                                try buf.appendSlice(this.allocator, &encodeSurrogate(hi));
                            } else {
                                var encoded: [4]u8 = undefined;
                                const len = std.unicode.utf8Encode(hi, &encoded) catch {
                                    try buf.append(this.allocator, '\\');
                                    try buf.append(this.allocator, 'u');
                                    i += 2;
                                    continue;
                                };
                                try buf.appendSlice(this.allocator, encoded[0..len]);
                            }
                            i += 6;
                            continue;
                        }
                        try buf.append(this.allocator, '\\');
                        try buf.append(this.allocator, 'u');
                        i += 2;
                        continue;
                    },
                    else => {
                        try buf.append(this.allocator, raw[i + 1]);
                        i += 2;
                        continue;
                    },
                }
                i += 2;
            } else {
                try buf.append(this.allocator, raw[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice(this.allocator);
    }

    fn parseBooleanLiteral(this: *Parser, value: bool) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BooleanLiteral = .{ .value = value } };
        this.nextToken();
        return node;
    }

    fn parseArrayLiteral(this: *Parser) anyerror!*ast.Node {
        this.nextToken(); // consume '['

        var elements = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 8);
        defer elements.deinit(this.allocator);

        while (this.current_token.type != .RBracket) {
            if (this.current_token.type == .Comma or this.current_token.type == .RBracket) {
                const elision = try this.allocator.create(ast.Node);
                elision.* = .{ .Elision = {} };
                try elements.append(this.allocator, elision);
                if (this.current_token.type == .RBracket) break;
                this.nextToken(); // consume ','
                continue;
            }

            const element = if (this.current_token.type == .DotDotDot) blk: {
                this.nextToken(); // consume '...'
                const expr = try this.parseExpression();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .SpreadExpression = .{ .value = expr } };
                break :blk node;
            } else try this.parseExpression();

            try elements.append(this.allocator, element);

            if (this.current_token.type == .RBracket) break;

            if (this.current_token.type != .Comma) {
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }

        this.nextToken(); // consume ']'

        const node = try this.allocator.create(ast.Node);
        node.* = .{
            .ArrayLiteral = .{
                .elements = try elements.toOwnedSlice(this.allocator),
            },
        };
        return node;
    }

    fn parseMethodProperty(this: *Parser, key: []const u8, key_expr: ?*ast.Node) !ast.Property {
        // ES2015 method shorthand: `name(params) { ... }` inside an object
        // literal. The function is a normal (non-arrow) function so `this`
        // binds dynamically when it is called as a method.
        this.nextToken(); // consume '('
        const params = try this.parseFunctionParameters();
        if (this.current_token.type != .RParen) return error.ExpectedRParen;
        this.nextToken(); // consume ')'
        const body = try this.parseFunctionBody();
        const final_body = if (params.destructured_preamble) |preamble| blk: {
            if (body.* == .BlockStatement) {
                var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, body.BlockStatement.statements.len + 1);
                defer new_stmts.deinit(this.allocator);
                try new_stmts.append(this.allocator, preamble);
                for (body.BlockStatement.statements) |s| try new_stmts.append(this.allocator, s);
                this.allocator.free(body.BlockStatement.statements);
                const wrapped = try this.allocator.create(ast.Node);
                wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                break :blk wrapped;
            } else {
                var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 2);
                defer new_stmts.deinit(this.allocator);
                try new_stmts.append(this.allocator, preamble);
                const ret = try this.allocator.create(ast.Node);
                ret.* = .{ .ReturnStatement = .{ .value = body } };
                try new_stmts.append(this.allocator, ret);
                const wrapped = try this.allocator.create(ast.Node);
                wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                break :blk wrapped;
            }
        } else body;
        const fn_node = try this.allocator.create(ast.Node);
        fn_node.* = .{ .FunctionDeclaration = .{
            .name = "",
            .parameters = params.names,
            .body = final_body,
            .rest_param = params.rest_param,
            .param_defaults = params.defaults,
        } };
        return .{ .key = key, .value = fn_node, .key_expr = key_expr };
    }

    fn parseObjectLiteral(this: *Parser) anyerror!*ast.Node {
        this.nextToken(); // consume '{'
        var properties = try std.ArrayList(ast.Property).initCapacity(this.allocator, 8);
        defer properties.deinit(this.allocator);

        while (this.current_token.type != .RBrace and this.current_token.type != .EOF) {
            // Async method shorthand: `async name() {}`. `async()` remains a
            // method literally named "async", and `async: value` a property.
            var is_async_method = false;
            if (this.current_token.type == .Async and this.peek_token.type != .LParen and this.peek_token.type != .Colon) {
                is_async_method = true;
                this.nextToken();
            }

            // Handle spread property: {...expr}
            if (this.current_token.type == .DotDotDot) {
                this.nextToken(); // consume '...'
                const expr = try this.parseExpression();
                const spread_node = try this.allocator.create(ast.Node);
                spread_node.* = .{ .SpreadExpression = .{ .value = expr } };
                try properties.append(this.allocator, .{ .key = "", .value = spread_node });

                if (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                } else if (this.current_token.type != .RBrace) {
                    return error.ExpectedCommaOrRBrace;
                }
                continue;
            }

            // Handle computed property key: [expr]
            if (this.current_token.type == .LBracket) {
                this.nextToken(); // consume '['
                const key_expr = try this.parseExpression();
                if (this.current_token.type != .RBracket) return error.ExpectedRBracket;
                this.nextToken(); // consume ']'

                if (this.current_token.type == .LParen) {
                    var prop = try this.parseMethodProperty("", key_expr);
                    if (is_async_method and prop.value.* == .FunctionDeclaration) prop.value.FunctionDeclaration.is_async = true;
                    try properties.append(this.allocator, prop);
                } else {
                    if (this.current_token.type != .Colon) return error.ExpectedColon;
                    this.nextToken(); // consume ':'
                    const value = try this.parseExpression();
                    try properties.append(this.allocator, .{ .key = "", .value = value, .key_expr = key_expr });
                }

                if (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                } else if (this.current_token.type != .RBrace) {
                    return error.ExpectedCommaOrRBrace;
                }
                continue;
            }

            // ES2015 §13.2.5.4: a property name in an object literal may be
            // an IdentifierName (which includes reserved words like `fn`,
            // `return`, `if`, ...), a string literal, or a numeric literal.
            // `isPropertyName(tok_type)` already covers IdentifierName (we
            // use it for member-access keys too), so we delegate to it for
            // the Identifier-or-keyword branch. The String / Integer / Float
            // cases stay explicit because their semantics are "use the
            // literal as the key" (e.g. `{ "fn": 1 }` vs `{ fn: 1 }`).
            const key = switch (this.current_token.type) {
                .String, .Integer, .Float => this.current_token.literal,
                else => blk: {
                    if (!isPropertyName(this.current_token.type)) return error.ExpectedPropertyName;
                    break :blk this.current_token.literal;
                },
            };
            this.nextToken(); // consume key

            // ES2015 accessor properties: `get name() { ... }` /
            // `set name(value) { ... }`. The first key we consumed is the
            // `get`/`set` keyword, so a following colon means it is a normal
            // property literally named "get"/"set".
            if ((std.mem.eql(u8, key, "get") or std.mem.eql(u8, key, "set")) and
                this.current_token.type != .Colon)
            {
                const accessor_key = switch (this.current_token.type) {
                    .String, .Integer, .Float => this.current_token.literal,
                    else => blk: {
                        if (!isPropertyName(this.current_token.type)) return error.ExpectedPropertyName;
                        break :blk this.current_token.literal;
                    },
                };
                this.nextToken(); // consume accessor name

                if (this.current_token.type != .LParen) return error.ExpectedLParen;
                this.nextToken(); // consume '('
                const params = try this.parseFunctionParameters();
                if (this.current_token.type != .RParen) return error.ExpectedRParen;
                this.nextToken(); // consume ')'

                const body = try this.parseFunctionBody();
                const final_body = if (params.destructured_preamble) |preamble| blk: {
                    if (body.* == .BlockStatement) {
                        var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, body.BlockStatement.statements.len + 1);
                        defer new_stmts.deinit(this.allocator);
                        try new_stmts.append(this.allocator, preamble);
                        for (body.BlockStatement.statements) |s| try new_stmts.append(this.allocator, s);
                        this.allocator.free(body.BlockStatement.statements);
                        const wrapped = try this.allocator.create(ast.Node);
                        wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                        break :blk wrapped;
                    } else {
                        var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 2);
                        defer new_stmts.deinit(this.allocator);
                        try new_stmts.append(this.allocator, preamble);
                        const ret = try this.allocator.create(ast.Node);
                        ret.* = .{ .ReturnStatement = .{ .value = body } };
                        try new_stmts.append(this.allocator, ret);
                        const wrapped = try this.allocator.create(ast.Node);
                        wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                        break :blk wrapped;
                    }
                } else body;

                const fn_node = try this.allocator.create(ast.Node);
                fn_node.* = .{ .FunctionDeclaration = .{
                    .name = "",
                    .parameters = params.names,
                    .body = final_body,
                    .rest_param = params.rest_param,
                } };
                try properties.append(this.allocator, .{
                    .key = accessor_key,
                    .value = fn_node,
                    .kind = if (std.mem.eql(u8, key, "get")) .get else .set,
                });

                if (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                } else if (this.current_token.type != .RBrace) {
                    return error.ExpectedCommaOrRBrace;
                }
                continue;
            }

            if (this.current_token.type == .LParen) {
                var prop = try this.parseMethodProperty(key, null);
                if (is_async_method and prop.value.* == .FunctionDeclaration) prop.value.FunctionDeclaration.is_async = true;
                try properties.append(this.allocator, prop);

                if (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                } else if (this.current_token.type != .RBrace) {
                    return error.ExpectedCommaOrRBrace;
                }
                continue;
            }

            if (this.current_token.type != .Colon) return error.ExpectedColon;
            this.nextToken(); // consume ':'

            const value = try this.parseExpression();

            try properties.append(this.allocator, .{ .key = key, .value = value });

            if (this.current_token.type == .Comma) {
                this.nextToken(); // consume ','
            } else if (this.current_token.type != .RBrace) {
                return error.ExpectedCommaOrRBrace;
            }
        }

        if (this.current_token.type != .RBrace) return error.ExpectedRBrace;
        this.nextToken(); // consume '}'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ObjectLiteral = .{
            .properties = try properties.toOwnedSlice(this.allocator),
        } };
        return node;
    }

    fn parseIdentifier(this: *Parser) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .Identifier = .{ .name = this.current_token.literal } };
        this.nextToken();
        return node;
    }

    fn parseForLoop(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'for'
        var is_await = false;
        if (this.current_token.type == .Await) {
            is_await = true;
            this.nextToken(); // consume 'await'
        }
        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        // Check for for...of pattern: for (const/var/let identifier of expr)
        if (this.current_token.type == .Const or this.current_token.type == .Var or this.current_token.type == .Let) {
            // Save lexer state for backtracking
            const saved_lexer = this.lexer.*;
            const saved_current = this.current_token;
            const saved_peek = this.peek_token;

            const decl_kind = this.current_token.type;
            this.nextToken(); // consume const/var/let

            if (this.current_token.type == .Identifier) {
                const variable = this.current_token.literal;
                this.nextToken(); // consume identifier

                if (this.current_token.type == .Of) {
                    this.nextToken(); // consume 'of'
                    const iterable = try this.parseExpression();

                    if (this.current_token.type != .RParen) {
                        return error.ExpectedRParen;
                    }
                    this.nextToken(); // consume ')'

                    const body = try this.parseStatement();

                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .ForOfLoop = .{
                        .kind = switch (decl_kind) {
                            .Const => .Const,
                            .Var => .Var,
                            .Let => .Let,
                            else => unreachable,
                        },
                        .variable = variable,
                        .iterable = iterable,
                        .body = body,
                        .is_await = is_await,
                    } };
                    return node;
                }

                if (this.current_token.type == .In) {
                    if (is_await) return error.UnexpectedToken;
                    this.nextToken(); // consume 'in'
                    const object = try this.parseExpression();

                    if (this.current_token.type != .RParen) {
                        return error.ExpectedRParen;
                    }
                    this.nextToken(); // consume ')'

                    const body = try this.parseStatement();

                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .ForInLoop = .{
                        .kind = switch (decl_kind) {
                            .Const => .Const,
                            .Var => .Var,
                            .Let => .Let,
                            else => unreachable,
                        },
                        .variable = variable,
                        .object = object,
                        .body = body,
                    } };
                    return node;
                }
            } else if (this.current_token.type == .LBracket or this.current_token.type == .LBrace) {
                // Destructuring pattern in for...of: for (const [a, b] of iter) {}
                // Strategy: desugar to for (const _tmp of iter) { const [a, b] = _tmp; body }
                const dest_saved_lexer = this.lexer.*;
                const dest_saved_current = this.current_token;
                const dest_saved_peek = this.peek_token;

                var destr_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 8);

                const temp_name = try this.genDestTempName();
                const temp_ident = try this.makeIdentNode(temp_name);

                // Try to parse the destructuring pattern
                const pattern_ok = this.parseDestructuredPattern(temp_ident, &destr_stmts, true);
                if (pattern_ok) {
                    if (this.current_token.type == .Of) {
                        // For-of destructuring: for (const [a, b] of iter) { body }
                        this.nextToken(); // consume 'of'
                        const iterable = try this.parseExpression();

                        if (this.current_token.type != .RParen) {
                            return error.ExpectedRParen;
                        }
                        this.nextToken(); // consume ')'

                        const original_body = try this.parseStatement();

                        // Wrap body: { const [a, b] = _tmp; original_body }
                        var body_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, destr_stmts.items.len + 1);
                        defer body_stmts.deinit(this.allocator);
                        for (destr_stmts.items) |s| try body_stmts.append(this.allocator, s);
                        try body_stmts.append(this.allocator, original_body);

                        const new_body = try this.allocator.create(ast.Node);
                        new_body.* = .{ .BlockStatement = .{ .statements = try body_stmts.toOwnedSlice(this.allocator) } };

                        // Clean up the temp ArrayList (not the elements — they're now in BlockStatement)
                        destr_stmts.deinit(this.allocator);

                        const node = try this.allocator.create(ast.Node);
                        node.* = .{ .ForOfLoop = .{
                            .kind = switch (decl_kind) {
                                .Const => .Const,
                                .Var => .Var,
                                .Let => .Let,
                                else => unreachable,
                            },
                            .variable = temp_name,
                            .iterable = iterable,
                            .body = new_body,
                            .is_await = is_await,
                        } };
                        return node;
                    }

                    if (this.current_token.type == .In) {
                        if (is_await) return error.UnexpectedToken;
                        this.nextToken(); // consume 'in'
                        const object = try this.parseExpression();

                        if (this.current_token.type != .RParen) {
                            return error.ExpectedRParen;
                        }
                        this.nextToken(); // consume ')'

                        const original_body = try this.parseStatement();

                        // Wrap body: { const [a, b] = _tmp; original_body }
                        var body_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, destr_stmts.items.len + 1);
                        defer body_stmts.deinit(this.allocator);
                        for (destr_stmts.items) |s| try body_stmts.append(this.allocator, s);
                        try body_stmts.append(this.allocator, original_body);

                        const new_body = try this.allocator.create(ast.Node);
                        new_body.* = .{ .BlockStatement = .{ .statements = try body_stmts.toOwnedSlice(this.allocator) } };

                        destr_stmts.deinit(this.allocator);

                        const node = try this.allocator.create(ast.Node);
                        node.* = .{ .ForInLoop = .{
                            .kind = switch (decl_kind) {
                                .Const => .Const,
                                .Var => .Var,
                                .Let => .Let,
                                else => unreachable,
                            },
                            .variable = temp_name,
                            .object = object,
                            .body = new_body,
                        } };
                        return node;
                    }
                } else |_| {
                    // Pattern parsing failed, backtrack
                    destr_stmts.deinit(this.allocator);
                    this.lexer.* = dest_saved_lexer;
                    this.current_token = dest_saved_current;
                    this.peek_token = dest_saved_peek;
                }
            }

            // Not a for...of or for...in, restore state and fall through to regular for loop parsing
            this.lexer.* = saved_lexer;
            this.current_token = saved_current;
            this.peek_token = saved_peek;
        }

        // `for await` only supports the `of` form.
        if (is_await) return error.UnexpectedToken;

        // Parse initialization (optional) — supports comma-separated initializers.
        // For `var` and `let`, each binding may be initialized with `=` OR
        // intentionally left uninitialized (`for (var i; ...)` /
        // `for (let x;;)`). `const` always requires `=` per ES2015.
        var init_stmt: ?*ast.Node = null;
        if (this.current_token.type != .Semicolon) {
            if (this.current_token.type == .Var or this.current_token.type == .Let or this.current_token.type == .Const) {
                const decl_type = this.current_token.type;
                this.nextToken(); // consume 'var'/'let'/'const'

                var init_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 2);
                defer init_stmts.deinit(this.allocator);

                // Helper closure: build one decl node with name + optional value.
                // const still requires `=`; var/let allow either '=' or
                // a `;`/`)`/`/`/`{` boundary (no initializer).
                const build_decl = struct {
                    fn build(p: *Parser, kind: TokenType, name: []const u8) anyerror!*ast.Node {
                        const opt_value: ?*ast.Node = if (p.current_token.type == .Assign) blk: {
                            p.nextToken(); // consume '='
                            break :blk try p.parseExpression();
                        } else if (kind == .Const) {
                            return error.ExpectedAssign;
                        } else null;
                        const n = try p.allocator.create(ast.Node);
                        n.* = switch (kind) {
                            .Var => .{ .VariableDeclaration = .{ .name = name, .value = opt_value } },
                            .Let => .{ .LetDeclaration = .{ .name = name, .value = opt_value } },
                            .Const => .{ .ConstantDeclaration = .{ .name = name, .value = opt_value.? } },
                            else => unreachable,
                        };
                        return n;
                    }
                }.build;

                {
                    const name = this.current_token.literal;
                    this.nextToken(); // consume identifier
                    const n = try build_decl(this, decl_type, name);
                    try init_stmts.append(this.allocator, n);
                }

                while (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                    const name = this.current_token.literal;
                    this.nextToken(); // consume identifier
                    const n = try build_decl(this, decl_type, name);
                    try init_stmts.append(this.allocator, n);
                }

                if (init_stmts.items.len == 1) {
                    init_stmt = init_stmts.items[0];
                } else {
                    const wrapped = try this.allocator.create(ast.Node);
                    wrapped.* = .{ .BlockStatement = .{ .statements = try init_stmts.toOwnedSlice(this.allocator) } };
                    init_stmt = wrapped;
                }
            } else {
                init_stmt = try this.parseCommaExpression();
            }
        }
        if (this.current_token.type != .Semicolon) {
            if (init_stmt) |init_node| ast.freeAst(this.allocator, init_node);
            return error.ExpectedSemicolon;
        }
        this.nextToken(); // consume ';'

        // Parse condition (optional)
        var condition: ?*ast.Node = null;
        if (this.current_token.type != .Semicolon) {
            condition = try this.parseCommaExpression();
        }
        if (this.current_token.type != .Semicolon) {
            if (init_stmt) |init_node| ast.freeAst(this.allocator, init_node);
            if (condition) |cond_node| ast.freeAst(this.allocator, cond_node);
            return error.ExpectedSemicolon;
        }
        this.nextToken(); // consume ';'

        // Parse increment (optional)
        var increment: ?*ast.Node = null;
        if (this.current_token.type != .RParen) {
            increment = try this.parseCommaExpression();
        }
        if (this.current_token.type != .RParen) {
            if (init_stmt) |init_node| ast.freeAst(this.allocator, init_node);
            if (condition) |cond_node| ast.freeAst(this.allocator, cond_node);
            if (increment) |inc_node| ast.freeAst(this.allocator, inc_node);
            return error.ExpectedRParen;
        }
        this.nextToken(); // consume ')'

        const body = try this.parseStatement();

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ForLoop = .{
            .init = init_stmt,
            .condition = condition,
            .increment = increment,
            .body = body,
        } };
        return node;
    }

    fn parseWhileLoop(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'while'
        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        const condition = try this.parseCommaExpression();

        if (this.current_token.type != .RParen) {
            ast.freeAst(this.allocator, condition);
            return error.ExpectedRParen;
        }
        this.nextToken(); // consume ')'

        const body = try this.parseStatement();

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .WhileLoop = .{
            .condition = condition,
            .body = body,
        } };
        return node;
    }

    fn parseDoWhileLoop(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'do'

        const body = try this.parseStatement();

        if (this.current_token.type != .While) {
            return error.ExpectedWhile;
        }
        this.nextToken(); // consume 'while'

        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        const condition = try this.parseCommaExpression();

        if (this.current_token.type != .RParen) {
            ast.freeAst(this.allocator, condition);
            ast.freeAst(this.allocator, body);
            return error.ExpectedRParen;
        }
        this.nextToken(); // consume ')'

        if (this.current_token.type == .Semicolon) {
            this.nextToken(); // consume ';'
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .DoWhileLoop = .{
            .body = body,
            .condition = condition,
        } };
        return node;
    }

    fn parseIfStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'if'
        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        const condition = try this.parseCommaExpression();

        if (this.current_token.type != .RParen) {
            ast.freeAst(this.allocator, condition);
            return error.ExpectedRParen;
        }
        this.nextToken(); // consume ')'

        const consequence = try this.parseStatement();

        var alternative: ?*ast.Node = null;
        if (this.current_token.type == .Else) {
            this.nextToken(); // consume 'else'
            alternative = try this.parseStatement();
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .IfStatement = .{
            .condition = condition,
            .consequence = consequence,
            .alternative = alternative,
        } };
        return node;
    }

    fn parseSwitchStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'switch'
        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        const discriminant = try this.parseCommaExpression();

        if (this.current_token.type != .RParen) {
            ast.freeAst(this.allocator, discriminant);
            return error.ExpectedRParen;
        }
        this.nextToken(); // consume ')'

        if (this.current_token.type != .LBrace) {
            ast.freeAst(this.allocator, discriminant);
            return error.ExpectedLBrace;
        }
        this.nextToken(); // consume '{'

        var cases = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
        defer cases.deinit(this.allocator);

        while (this.current_token.type != .RBrace and this.current_token.type != .EOF) {
            var test_expr: ?*ast.Node = null;
            if (this.current_token.type == .Case) {
                this.nextToken(); // consume 'case'
                test_expr = try this.parseCommaExpression();
            } else if (this.current_token.type == .Default) {
                this.nextToken(); // consume 'default'
            } else {
                ast.freeAst(this.allocator, discriminant);
                return error.UnexpectedToken;
            }

            if (this.current_token.type != .Colon) {
                if (test_expr) |te| ast.freeAst(this.allocator, te);
                ast.freeAst(this.allocator, discriminant);
                return error.ExpectedColon;
            }
            this.nextToken(); // consume ':'

            var statements = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
            defer statements.deinit(this.allocator);
            while (this.current_token.type != .Case and
                this.current_token.type != .Default and
                this.current_token.type != .RBrace and
                this.current_token.type != .EOF)
            {
                try statements.append(this.allocator, try this.parseStatement());
            }

            const consequent = try this.allocator.create(ast.Node);
            consequent.* = .{ .BlockStatement = .{ .statements = try statements.toOwnedSlice(this.allocator) } };

            const case_node = try this.allocator.create(ast.Node);
            case_node.* = .{ .SwitchCase = .{ .test_expr = test_expr, .consequent = consequent } };
            try cases.append(this.allocator, case_node);
        }

        if (this.current_token.type != .RBrace) {
            ast.freeAst(this.allocator, discriminant);
            return error.ExpectedRBrace;
        }
        this.nextToken(); // consume '}'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .SwitchStatement = .{
            .discriminant = discriminant,
            .cases = try cases.toOwnedSlice(this.allocator),
        } };
        return node;
    }

    fn parseReturnStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'return'

        var value: ?*ast.Node = null;

        // Check if there's an expression after return (not semicolon or other statement terminators)
        if (this.current_token.type != .Semicolon and
            this.current_token.type != .RBrace and
            this.current_token.type != .EOF and
            this.current_token.type != .Else)
        {
            value = try this.parseExpression();
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ReturnStatement = .{
            .value = value,
        } };
        return node;
    }

    fn parseBreakStatement(this: *Parser) !*ast.Node {
        const line = this.current_token.line;
        this.nextToken(); // consume 'break'
        var label: ?[]const u8 = null;
        if (this.current_token.type == .Identifier) {
            label = this.current_token.literal;
            this.nextToken(); // consume label
        }
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .BreakStatement = .{ .label = label, .line = line } };
        return node;
    }

    fn parseContinueStatement(this: *Parser) !*ast.Node {
        const line = this.current_token.line;
        this.nextToken(); // consume 'continue'
        var label: ?[]const u8 = null;
        if (this.current_token.type == .Identifier) {
            label = this.current_token.literal;
            this.nextToken(); // consume label
        }
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ContinueStatement = .{ .label = label, .line = line } };
        return node;
    }

    fn parseThrowStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'throw'
        const value = try this.parseExpression();
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ThrowStatement = .{ .value = value } };
        return node;
    }

    fn parseTryStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'try'
        const body = try this.parseBlockStatement();

        var catch_param: ?[]const u8 = null;
        var catch_body: ?*ast.Node = null;
        var finally_body: ?*ast.Node = null;

        if (this.current_token.type == .Catch) {
            this.nextToken(); // consume 'catch'
            if (this.current_token.type == .LParen) {
                this.nextToken(); // consume '('
                if (this.current_token.type == .Identifier) {
                    catch_param = this.current_token.literal;
                    this.nextToken(); // consume param name
                }
                if (this.current_token.type == .RParen) {
                    this.nextToken(); // consume ')'
                }
            }
            catch_body = try this.parseBlockStatement();
        }

        if (this.current_token.type == .Finally) {
            this.nextToken(); // consume 'finally'
            finally_body = try this.parseBlockStatement();
        }

        if (catch_body == null and finally_body == null) {
            return error.ExpectedCatchOrFinally;
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .TryCatchFinally = .{
            .body = body,
            .catch_param = catch_param,
            .catch_body = catch_body,
            .finally_body = finally_body,
        } };
        return node;
    }

    // Shared by parseArrowFunction and parseFunctionDeclaration.
    // Block bodies call parseBlockStatement; non-block bodies call
    // parseExpression (NOT parseStatement — which via
    // parseCommaExpression greedily consumes boundary tokens).
    fn parseFunctionBody(this: *Parser) !*ast.Node {
        return if (this.current_token.type == .LBrace) this.parseBlockStatement() else this.parseExpression();
    }

    /// Parse parameter list for functions/arrows/generators.
    /// Returns parameter names, optional rest param, and any destructured
    /// binding statements that should be prepended to the function body.
    fn parseFunctionParameters(this: *Parser) !struct {
        names: [][]const u8,
        rest_param: ?[]const u8,
        destructured_preamble: ?*ast.Node,
        defaults: []?*ast.Node,
    } {
        var parameters = try std.ArrayList([]const u8).initCapacity(this.allocator, 4);
        defer parameters.deinit(this.allocator);
        var defaults = try std.ArrayList(?*ast.Node).initCapacity(this.allocator, 4);
        defer defaults.deinit(this.allocator);
        var rest_param: ?[]const u8 = null;
        var preamble_stmts = std.ArrayList(*ast.Node).initCapacity(this.allocator, 4) catch {
            return error.OutOfMemory;
        };

        while (this.current_token.type != .RParen) {
            // Rest parameter: ...restName
            if (this.current_token.type == .DotDotDot) {
                this.nextToken(); // consume '...'
                if (this.current_token.type == .Identifier or this.current_token.type == .Fn) {
                    rest_param = this.current_token.literal;
                    this.nextToken(); // consume parameter name
                    break; // rest param must be last
                } else {
                    preamble_stmts.deinit(this.allocator);
                    return error.ExpectedIdentifier;
                }
            }
            // Destructured parameter: { pattern } or [ pattern ]
            else if (this.current_token.type == .LBrace or this.current_token.type == .LBracket) {
                const temp_name = try this.genDestTempName();
                const temp_ident = try this.makeIdentNode(temp_name);
                this.parseDestructuredPattern(temp_ident, &preamble_stmts, true) catch |err| {
                    preamble_stmts.deinit(this.allocator);
                    return err;
                };
                try parameters.append(this.allocator, temp_name);
                // Whole-pattern default: function f({x, y} = defaultValue)
                if (this.current_token.type == .Assign) {
                    this.nextToken(); // consume '='
                    const default_expr = this.parseExpression() catch |err| {
                        preamble_stmts.deinit(this.allocator);
                        return err;
                    };
                    // Create assignment: temp_name = temp_name ?? default_expr
                    const ident_ref = this.makeIdentNode(temp_name) catch |err| {
                        preamble_stmts.deinit(this.allocator);
                        return err;
                    };
                    const nullish = this.allocator.create(ast.Node) catch |err| {
                        preamble_stmts.deinit(this.allocator);
                        return err;
                    };
                    nullish.* = .{ .BinaryExpression = .{
                        .left = ident_ref,
                        .operator = .Nullish,
                        .right = default_expr,
                    } };
                    const reassign = this.allocator.create(ast.Node) catch |err| {
                        preamble_stmts.deinit(this.allocator);
                        return err;
                    };
                    reassign.* = .{ .Assignment = .{ .name = temp_name, .value = nullish } };
                    preamble_stmts.insert(this.allocator, 0, reassign) catch |err| {
                        preamble_stmts.deinit(this.allocator);
                        return err;
                    };
                }
                try defaults.append(this.allocator, null);
            }
            // Plain identifier parameter
            else if (this.current_token.type == .Identifier or this.current_token.type == .Fn) {
                try parameters.append(this.allocator, this.current_token.literal);
                this.nextToken(); // consume parameter name
                if (this.current_token.type == .Assign) {
                    this.nextToken(); // consume '='
                    const default_expr = this.parseExpression() catch |err| {
                        preamble_stmts.deinit(this.allocator);
                        return err;
                    };
                    try defaults.append(this.allocator, default_expr);
                } else {
                    try defaults.append(this.allocator, null);
                }
            } else {
                preamble_stmts.deinit(this.allocator);
                return error.ExpectedIdentifier;
            }

            // After a parameter, expect ',' (more params) or ')' (end)
            if (this.current_token.type == .RParen) break;
            if (this.current_token.type != .Comma) {
                preamble_stmts.deinit(this.allocator);
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }

        const destructured_preamble: ?*ast.Node = if (preamble_stmts.items.len > 0) blk: {
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .BlockStatement = .{ .statements = try preamble_stmts.toOwnedSlice(this.allocator) } };
            break :blk node;
        } else blk: {
            preamble_stmts.deinit(this.allocator);
            break :blk null;
        };

        return .{
            .names = try parameters.toOwnedSlice(this.allocator),
            .rest_param = rest_param,
            .destructured_preamble = destructured_preamble,
            .defaults = try defaults.toOwnedSlice(this.allocator),
        };
    }

    fn parseClass(this: *Parser, declaration: bool) !*ast.Node {
        this.nextToken(); // consume class

        var name: []const u8 = "";
        if (this.current_token.type == .Identifier) {
            name = this.current_token.literal;
            this.nextToken();
        }

        var superclass: ?*ast.Node = null;
        if (this.current_token.type == .Extends) {
            this.nextToken();
            superclass = try this.parseExpression();
        }

        if (this.current_token.type != .LBrace) return error.ExpectedLBrace;
        this.nextToken();

        var methods = try std.ArrayList(ast.ClassMethod).initCapacity(this.allocator, 8);
        defer methods.deinit(this.allocator);
        var fields = try std.ArrayList(ast.ClassField).initCapacity(this.allocator, 4);
        defer fields.deinit(this.allocator);

        while (this.current_token.type != .RBrace and this.current_token.type != .EOF) {
            if (this.current_token.type == .Semicolon) {
                this.nextToken();
                continue;
            }

            var is_static = false;
            if (this.current_token.type == .Static and this.peek_token.type != .LParen) {
                is_static = true;
                this.nextToken();
            }

            var is_async = false;
            if (this.current_token.type == .Async and this.peek_token.type != .LParen) {
                is_async = true;
                this.nextToken();
            }

            var kind: ast.ClassMethodKind = .method;
            if ((this.current_token.type == .Get or this.current_token.type == .Set) and this.peek_token.type != .LParen) {
                kind = if (this.current_token.type == .Get) .get else .set;
                this.nextToken();
            }

            var method_name: []const u8 = undefined;
            if (this.current_token.type == .Hash) {
                this.nextToken();
                if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
                method_name = try std.fmt.allocPrint(this.allocator, "#{s}", .{this.current_token.literal});
                this.nextToken();
            } else if (this.current_token.type == .Identifier or this.current_token.type == .String or this.current_token.type == .Integer) {
                method_name = this.current_token.literal;
                this.nextToken();
            } else {
                return error.ExpectedIdentifier;
            }

            if (this.current_token.type == .Assign) {
                this.nextToken();
                var value: ?*ast.Node = null;
                if (this.current_token.type != .Semicolon and this.current_token.type != .RBrace) {
                    value = try this.parseExpression();
                }
                if (this.current_token.type == .Semicolon) this.nextToken();
                try fields.append(this.allocator, .{ .name = method_name, .value = value, .is_static = is_static });
                continue;
            }

            if (this.current_token.type != .LParen) return error.ExpectedLParen;
            this.nextToken();
            const params = try this.parseFunctionParameters();
            this.nextToken(); // consume )
            const body = try this.parseFunctionBody();
            const final_body = if (params.destructured_preamble) |preamble| blk: {
                if (body.* == .BlockStatement) {
                    var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, body.BlockStatement.statements.len + 1);
                    defer new_stmts.deinit(this.allocator);
                    try new_stmts.append(this.allocator, preamble);
                    for (body.BlockStatement.statements) |s| try new_stmts.append(this.allocator, s);
                    this.allocator.free(body.BlockStatement.statements);
                    const wrapped = try this.allocator.create(ast.Node);
                    wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                    break :blk wrapped;
                }
                break :blk body;
            } else body;

            if (!is_static and std.mem.eql(u8, method_name, "constructor")) kind = .constructor;
            const func_node = try this.allocator.create(ast.Node);
            func_node.* = .{ .FunctionDeclaration = .{
                .name = method_name,
                .parameters = params.names,
                .body = final_body,
                .rest_param = params.rest_param,
                .param_defaults = params.defaults,
                .is_async = is_async,
            } };
            try methods.append(this.allocator, .{ .name = method_name, .function = func_node, .is_static = is_static, .kind = kind });
        }

        if (this.current_token.type != .RBrace) return error.ExpectedRBrace;
        this.nextToken();
        if (this.current_token.type == .Semicolon) this.nextToken();

        const node = try this.allocator.create(ast.Node);
        if (declaration) {
            node.* = .{ .ClassDeclaration = .{
                .name = name,
                .superclass = superclass,
                .methods = try methods.toOwnedSlice(this.allocator),
                .fields = try fields.toOwnedSlice(this.allocator),
            } };
        } else {
            node.* = .{ .ClassExpression = .{
                .name = name,
                .superclass = superclass,
                .methods = try methods.toOwnedSlice(this.allocator),
                .fields = try fields.toOwnedSlice(this.allocator),
            } };
        }
        return node;
    }

    fn isAsyncSyntaxStart(this: *Parser) bool {
        return switch (this.peek_token.type) {
            .Fn, .Identifier => true,
            .LParen => this.tokenAfterBalancedParens() == .Arrow,
            else => false,
        };
    }

    /// Starting just after the peek token `(`, scan to its matching `)` and
    /// return the token that follows. Used to distinguish `async (x) => ...`
    /// from a call to a variable named `async`.
    fn tokenAfterBalancedParens(this: *Parser) TokenType {
        var lex_copy = this.lexer.*;
        var depth: usize = 1;
        while (true) {
            const tok = lex_copy.nextToken();
            switch (tok.type) {
                .LParen => depth += 1,
                .RParen => {
                    depth -= 1;
                    if (depth == 0) break;
                },
                .EOF => return .EOF,
                else => {},
            }
        }
        return lex_copy.nextToken().type;
    }
    fn parseAsyncFunctionOrArrow(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'async'

        if (this.current_token.type == .Fn) {
            const node = try this.parseFunctionDeclaration();
            switch (node.*) {
                .FunctionDeclaration => node.FunctionDeclaration.is_async = true,
                .GeneratorDeclaration => node.GeneratorDeclaration.is_async = true,
                else => return error.UnexpectedToken,
            }
            return node;
        }

        if (this.current_token.type == .LParen) {
            const node = try this.parseArrowFunction();
            node.ArrowFunction.is_async = true;
            return node;
        }

        // Single-parameter async arrow: async x => ...
        if (this.current_token.type == .Identifier) {
            const param_name = this.current_token.literal;
            this.nextToken();
            if (this.current_token.type != .Arrow) return error.ExpectedArrow;
            this.nextToken(); // consume '=>'
            const body = try this.parseFunctionBody();
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ArrowFunction = .{
                .parameters = try this.allocator.dupe([]const u8, &.{param_name}),
                .body = body,
                .is_async = true,
            } };
            return node;
        }

        return error.ExpectedLParen;
    }
    fn parseFunctionDeclaration(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'fn'

        // Check if this is a generator function (function* or fn*)
        var is_generator = false;
        if (this.current_token.type == .Multiply) {
            is_generator = true;
            this.nextToken(); // consume '*'
        }

        var name: []const u8 = "";
        if (this.current_token.type == .Identifier or this.current_token.type == .Async) {
            name = this.current_token.literal;
            this.nextToken(); // consume identifier
        }

        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        const params = try this.parseFunctionParameters();
        this.nextToken(); // consume ')'

        const body = try this.parseFunctionBody();
        const final_body = if (params.destructured_preamble) |preamble| blk: {
            // Prepend destructured bindings to the function body
            if (body.* == .BlockStatement) {
                var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, body.BlockStatement.statements.len + 1);
                defer new_stmts.deinit(this.allocator);
                try new_stmts.append(this.allocator, preamble);
                for (body.BlockStatement.statements) |s| try new_stmts.append(this.allocator, s);
                this.allocator.free(body.BlockStatement.statements);
                const wrapped = try this.allocator.create(ast.Node);
                wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                break :blk wrapped;
            } else {
                // Expression body: wrap in BlockStatement with preamble
                var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 2);
                defer new_stmts.deinit(this.allocator);
                try new_stmts.append(this.allocator, preamble);
                const ret = try this.allocator.create(ast.Node);
                ret.* = .{ .ReturnStatement = .{ .value = body } };
                try new_stmts.append(this.allocator, ret);
                const wrapped = try this.allocator.create(ast.Node);
                wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                break :blk wrapped;
            }
        } else body;

        if (is_generator) {
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .GeneratorDeclaration = .{
                .name = name,
                .parameters = params.names,
                .body = final_body,
                .rest_param = params.rest_param,
                .param_defaults = params.defaults,
            } };
            return node;
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .FunctionDeclaration = .{
            .name = name,
            .parameters = params.names,
            .body = final_body,
            .rest_param = params.rest_param,
            .param_defaults = params.defaults,
        } };
        return node;
    }

    fn parseArrowFunction(this: *Parser) !*ast.Node {
        this.nextToken(); // consume '('

        const params = try this.parseFunctionParameters();
        this.nextToken(); // consume ')'

        if (this.current_token.type != .Arrow) {
            return error.ExpectedArrow;
        }
        this.nextToken(); // consume '=>'

        const body = try this.parseFunctionBody();
        const final_body = if (params.destructured_preamble) |preamble| blk: {
            // Prepend destructured bindings to the function body
            if (body.* == .BlockStatement) {
                var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, body.BlockStatement.statements.len + 1);
                defer new_stmts.deinit(this.allocator);
                try new_stmts.append(this.allocator, preamble);
                for (body.BlockStatement.statements) |s| try new_stmts.append(this.allocator, s);
                this.allocator.free(body.BlockStatement.statements);
                const wrapped = try this.allocator.create(ast.Node);
                wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                break :blk wrapped;
            } else {
                // Expression body: wrap in BlockStatement with preamble
                var new_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 2);
                defer new_stmts.deinit(this.allocator);
                try new_stmts.append(this.allocator, preamble);
                const ret = try this.allocator.create(ast.Node);
                ret.* = .{ .ReturnStatement = .{ .value = body } };
                try new_stmts.append(this.allocator, ret);
                const wrapped = try this.allocator.create(ast.Node);
                wrapped.* = .{ .BlockStatement = .{ .statements = try new_stmts.toOwnedSlice(this.allocator) } };
                break :blk wrapped;
            }
        } else body;

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ArrowFunction = .{
            .parameters = params.names,
            .body = final_body,
            .rest_param = params.rest_param,
            .param_defaults = params.defaults,
        } };
        return node;
    }

    fn appendOptionalLink(this: *Parser, base: *ast.Node, link: ast.OptionalLink) anyerror!*ast.Node {
        if (base.* == .OptionalChain) {
            var oc = &base.OptionalChain;
            var list = try std.ArrayList(ast.OptionalLink).initCapacity(this.allocator, oc.links.len + 1);
            defer list.deinit(this.allocator);
            try list.appendSlice(this.allocator, oc.links);
            try list.append(this.allocator, link);
            const new_links = try list.toOwnedSlice(this.allocator);
            this.allocator.free(oc.links);
            oc.links = new_links;
            return base;
        }
        const links = try this.allocator.alloc(ast.OptionalLink, 1);
        links[0] = link;
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .OptionalChain = .{ .base = base, .links = links } };
        return node;
    }

    fn parseCallLink(this: *Parser, optional: bool) anyerror!ast.OptionalLink {
        this.nextToken(); // consume '('
        var args = try this.parseCallArguments();
        defer args.deinit(this.allocator);
        if (this.current_token.type != .RParen) return error.ExpectedRParen;
        this.nextToken(); // consume ')'
        return .{ .kind = .call, .optional = optional, .arguments = try args.toOwnedSlice(this.allocator) };
    }

    fn parseOptionalChainPostfix(this: *Parser, base: *ast.Node) anyerror!*ast.Node {
        this.nextToken(); // consume '?.'
        var node = base;
        if (this.current_token.type == .LBracket) {
            this.nextToken(); // consume '['
            const index = try this.parseExpression();
            if (this.current_token.type != .RBracket) {
                ast.freeAst(this.allocator, index);
                return error.ExpectedRBracket;
            }
            this.nextToken(); // consume ']'
            return this.appendOptionalLink(node, .{ .kind = .index, .optional = true, .expr = index });
        }
        if (this.current_token.type == .LParen) {
            const link = try this.parseCallLink(true);
            return this.appendOptionalLink(node, link);
        }
        if (!isPropertyName(this.current_token.type)) return error.ExpectedIdentifier;
        const name = this.current_token.literal;
        this.nextToken();
        node = try this.appendOptionalLink(node, .{ .kind = .property, .optional = true, .name = name });
        if (this.current_token.type == .LParen) {
            const link = try this.parseCallLink(false);
            node = try this.appendOptionalLink(node, link);
        }
        return node;
    }

    fn parseChainDotPostfix(this: *Parser, base: *ast.Node) anyerror!*ast.Node {
        this.nextToken(); // consume '.'
        if (!isPropertyName(this.current_token.type)) return error.ExpectedIdentifier;
        const name = this.current_token.literal;
        this.nextToken();
        var node = try this.appendOptionalLink(base, .{ .kind = .property, .optional = false, .name = name });
        if (this.current_token.type == .LParen) {
            const link = try this.parseCallLink(false);
            node = try this.appendOptionalLink(node, link);
        }
        return node;
    }

    fn parseChainIndexPostfix(this: *Parser, base: *ast.Node) anyerror!*ast.Node {
        this.nextToken(); // consume '['
        const index = try this.parseExpression();
        if (this.current_token.type != .RBracket) {
            ast.freeAst(this.allocator, index);
            return error.ExpectedRBracket;
        }
        this.nextToken(); // consume ']'
        return this.appendOptionalLink(base, .{ .kind = .index, .optional = false, .expr = index });
    }

    fn parseChainCallPostfix(this: *Parser, base: *ast.Node) anyerror!*ast.Node {
        const link = try this.parseCallLink(false);
        return this.appendOptionalLink(base, link);
    }
    fn parseMemberAccessOrCall(this: *Parser, object: *ast.Node) anyerror!*ast.Node {
        // Si esta función falla, debemos liberar el object
        errdefer ast.freeAst(this.allocator, object);

        this.nextToken(); // consume '.'

        var property: []const u8 = undefined;
        if (this.current_token.type == .Hash) {
            this.nextToken();
            if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
            property = try std.fmt.allocPrint(this.allocator, "#{s}", .{this.current_token.literal});
        } else if (isPropertyName(this.current_token.type)) {
            property = this.current_token.literal;
        } else {
            return error.ExpectedIdentifier;
        }
        this.nextToken(); // consume property name

        // Si hay paréntesis, es una llamada a método
        if (this.current_token.type == .LParen) {
            this.nextToken(); // consume '('

            var arguments = try this.parseCallArguments();
            defer arguments.deinit(this.allocator);
            this.nextToken(); // consume ')'

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .MethodCall = .{
                .object = object,
                .method = property,
                .arguments = try arguments.toOwnedSlice(this.allocator),
            } };
            return node;
        }

        // Si no hay paréntesis, es solo acceso a propiedad
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .MemberAccess = .{
            .object = object,
            .property = property,
        } };
        return node;
    }

    fn parseArrayIndex(this: *Parser, array: *ast.Node) anyerror!*ast.Node {
        this.nextToken(); // consume '['

        const index = try this.parseExpression();
        errdefer ast.freeAst(this.allocator, index);

        if (this.current_token.type != .RBracket) {
            ast.freeAst(this.allocator, index);
            ast.freeAst(this.allocator, array);
            return error.ExpectedRBracket;
        }
        this.nextToken(); // consume ']'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ArrayIndex = .{
            .array = array,
            .index = index,
        } };
        return node;
    }

    fn parseYieldExpression(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'yield'

        var is_star = false;
        if (this.current_token.type == .Multiply) {
            is_star = true;
            this.nextToken(); // consume '*'
        }

        var value: ?*ast.Node = null;
        // Check if there's an expression after yield
        if (this.current_token.type != .Semicolon and
            this.current_token.type != .RBrace and
            this.current_token.type != .EOF and
            this.current_token.type != .RParen and
            this.current_token.type != .Comma)
        {
            value = try this.parseExpression();
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .YieldExpression = .{
            .value = value,
            .is_star = is_star,
        } };
        return node;
    }

    fn parseCallArguments(this: *Parser) !std.ArrayList(*ast.Node) {
        var arguments = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
        errdefer {
            for (arguments.items) |arg| {
                ast.freeAst(this.allocator, arg);
            }
            arguments.deinit(this.allocator);
        }

        while (this.current_token.type != .RParen) {
            const arg = if (this.current_token.type == .DotDotDot) blk: {
                this.nextToken(); // consume '...'
                const expr = try this.parseExpression();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .SpreadExpression = .{ .value = expr } };
                break :blk node;
            } else try this.parseExpression();

            errdefer ast.freeAst(this.allocator, arg);

            try arguments.append(this.allocator, arg);

            if (this.current_token.type == .RParen) break;

            if (this.current_token.type != .Comma) {
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }

        return arguments;
    }

    fn parseFunctionCall(this: *Parser) anyerror!*ast.Node {
        const name = this.current_token.literal;
        this.nextToken(); // consume identifier
        this.nextToken(); // consume '('

        var arguments = try this.parseCallArguments();
        defer arguments.deinit(this.allocator);
        this.nextToken(); // consume ')'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .FunctionCall = .{
            .name = name,
            .arguments = try arguments.toOwnedSlice(this.allocator),
        } };
        return node;
    }

    fn parseFunctionCallFromBase(this: *Parser, base: *ast.Node) anyerror!*ast.Node {
        if (base.* == .Identifier) {
            const name = base.Identifier.name;
            ast.freeAst(this.allocator, base);
            this.nextToken(); // consume '('

            var arguments = try this.parseCallArguments();
            defer arguments.deinit(this.allocator);
            this.nextToken(); // consume ')'

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .FunctionCall = .{
                .name = name,
                .arguments = try arguments.toOwnedSlice(this.allocator),
            } };
            return node;
        }

        // Non-identifier base (e.g. (function*() { ... })()) — create DirectCall node
        this.nextToken(); // consume '('

        var arguments = try this.parseCallArguments();
        defer arguments.deinit(this.allocator);
        this.nextToken(); // consume ')'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .DirectCall = .{
            .callee = base,
            .arguments = try arguments.toOwnedSlice(this.allocator),
        } };
        return node;
    }

    fn parseImportStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'import'

        // import "module-name" (side-effect only)
        if (this.current_token.type == .String) {
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ImportStatement = .{
                .module_path = this.current_token.literal,
                .default_binding = null,
                .namespace = null,
                .named_bindings = null,
                .side_effect_only = true,
            } };
            this.nextToken();
            return node;
        }

        // import * as name from "..."
        if (this.current_token.type == .Multiply) {
            this.nextToken(); // consume '*'
            if (this.current_token.type != .As) return error.ExpectedAs;
            this.nextToken(); // consume 'as'
            if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
            const namespace = this.current_token.literal;
            this.nextToken(); // consume name
            if (this.current_token.type != .From) return error.ExpectedFrom;
            this.nextToken(); // consume 'from'
            if (this.current_token.type != .String) return error.ExpectedString;
            const module_path = this.current_token.literal;
            this.nextToken(); // consume string

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ImportStatement = .{
                .module_path = module_path,
                .default_binding = null,
                .namespace = namespace,
                .named_bindings = null,
                .side_effect_only = false,
            } };
            return node;
        }

        // import { ... } from "..."
        if (this.current_token.type == .LBrace) {
            var bindings = try std.ArrayList(ast.NamedImport).initCapacity(this.allocator, 4);
            defer bindings.deinit(this.allocator);

            this.nextToken(); // consume '{'
            while (this.current_token.type != .RBrace) {
                if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
                const name = this.current_token.literal;
                this.nextToken(); // consume name

                var alias: ?[]const u8 = null;
                if (this.current_token.type == .As) {
                    this.nextToken(); // consume 'as'
                    if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
                    alias = this.current_token.literal;
                    this.nextToken(); // consume alias
                }

                try bindings.append(this.allocator, .{ .name = name, .alias = alias });

                if (this.current_token.type == .RBrace) break;
                if (this.current_token.type != .Comma) return error.ExpectedComma;
                this.nextToken(); // consume ','
            }
            this.nextToken(); // consume '}'

            if (this.current_token.type != .From) return error.ExpectedFrom;
            this.nextToken(); // consume 'from'
            if (this.current_token.type != .String) return error.ExpectedString;
            const module_path = this.current_token.literal;
            this.nextToken(); // consume string

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ImportStatement = .{
                .module_path = module_path,
                .default_binding = null,
                .namespace = null,
                .named_bindings = try bindings.toOwnedSlice(this.allocator),
                .side_effect_only = false,
            } };
            return node;
        }

        // import defaultExport from "..." or import defaultExport, { ... } from "..." or import defaultExport, * as name from "..."
        if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
        const default_binding = this.current_token.literal;
        this.nextToken(); // consume default name

        // import defaultExport from "..."
        if (this.current_token.type == .From) {
            this.nextToken(); // consume 'from'
            if (this.current_token.type != .String) return error.ExpectedString;
            const module_path = this.current_token.literal;
            this.nextToken(); // consume string

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ImportStatement = .{
                .module_path = module_path,
                .default_binding = default_binding,
                .namespace = null,
                .named_bindings = null,
                .side_effect_only = false,
            } };
            return node;
        }

        // import defaultExport, ... from "..."
        if (this.current_token.type != .Comma) return error.UnexpectedToken;
        this.nextToken(); // consume ','

        // import defaultExport, * as name from "..."
        if (this.current_token.type == .Multiply) {
            this.nextToken(); // consume '*'
            if (this.current_token.type != .As) return error.ExpectedAs;
            this.nextToken(); // consume 'as'
            if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
            const namespace = this.current_token.literal;
            this.nextToken(); // consume name
            if (this.current_token.type != .From) return error.ExpectedFrom;
            this.nextToken(); // consume 'from'
            if (this.current_token.type != .String) return error.ExpectedString;
            const module_path = this.current_token.literal;
            this.nextToken(); // consume string

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ImportStatement = .{
                .module_path = module_path,
                .default_binding = default_binding,
                .namespace = namespace,
                .named_bindings = null,
                .side_effect_only = false,
            } };
            return node;
        }

        // import defaultExport, { ... } from "..."
        if (this.current_token.type == .LBrace) {
            var bindings = try std.ArrayList(ast.NamedImport).initCapacity(this.allocator, 4);
            defer bindings.deinit(this.allocator);

            this.nextToken(); // consume '{'
            while (this.current_token.type != .RBrace) {
                if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
                const name = this.current_token.literal;
                this.nextToken(); // consume name

                var alias: ?[]const u8 = null;
                if (this.current_token.type == .As) {
                    this.nextToken(); // consume 'as'
                    if (this.current_token.type != .Identifier) return error.ExpectedIdentifier;
                    alias = this.current_token.literal;
                    this.nextToken(); // consume alias
                }

                try bindings.append(this.allocator, .{ .name = name, .alias = alias });

                if (this.current_token.type == .RBrace) break;
                if (this.current_token.type != .Comma) return error.ExpectedComma;
                this.nextToken(); // consume ','
            }
            this.nextToken(); // consume '}'

            if (this.current_token.type != .From) return error.ExpectedFrom;
            this.nextToken(); // consume 'from'
            if (this.current_token.type != .String) return error.ExpectedString;
            const module_path = this.current_token.literal;
            this.nextToken(); // consume string

            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ImportStatement = .{
                .module_path = module_path,
                .default_binding = default_binding,
                .namespace = null,
                .named_bindings = try bindings.toOwnedSlice(this.allocator),
                .side_effect_only = false,
            } };
            return node;
        }

        return error.UnexpectedToken;
    }

    fn parseExportStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'export'

        // export default ...
        if (this.current_token.type == .Default) {
            this.nextToken(); // consume 'default'
            const declaration = try this.parseStatement();
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .ExportStatement = .{
                .declaration = declaration,
                .is_default = true,
            } };
            return node;
        }

        // export const/var/let/fn ...
        const declaration = try this.parseStatement();
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ExportStatement = .{
            .declaration = declaration,
            .is_default = false,
        } };
        return node;
    }

    fn nextToken(this: *Parser) void {
        this.current_token = this.peek_token;
        this.peek_token = this.lexer.nextToken();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parse modulo operator" {
    const allocator = std.testing.allocator;
    const input = "5 % 2";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .Modulo);
}

test "parse bitwise operators" {
    const allocator = std.testing.allocator;
    const input = "5 & 3";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .BitAnd);
}

test "parse logical operators" {
    const allocator = std.testing.allocator;
    const input = "true && false";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .And);
}

test "parse nullish coalescing" {
    const allocator = std.testing.allocator;
    const input = "x ?? y";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .Nullish);
}

test "parse pipeline operator" {
    const allocator = std.testing.allocator;
    const input = "x |> double";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .Pipe);
}

test "parse compound assignment operators" {
    const allocator = std.testing.allocator;
    const input = "x += 5";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .PlusAssign);
}

test "parse single quoted string" {
    const allocator = std.testing.allocator;
    const input = "'hello'";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .StringLiteral);
    try std.testing.expectEqualStrings("hello", node.StringLiteral.value);
}

test "parse ternary - simple" {
    const allocator = std.testing.allocator;
    const input = "cond ? 1 : 2";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ConditionalExpression);
    try std.testing.expect(node.ConditionalExpression.condition.* == .Identifier);
    try std.testing.expectEqualStrings("cond", node.ConditionalExpression.condition.Identifier.name);
    try std.testing.expect(node.ConditionalExpression.consequent.* == .IntegerLiteral);
    try std.testing.expectEqual(@as(i64, 1), node.ConditionalExpression.consequent.IntegerLiteral.value);
    try std.testing.expect(node.ConditionalExpression.alternate.* == .IntegerLiteral);
    try std.testing.expectEqual(@as(i64, 2), node.ConditionalExpression.alternate.IntegerLiteral.value);
}

test "parse ternary - condition has higher precedence operator" {
    // `a > b ? 1 : 2` must parse as `(a > b) ? 1 : 2`, i.e. the comparison
    // operator is folded into the condition before the `?` is recognised.
    const allocator = std.testing.allocator;
    const input = "a > b ? 1 : 2";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ConditionalExpression);
    try std.testing.expect(node.ConditionalExpression.condition.* == .BinaryExpression);
    try std.testing.expect(node.ConditionalExpression.condition.BinaryExpression.operator == .GreaterThan);
}

test "parse ternary - right associative" {
    // `a ? b : c ? d : e` must parse as `a ? b : (c ? d : e)`.
    const allocator = std.testing.allocator;
    const input = "a ? b : c ? d : e";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ConditionalExpression);
    try std.testing.expect(node.ConditionalExpression.condition.* == .Identifier);
    try std.testing.expectEqualStrings("a", node.ConditionalExpression.condition.Identifier.name);
    try std.testing.expect(node.ConditionalExpression.consequent.* == .Identifier);
    try std.testing.expectEqualStrings("b", node.ConditionalExpression.consequent.Identifier.name);
    try std.testing.expect(node.ConditionalExpression.alternate.* == .ConditionalExpression);
    const inner = &node.ConditionalExpression.alternate.ConditionalExpression;
    try std.testing.expect(inner.condition.* == .Identifier);
    try std.testing.expectEqualStrings("c", inner.condition.Identifier.name);
    try std.testing.expect(inner.consequent.* == .Identifier);
    try std.testing.expectEqualStrings("d", inner.consequent.Identifier.name);
    try std.testing.expect(inner.alternate.* == .Identifier);
    try std.testing.expectEqualStrings("e", inner.alternate.Identifier.name);
}

test "parse ternary - missing colon is an error" {
    const allocator = std.testing.allocator;
    const input = "a ? b";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();

    try std.testing.expectError(error.ExpectedColon, parser.parseExpression());
}

test "parse ternary inside assignment" {
    // `q = cond ? a : b` must parse as `q = (cond ? a : b)`, not
    // `(q = cond) ? a : b`.
    const allocator = std.testing.allocator;
    const input = "q = cond ? a : b";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    // Top-level should be an Assignment
    try std.testing.expect(node.* == .Assignment);
    try std.testing.expectEqualStrings("q", node.Assignment.name);

    // The value of the assignment should be a ConditionalExpression
    const val = node.Assignment.value;
    try std.testing.expect(val.* == .ConditionalExpression);
    try std.testing.expect(val.ConditionalExpression.condition.* == .Identifier);
    try std.testing.expectEqualStrings("cond", val.ConditionalExpression.condition.Identifier.name);
    try std.testing.expect(val.ConditionalExpression.consequent.* == .Identifier);
    try std.testing.expectEqualStrings("a", val.ConditionalExpression.consequent.Identifier.name);
    try std.testing.expect(val.ConditionalExpression.alternate.* == .Identifier);
    try std.testing.expectEqualStrings("b", val.ConditionalExpression.alternate.Identifier.name);
}

test "parse ternary inside assignment - grouped condition" {
    // `q = (p % 2 == 0) ? q + 1 : q - 1` must parse as
    // `q = ((p % 2 == 0) ? q + 1 : q - 1)`.
    const allocator = std.testing.allocator;
    const input = "q = (p % 2 == 0) ? q + 1 : q - 1";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    try std.testing.expect(node.* == .Assignment);
    try std.testing.expectEqualStrings("q", node.Assignment.name);

    const val = node.Assignment.value;
    try std.testing.expect(val.* == .ConditionalExpression);

    // Condition: (p % 2 == 0) is a BinaryExpression
    try std.testing.expect(val.ConditionalExpression.condition.* == .BinaryExpression);
    try std.testing.expect(val.ConditionalExpression.condition.BinaryExpression.operator == .Equal);

    // Consequent: q + 1
    try std.testing.expect(val.ConditionalExpression.consequent.* == .BinaryExpression);
    try std.testing.expect(val.ConditionalExpression.consequent.BinaryExpression.operator == .Plus);

    // Alternate: q - 1
    try std.testing.expect(val.ConditionalExpression.alternate.* == .BinaryExpression);
    try std.testing.expect(val.ConditionalExpression.alternate.BinaryExpression.operator == .Minus);
}

test "parse ternary inside compound assignment" {
    // `x += cond ? a : b` must parse as `x += (cond ? a : b)`.
    const allocator = std.testing.allocator;
    const input = "x += cond ? a : b";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    // Top-level should be a BinaryExpression with += operator
    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .PlusAssign);
    try std.testing.expect(node.BinaryExpression.left.* == .Identifier);
    try std.testing.expectEqualStrings("x", node.BinaryExpression.left.Identifier.name);

    // Right side should be a ConditionalExpression
    const right = node.BinaryExpression.right;
    try std.testing.expect(right.* == .ConditionalExpression);
    try std.testing.expect(right.ConditionalExpression.condition.* == .Identifier);
    try std.testing.expectEqualStrings("cond", right.ConditionalExpression.condition.Identifier.name);
}

test "parse ternary inside comma expression with assignment" {
    // `(p = p + 1, q = cond ? a : b)` — the comma expression splits into two
    // statements, and the second one has a ternary inside its assignment.
    const allocator = std.testing.allocator;
    const input = "p = p + 1, q = cond ? a : b";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    // Top-level should be a CommaExpression
    try std.testing.expect(node.* == .CommaExpression);
    try std.testing.expectEqual(@as(usize, 2), node.CommaExpression.expressions.len);

    // First expression: p = p + 1 (Assignment)
    const first = node.CommaExpression.expressions[0];
    try std.testing.expect(first.* == .Assignment);
    try std.testing.expectEqualStrings("p", first.Assignment.name);

    // Second expression: q = cond ? a : b — parsed as BinaryExpression(q, =, ConditionalExpression)
    // because inside a comma expression the = is treated as a binary operator, not a statement-level Assignment.
    const second = node.CommaExpression.expressions[1];
    try std.testing.expect(second.* == .BinaryExpression);
    try std.testing.expect(second.BinaryExpression.operator == .Assign);
    try std.testing.expect(second.BinaryExpression.left.* == .Identifier);
    try std.testing.expectEqualStrings("q", second.BinaryExpression.left.Identifier.name);
    const ternary = second.BinaryExpression.right;
    try std.testing.expect(ternary.* == .ConditionalExpression);
    try std.testing.expect(ternary.ConditionalExpression.condition.* == .Identifier);
    try std.testing.expectEqualStrings("cond", ternary.ConditionalExpression.condition.Identifier.name);
}

test "parse object literal with reserved-keyword key - fn" {
    // ES2015 §13.2.5.4 allows IdentifierName (which includes reserved
    // words like `fn`, `return`, `if`) as object-literal property keys.
    const allocator = std.testing.allocator;
    const input = "({ fn: 1 })";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ObjectLiteral);
    try std.testing.expectEqual(@as(usize, 1), node.ObjectLiteral.properties.len);
    try std.testing.expectEqualStrings("fn", node.ObjectLiteral.properties[0].key);
    try std.testing.expect(node.ObjectLiteral.properties[0].value.* == .IntegerLiteral);
    try std.testing.expectEqual(@as(i64, 1), node.ObjectLiteral.properties[0].value.IntegerLiteral.value);
}

test "parse object literal with reserved-keyword key - return" {
    const allocator = std.testing.allocator;
    const input = "({ return: 1 })";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ObjectLiteral);
    try std.testing.expectEqual(@as(usize, 1), node.ObjectLiteral.properties.len);
    try std.testing.expectEqualStrings("return", node.ObjectLiteral.properties[0].key);
    try std.testing.expect(node.ObjectLiteral.properties[0].value.* == .IntegerLiteral);
    try std.testing.expectEqual(@as(i64, 1), node.ObjectLiteral.properties[0].value.IntegerLiteral.value);
}

test "parse object literal with multiple reserved-keyword keys" {
    // `{ if: 2, else: 3 }` — verifies the comma-delimited path also
    // accepts reserved-keyword keys (and that follow-up keys are not
    // accidentally consumed by a body-parser greediness).
    const allocator = std.testing.allocator;
    const input = "({ if: 2, else: 3 })";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ObjectLiteral);
    try std.testing.expectEqual(@as(usize, 2), node.ObjectLiteral.properties.len);
    try std.testing.expectEqualStrings("if", node.ObjectLiteral.properties[0].key);
    try std.testing.expectEqual(@as(i64, 2), node.ObjectLiteral.properties[0].value.IntegerLiteral.value);
    try std.testing.expectEqualStrings("else", node.ObjectLiteral.properties[1].key);
    try std.testing.expectEqual(@as(i64, 3), node.ObjectLiteral.properties[1].value.IntegerLiteral.value);
}

test "parse object literal regression - plain identifier keys still work" {
    // Sanity guard: the key-switch refactor must not break the
    // pre-existing Identifier/String/Integer/Float paths.
    const allocator = std.testing.allocator;
    const input = "({ a: 1, \"b\": 2, 3: 'three' })";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ObjectLiteral);
    try std.testing.expectEqual(@as(usize, 3), node.ObjectLiteral.properties.len);
    try std.testing.expectEqualStrings("a", node.ObjectLiteral.properties[0].key);
    try std.testing.expectEqualStrings("b", node.ObjectLiteral.properties[1].key);
    try std.testing.expectEqualStrings("3", node.ObjectLiteral.properties[2].key);
}

test "parse object literal - true/false/null/undefined as keys" {
    // Locks the contract that the lexer populates `tok.literal` with
    // the source word for these keyword token types. Without that,
    // `o.true` would resolve to an empty key and break all subsequent
    // reads on the resulting object.
    const allocator = std.testing.allocator;
    const input = "({ true: 1, false: 2, null: 3, undefined: 4 })";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ObjectLiteral);
    try std.testing.expectEqual(@as(usize, 4), node.ObjectLiteral.properties.len);
    try std.testing.expectEqualStrings("true", node.ObjectLiteral.properties[0].key);
    try std.testing.expectEqualStrings("false", node.ObjectLiteral.properties[1].key);
    try std.testing.expectEqualStrings("null", node.ObjectLiteral.properties[2].key);
    try std.testing.expectEqualStrings("undefined", node.ObjectLiteral.properties[3].key);
}

test "parse object literal - non-keyword token still errors" {
    // Bounds guard: widening the key switch via isPropertyName MUST
    // NOT accidentally accept tokens that are neither literals nor
    // keywords. A bare `;` is neither, so it must still error.
    const allocator = std.testing.allocator;
    const input = "{ ;: 1 }";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();

    try std.testing.expectError(error.ExpectedPropertyName, parser.parseExpression());
}

test "parse for loop - var without initializer" {
    // `for (var i; i < 10; i++)` is valid ES — `var` allows no initializer.
    const allocator = std.testing.allocator;
    const input = "for (var i; i < 3; i++) {}";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    try std.testing.expect(node.* == .ForLoop);
    try std.testing.expect(node.ForLoop.init != null);
    try std.testing.expect(node.ForLoop.init.?.* == .VariableDeclaration);
    try std.testing.expectEqualStrings("i", node.ForLoop.init.?.VariableDeclaration.name);
    try std.testing.expect(node.ForLoop.init.?.VariableDeclaration.value == null);
}

test "parse for loop - let without initializer" {
    // `for (let x;;) { break; }` is valid ES — `let` allows no initializer
    // (and `let` with no condition is also valid).
    const allocator = std.testing.allocator;
    const input = "for (let x;;) { break; }";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    try std.testing.expect(node.* == .ForLoop);
    try std.testing.expect(node.ForLoop.init.?.* == .LetDeclaration);
    try std.testing.expectEqualStrings("x", node.ForLoop.init.?.LetDeclaration.name);
    try std.testing.expect(node.ForLoop.init.?.LetDeclaration.value == null);
}

test "parse for loop - mixed init/no-init with var and comma" {
    // `for (var i = 0, j; i < 3; i++)` — var with mixed init across the
    // comma-list produces a BlockStatement-of-decls.
    const allocator = std.testing.allocator;
    const input = "for (var i = 0, j; i < 3; i++) {}";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    try std.testing.expect(node.* == .ForLoop);
    try std.testing.expect(node.ForLoop.init.?.* == .BlockStatement);
    const stmts = node.ForLoop.init.?.BlockStatement.statements;
    try std.testing.expectEqual(@as(usize, 2), stmts.len);

    // First: i = 0 (value present)
    try std.testing.expect(stmts[0].* == .VariableDeclaration);
    try std.testing.expectEqualStrings("i", stmts[0].VariableDeclaration.name);
    try std.testing.expect(stmts[0].VariableDeclaration.value != null);

    // Second: j; (no value)
    try std.testing.expect(stmts[1].* == .VariableDeclaration);
    try std.testing.expectEqualStrings("j", stmts[1].VariableDeclaration.name);
    try std.testing.expect(stmts[1].VariableDeclaration.value == null);
}

test "parse for loop - const without initializer is SyntaxError" {
    // ECMAScript §14.7.4.5: const bindings in for-init MUST have an initializer.
    const allocator = std.testing.allocator;
    const input = "for (const c;;) {}";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();

    try std.testing.expectError(error.ExpectedAssign, parser.parseStatement());
}

test "parse for loop - var with initializer still works (regression)" {
    // Sanity guard: existing `for (var i = 0; ...)` shape must remain a
    // VariableDeclaration with non-null value.
    const allocator = std.testing.allocator;
    const input = "for (var i = 0; i < 3; i++) {}";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();

    try std.testing.expect(node.* == .ForLoop);
    try std.testing.expect(node.ForLoop.init.?.* == .VariableDeclaration);
    try std.testing.expectEqualStrings("i", node.ForLoop.init.?.VariableDeclaration.name);
    try std.testing.expect(node.ForLoop.init.?.VariableDeclaration.value != null);
    try std.testing.expect(node.ForLoop.init.?.VariableDeclaration.value.?.* == .IntegerLiteral);
    try std.testing.expectEqual(@as(i64, 0), node.ForLoop.init.?.VariableDeclaration.value.?.IntegerLiteral.value);
}

test "parse object literal - non-block function expression as value" {
    // C-1 of the closed object-method-call edge cases. The compat file
    // `tests/compat/object-method-call-edge-cases.lou` cannot exercise
    // this — `function() 1` is invalid ES (function bodies must be
    // BlockStatements per ECMAScript). This unit test is therefore the
    // only future-detection surface for parseFunctionDeclaration's
    // non-block body consolidation (parseExpression instead of
    // parseStatement, via the shared `parseFunctionBody` helper).
    //
    // Pre-fix, parseStatement called parseCommaExpression which greedily
    // consumed the comma after `1`, collapsing `1, g: 2` into a single
    // property whose value was a CommaExpression — silently dropping
    // the second property. Two phases assert the closed contract:

    const allocator = std.testing.allocator;

    // Phase A — structural: the full input parses to a 2-property
    // ObjectLiteral whose first value is a FunctionDeclaration with a
    // non-block IntegerLiteral body.
    {
        const input = "{ f: function() 1, g: 2 }";
        var lexer = Lexer.init(input);
        var parser = try Parser.init(&lexer, allocator);
        defer parser.deinit();
        const node = try parser.parseExpression();

        try std.testing.expect(node.* == .ObjectLiteral);
        try std.testing.expectEqual(@as(usize, 2), node.ObjectLiteral.properties.len);

        // First property: f → function() 1
        try std.testing.expectEqualStrings("f", node.ObjectLiteral.properties[0].key);
        try std.testing.expect(node.ObjectLiteral.properties[0].value.* == .FunctionDeclaration);
        const body = node.ObjectLiteral.properties[0].value.FunctionDeclaration.body;
        try std.testing.expect(body.* == .IntegerLiteral);
        try std.testing.expectEqual(@as(i64, 1), body.IntegerLiteral.value);

        // Second property: g → 2. Its presence proves the comma after `1`
        // was left intact — parseExpression does not fold boundary commas
        // the way parseStatement → parseCommaExpression would.
        try std.testing.expectEqualStrings("g", node.ObjectLiteral.properties[1].key);
        try std.testing.expect(node.ObjectLiteral.properties[1].value.* == .IntegerLiteral);
        try std.testing.expectEqual(@as(i64, 2), node.ObjectLiteral.properties[1].value.IntegerLiteral.value);

        // After parseObjectLiteral's final nextToken() consumes '}',
        // the lexer returns .EOF (no comma greediness seized g).
        try std.testing.expect(parser.current_token.type == .EOF);
    }

    // Phase B — comma-position contract: when parseFunctionDeclaration
    // returns with a non-block body in expression context, the trailing
    // `,` MUST remain for the caller (current_token.type == .Comma) —
    // i.e. parseExpression stops at the boundary token instead of
    // folding it via parseCommaExpression. This is the explicit
    // "current_token lands on the comma after the body" assertion.
    {
        const input = "function() 1, g: 2";
        var lexer = Lexer.init(input);
        var parser = try Parser.init(&lexer, allocator);
        defer parser.deinit();
        const node = try parser.parseExpression();

        try std.testing.expect(node.* == .FunctionDeclaration);
        try std.testing.expect(node.FunctionDeclaration.body.* == .IntegerLiteral);
        try std.testing.expect(parser.current_token.type == .Comma);
    }
}
test "parse object literal - function expression block followed by arrow property" {
    // Regression guard for the closed function-and-arrow edge case:
    // a block-bodied function expression and a parenthesized arrow must
    // coexist as separate properties without either parser consuming the
    // comma between them or the next property key.
    const allocator = std.testing.allocator;
    const input = "{ fn: function(a, b) { return a + b; }, arrow: (a, b) => a + b }";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .ObjectLiteral);
    try std.testing.expectEqual(@as(usize, 2), node.ObjectLiteral.properties.len);

    try std.testing.expectEqualStrings("fn", node.ObjectLiteral.properties[0].key);
    try std.testing.expect(node.ObjectLiteral.properties[0].value.* == .FunctionDeclaration);
    try std.testing.expect(node.ObjectLiteral.properties[0].value.FunctionDeclaration.body.* == .BlockStatement);
    try std.testing.expectEqual(@as(usize, 2), node.ObjectLiteral.properties[0].value.FunctionDeclaration.parameters.len);

    try std.testing.expectEqualStrings("arrow", node.ObjectLiteral.properties[1].key);
    try std.testing.expect(node.ObjectLiteral.properties[1].value.* == .ArrowFunction);
    try std.testing.expect(node.ObjectLiteral.properties[1].value.ArrowFunction.body.* == .BinaryExpression);
    try std.testing.expectEqual(@as(usize, 2), node.ObjectLiteral.properties[1].value.ArrowFunction.parameters.len);

    try std.testing.expect(parser.current_token.type == .EOF);
}
test "regex literal parses to a RegExp constructor call" {
    const allocator = std.testing.allocator;
    const input = "/ab+c/gi";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();

    try std.testing.expect(node.* == .NewExpression);
    try std.testing.expect(node.NewExpression.callee.* == .Identifier);
    try std.testing.expectEqualStrings("RegExp", node.NewExpression.callee.Identifier.name);
    try std.testing.expectEqual(@as(usize, 2), node.NewExpression.arguments.len);
    try std.testing.expect(node.NewExpression.arguments[0].* == .StringLiteral);
    try std.testing.expectEqualStrings("ab+c", node.NewExpression.arguments[0].StringLiteral.value);
    try std.testing.expect(node.NewExpression.arguments[1].* == .StringLiteral);
    try std.testing.expectEqualStrings("gi", node.NewExpression.arguments[1].StringLiteral.value);
}

test "division after a number is not a regex literal" {
    const allocator = std.testing.allocator;
    const input = "6 / 3";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();
    try std.testing.expect(node.* == .BinaryExpression);
    try std.testing.expect(node.BinaryExpression.operator == .Divide);
}

test "parse class declaration with fields, accessors and static members" {
    const allocator = std.testing.allocator;
    const input =
        \\class A extends B {
        \\  x = 1;
        \\  static y = 2;
        \\  constructor(a) { this.a = a; }
        \\  m() { return 1; }
        \\  static s() { return 2; }
        \\  get v() { return 3; }
        \\  set v(next) { this.a = next; }
        \\}
    ;
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const program = try parser.parseProgram();
    try std.testing.expectEqual(@as(usize, 1), program.len);
    try std.testing.expect(program[0].* == .ClassDeclaration);
    const cls = program[0].ClassDeclaration;
    try std.testing.expectEqualStrings("A", cls.name);
    try std.testing.expect(cls.superclass != null);
    try std.testing.expectEqualStrings("B", cls.superclass.?.Identifier.name);
    try std.testing.expectEqual(@as(usize, 2), cls.fields.len);
    try std.testing.expectEqualStrings("x", cls.fields[0].name);
    try std.testing.expect(!cls.fields[0].is_static);
    try std.testing.expectEqualStrings("y", cls.fields[1].name);
    try std.testing.expect(cls.fields[1].is_static);
    try std.testing.expectEqual(@as(usize, 5), cls.methods.len);
    try std.testing.expect(cls.methods[0].kind == .constructor);
    try std.testing.expect(cls.methods[1].kind == .method);
    try std.testing.expect(cls.methods[2].is_static);
    try std.testing.expect(cls.methods[3].kind == .get);
    try std.testing.expect(cls.methods[4].kind == .set);
}

test "parse class expression with private field" {
    const allocator = std.testing.allocator;
    const input = "const C = class { #value = 1; get value() { return this.#value; } };";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const program = try parser.parseProgram();
    try std.testing.expectEqual(@as(usize, 1), program.len);
    try std.testing.expect(program[0].* == .ConstantDeclaration);
    const init = program[0].ConstantDeclaration.value.?;
    try std.testing.expect(init.* == .ClassExpression);
    try std.testing.expectEqualStrings("#value", init.ClassExpression.fields[0].name);
    try std.testing.expectEqual(@as(usize, 1), init.ClassExpression.methods.len);
    try std.testing.expect(init.ClassExpression.methods[0].kind == .get);
}

test "parse async function with await" {
    const allocator = std.testing.allocator;
    const input = "async function f() { return await p; }";
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();
    try std.testing.expect(node.* == .FunctionDeclaration);
    try std.testing.expect(node.FunctionDeclaration.is_async);
    const body = node.FunctionDeclaration.body;
    try std.testing.expect(body.* == .BlockStatement);
    try std.testing.expectEqual(@as(usize, 1), body.BlockStatement.statements.len);
    const ret = body.BlockStatement.statements[0];
    try std.testing.expect(ret.* == .ReturnStatement);
    try std.testing.expect(ret.ReturnStatement.value.?.* == .AwaitExpression);
}

test "parse async arrow forms" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("async (x) => await x");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseExpression();
    try std.testing.expect(node.* == .ArrowFunction);
    try std.testing.expect(node.ArrowFunction.is_async);
    try std.testing.expectEqual(@as(usize, 1), node.ArrowFunction.parameters.len);
}

test "async remains a valid identifier" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("const async = 2;");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();
    try std.testing.expect(node.* == .ConstantDeclaration);
    try std.testing.expectEqualStrings("async", node.ConstantDeclaration.name);
}

test "async generator declarations are marked async" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("async function* count() { yield 1; }");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();
    try std.testing.expect(node.* == .GeneratorDeclaration);
    try std.testing.expect(node.GeneratorDeclaration.is_async);
    try std.testing.expectEqualStrings("count", node.GeneratorDeclaration.name);
}

test "for await loops are marked await" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("for await (const value of values) { console.log(value); }");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();
    try std.testing.expect(node.* == .ForOfLoop);
    try std.testing.expect(node.ForOfLoop.is_await);
}

test "for await rejects the in form" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("for await (const value in values) {}");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    try std.testing.expectError(error.UnexpectedToken, parser.parseStatement());
}

test "for await rejects the c-style form" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("for await (;;) {}");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    try std.testing.expectError(error.UnexpectedToken, parser.parseStatement());
}

test "plain for-of loops are not marked await" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init("for (const value of values) { console.log(value); }");
    var parser = try Parser.init(&lexer, allocator);
    defer parser.deinit();
    const node = try parser.parseStatement();
    try std.testing.expect(node.* == .ForOfLoop);
    try std.testing.expect(!node.ForOfLoop.is_await);
}
