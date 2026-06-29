const std = @import("std");

const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;

pub const Parser = struct {
    lexer: *Lexer,
    current_token: Token,
    peek_token: Token,
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    arena_child: std.mem.Allocator,

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
            .Const, .Var, .Let, .Null, .Undefined, .True, .False, .Fn,
            .Return, .If, .Else, .For, .While, .In, .Break, .Continue,
            .Switch, .Case, .Default, .Match, .Import, .From, .As, .Export, .TypeOf => true,
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
                    node.* = .{ .BlockStatement = .{ .statements = try stmts.toOwnedSlice(this.allocator) } };
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
                    node.* = .{ .BlockStatement = .{ .statements = try stmts.toOwnedSlice(this.allocator) } };
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
                    node.* = .{ .BlockStatement = .{ .statements = try stmts.toOwnedSlice(this.allocator) } };
                    break :stmt node;
                },
                .For => break :stmt try this.parseForLoop(),
                .While => break :stmt try this.parseWhileLoop(),
                .Do => break :stmt try this.parseDoWhileLoop(),
                .If => break :stmt try this.parseIfStatement(),
                .Return => break :stmt try this.parseReturnStatement(),
                .Break => break :stmt try this.parseBreakStatement(),
                .Continue => break :stmt try this.parseContinueStatement(),
                .Try => break :stmt try this.parseTryStatement(),
                .Throw => break :stmt try this.parseThrowStatement(),
                .Fn => break :stmt try this.parseFunctionDeclaration(),
                .Import => break :stmt try this.parseImportStatement(),
                .Export => break :stmt try this.parseExportStatement(),
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

    fn parseConstantDeclaration(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'const'
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

        while (@intFromEnum(precedence) < @intFromEnum(ast.getTokenPrecedence(this.current_token.type))) {
            const op = this.current_token.type;
            this.nextToken();
            const next_precedence = ast.getTokenPrecedence(op);
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
        if (@intFromEnum(precedence) <= @intFromEnum(ast.Precedence.Assign) and this.current_token.type == .Question) {
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
            .TemplateString => base = try this.parseStringLiteral(),
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
                base = try this.parseArrayLiteral();
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
                // Try arrow function first; if it fails, parse as grouped expression
                const saved_lexer = this.lexer.*;
                const saved_current = this.current_token;
                const saved_peek = this.peek_token;

                if (this.parseArrowFunction()) |result| {
                    base = result;
                } else |_| {
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
            },
            .Increment => {
                // Handle pre-increment operator like ++i
                this.nextToken();
                if (this.current_token.type == .Identifier) {
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .UpdateExpression = .{
                        .operand = blk: {
                            const ident = try this.allocator.create(ast.Node);
                            ident.* = .{ .Identifier = .{ .name = this.current_token.literal } };
                            break :blk ident;
                        },
                        .prefix = true,
                        .operator = .Increment,
                    } };
                    this.nextToken();
                    return node;
                } else {
                    return error.UnexpectedToken;
                }
            },
            .Minus => {
                // Unary minus: -literal, -identifier, -(expr), etc.
                this.nextToken();
                if (this.current_token.type == .Integer) {
                    const node = try this.allocator.create(ast.Node);
                    const value = try std.fmt.parseInt(i64, this.current_token.literal, 10);
                    node.* = .{ .IntegerLiteral = .{ .value = -value } };
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
                // Handle pre-decrement operator like --i
                this.nextToken();
                if (this.current_token.type == .Identifier) {
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .UpdateExpression = .{
                        .operand = blk: {
                            const ident = try this.allocator.create(ast.Node);
                            ident.* = .{ .Identifier = .{ .name = this.current_token.literal } };
                            break :blk ident;
                        },
                        .prefix = true,
                        .operator = .Decrement,
                    } };
                    this.nextToken();
                    return node;
                } else {
                    return error.UnexpectedToken;
                }
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
            .TypeOf => {
                // Handle typeof operator: typeof expr
                this.nextToken(); // consume 'typeof'
                const expr = try this.parsePrimary();
                const node = try this.allocator.create(ast.Node);
                node.* = .{ .TypeOfExpression = .{ .operand = expr } };
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

        // Postfix chain: .prop, [index], (args)
        while (true) {
            if (this.current_token.type == .LBracket) {
                base = try this.parseArrayIndex(base);
            } else if (this.current_token.type == .Dot) {
                base = try this.parseMemberAccessOrCall(base);
            } else if (this.current_token.type == .LParen) {
                base = try this.parseFunctionCallFromBase(base);
            } else {
                break;
            }
        }

        // Post-increment: i++
        if (this.current_token.type == .Increment and base.* == .Identifier) {
            this.nextToken(); // consume ++
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .UpdateExpression = .{
                .operand = base,
                .prefix = false,
                .operator = .Increment,
            } };
            return node;
        }

        // Post-decrement: i--
        if (this.current_token.type == .Decrement and base.* == .Identifier) {
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
        const value = try std.fmt.parseInt(i64, this.current_token.literal, 10);
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

    fn processStringEscapes(this: *Parser, raw: []const u8) ![]const u8 {
        var buf = std.ArrayList(u8).initCapacity(this.allocator, raw.len) catch { return raw; };
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
                    'u' => {
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

    fn parseObjectLiteral(this: *Parser) anyerror!*ast.Node {
        this.nextToken(); // consume '{'
        var properties = try std.ArrayList(ast.Property).initCapacity(this.allocator, 8);
        defer properties.deinit(this.allocator);

        while (this.current_token.type != .RBrace and this.current_token.type != .EOF) {
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
                    } };
                    return node;
                }

                if (this.current_token.type == .In) {
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
            }

            // Not a for...of or for...in, restore state and fall through to regular for loop parsing
            this.lexer.* = saved_lexer;
            this.current_token = saved_current;
            this.peek_token = saved_peek;
        }

        // Parse initialization (optional) — supports comma-separated initializers
        var init_stmt: ?*ast.Node = null;
        if (this.current_token.type != .Semicolon) {
            if (this.current_token.type == .Var or this.current_token.type == .Let or this.current_token.type == .Const) {
                const decl_type = this.current_token.type;
                this.nextToken(); // consume 'var'/'let'/'const'

                var init_stmts = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 2);
                defer init_stmts.deinit(this.allocator);

                {
                    const name = this.current_token.literal;
                    this.nextToken(); // consume identifier
                    if (this.current_token.type != .Assign) return error.ExpectedAssign;
                    this.nextToken(); // consume '='
                    const value = try this.parseExpression();
                    const n = try this.allocator.create(ast.Node);
                    n.* = switch (decl_type) {
                        .Var => .{ .VariableDeclaration = .{ .name = name, .value = value } },
                        .Let => .{ .LetDeclaration = .{ .name = name, .value = value } },
                        .Const => .{ .ConstantDeclaration = .{ .name = name, .value = value } },
                        else => unreachable,
                    };
                    try init_stmts.append(this.allocator, n);
                }

                while (this.current_token.type == .Comma) {
                    this.nextToken(); // consume ','
                    const name = this.current_token.literal;
                    this.nextToken(); // consume identifier
                    if (this.current_token.type != .Assign) return error.ExpectedAssign;
                    this.nextToken(); // consume '='
                    const value = try this.parseExpression();
                    const n = try this.allocator.create(ast.Node);
                    n.* = switch (decl_type) {
                        .Var => .{ .VariableDeclaration = .{ .name = name, .value = value } },
                        .Let => .{ .LetDeclaration = .{ .name = name, .value = value } },
                        .Const => .{ .ConstantDeclaration = .{ .name = name, .value = value } },
                        else => unreachable,
                    };
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

    // Shared between parseArrowFunction and parseFunctionDeclaration.
    // Arrow body is an `AssignmentExpression` per ES (NOT a statement);
    // for non-arrow bodies, `fn foo() expr` / `function foo() expr` is
    // shorthand for `fn foo() { return expr; }`. Don't use parseStatement
    // here: it calls parseCommaExpression for non-keyword bodies, which
    // greedily consumes any `,` token that follows (e.g. the property-list
    // delimiter in an enclosing object literal). parseExpression
    // (= parsePrecedece(.lowest)) respects the surrounding boundary,
    // stopping at `,` / `}` / EOF so the caller's boundary-token check
    // (also via parseExpression) can re-recognize the next property.
    fn parseFunctionBody(p: *Parser) !*ast.Node {
        return if (p.current_token.type == .LBrace) p.parseBlockStatement() else p.parseExpression();
    }

    fn parseFunctionDeclaration(this: *Parser) !*ast.Node {
        // Check if this is a generator function (function* or fn*)
        var is_generator = false;
        if (this.peek_token.type == .Multiply) {
            is_generator = true;
            this.nextToken(); // consume 'function'/'fn'
            this.nextToken(); // consume '*'
        }

        var name: []const u8 = "";
        if (this.current_token.type == .Identifier) {
            name = this.current_token.literal;
            this.nextToken(); // consume identifier
        } else if (this.peek_token.type == .Identifier) {
            this.nextToken(); // consume 'fn'
            name = this.current_token.literal;
            this.nextToken(); // consume identifier
    } else {
        if (!is_generator) {
            this.nextToken(); // consume 'fn' (anonymous function)
        }
        // For anonymous generators, 'fn' and '*' are already consumed above
    }

        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        var parameters = try std.ArrayList([]const u8).initCapacity(this.allocator, 4);
        defer parameters.deinit(this.allocator);
        var rest_param: ?[]const u8 = null;

        while (this.current_token.type != .RParen) {
            if (this.current_token.type == .DotDotDot) {
                this.nextToken(); // consume ...
                if (this.current_token.type == .Identifier or this.current_token.type == .Fn) {
                    rest_param = this.current_token.literal;
                    this.nextToken(); // consume parameter name
                    break; // rest param must be last, exit loop
                } else {
                    return error.ExpectedIdentifier;
                }
            } else
            if (this.current_token.type != .Identifier) {
                return error.ExpectedIdentifier;
            }
            try parameters.append(this.allocator, this.current_token.literal);
            this.nextToken(); // consume parameter

            if (this.current_token.type == .RParen) break;

            if (this.current_token.type != .Comma) {
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }
        this.nextToken(); // consume ')'

        const body = try this.parseFunctionBody();

        if (is_generator) {
            const node = try this.allocator.create(ast.Node);
            node.* = .{ .GeneratorDeclaration = .{
                .name = name,
                .parameters = try parameters.toOwnedSlice(this.allocator),
                .body = body,
                .rest_param = rest_param,
            } };
            return node;
        }

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .FunctionDeclaration = .{
            .name = name,
            .parameters = try parameters.toOwnedSlice(this.allocator),
            .body = body,
            .rest_param = rest_param,
        } };
        return node;
    }

    fn parseArrowFunction(this: *Parser) !*ast.Node {
        this.nextToken(); // consume '('

        var parameters = try std.ArrayList([]const u8).initCapacity(this.allocator, 4);
        defer parameters.deinit(this.allocator);
        var rest_param: ?[]const u8 = null;

        while (this.current_token.type != .RParen) {
            if (this.current_token.type == .DotDotDot) {
                this.nextToken(); // consume ...
                if (this.current_token.type == .Identifier or this.current_token.type == .Fn) {
                    rest_param = this.current_token.literal;
                    this.nextToken(); // consume parameter name
                    break; // rest param must be last, exit loop
                } else {
                    return error.ExpectedIdentifier;
                }
            } else
            if (this.current_token.type != .Identifier) {
                return error.ExpectedIdentifier;
            }
            try parameters.append(this.allocator, this.current_token.literal);
            this.nextToken(); // consume parameter

            if (this.current_token.type == .RParen) break;

            if (this.current_token.type != .Comma) {
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }
        this.nextToken(); // consume ')'

        if (this.current_token.type != .Arrow) {
            return error.ExpectedArrow;
        }
        this.nextToken(); // consume '=>'

        const body = try this.parseFunctionBody();

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ArrowFunction = .{
            .parameters = try parameters.toOwnedSlice(this.allocator),
            .body = body,
            .rest_param = rest_param,
        } };
        return node;
    }

    fn parseMemberAccessOrCall(this: *Parser, object: *ast.Node) anyerror!*ast.Node {
        // Si esta función falla, debemos liberar el object
        errdefer ast.freeAst(this.allocator, object);

        this.nextToken(); // consume '.'

        if (!isPropertyName(this.current_token.type)) {
            return error.ExpectedIdentifier;
        }

        const property = this.current_token.literal;
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

        // After parsing the whole literal, current_token = .EOF —
        // parseObjectLiteral's final `nextToken()` consumes `}`, and
        // with no further input the lexer returns EOF. Both properties
        // were consumed cleanly without comma greediness seizing the
        // next key as a CommaExpression operand.
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
