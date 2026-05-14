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

    pub fn deinit(this: *Parser) void {
        this.arena.deinit();
        this.arena_child.destroy(this.arena);
    }

    pub fn parseExpression(this: *Parser) !*ast.Node {
        return try this.parsePrecedece(.lowest);
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
        switch (this.current_token.type) {
            .Const => return try this.parseConstantDeclaration(),
            .Var => return try this.parseVariableDeclaration(),
            .Let => return try this.parseLetDeclaration(),
            .For => return try this.parseForLoop(),
            .While => return try this.parseWhileLoop(),
            .If => return try this.parseIfStatement(),
            .Return => return try this.parseReturnStatement(),
            .Fn => return try this.parseFunctionDeclaration(),
            .Import => return try this.parseImportStatement(),
            .Export => return try this.parseExportStatement(),
            .Identifier => {
                if (this.peek_token.type == .Assign) {
                    const name = this.current_token.literal;
                    this.nextToken(); // consume identifier
                    this.nextToken(); // consume =
                    const value = try this.parseExpression();
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .Assignment = .{
                        .name = name,
                        .value = value,
                    } };
                    return node;
                } else if (this.peek_token.type == .Dot or this.peek_token.type == .LBracket) {
                    const expr = try this.parseExpression();
                    if (this.current_token.type == .Assign) {
                        if (expr.* == .MemberAccess) {
                            const key = expr.MemberAccess.property;
                            const object = expr.MemberAccess.object;
                            this.allocator.destroy(expr);
                            this.nextToken(); // consume '='
                            const value = try this.parseExpression();
                            const node = try this.allocator.create(ast.Node);
                            node.* = .{ .PropertySet = .{ .object = object, .key = key, .value = value } };
                            return node;
                        }
                        return error.InvalidAssignmentTarget;
                    }
                    return expr;
                } else {
                    return try this.parseExpression();
                }
            },
            .LBrace => return try this.parseBlockStatement(),
            else => return try this.parseExpression(),
        }
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

        return left;
    }

    fn parsePrimary(this: *Parser) !*ast.Node {
        switch (this.current_token.type) {
            .Integer => return try this.parseIntegerLiteral(),
            .Float => return try this.parseFloatLiteral(),
            .String => return try this.parseStringLiteral(),
            .TemplateString => return try this.parseStringLiteral(),
            .True => return try this.parseBooleanLiteral(true),
            .False => return try this.parseBooleanLiteral(false),
            .Null, .Undefined => {
                const node = try this.allocator.create(ast.Node);
                if (this.current_token.type == .Null) {
                    node.* = .{ .NullLiteral = .{} };
                } else {
                    node.* = .{ .VoidLiteral = .{} };
                }
                this.nextToken();
                return node;
            },
            .LBracket => {
                var base = try this.parseArrayLiteral();

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

                return base;
            },
            .Identifier => {
                var base = try this.parseIdentifier();

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
                    node.* = .{ .Assignment = .{
                        .name = base.Identifier.name,
                        .value = try this.parseBinaryExpression(.{ .Identifier = .{ .name = base.Identifier.name } }, .Plus, .{ .FloatLiteral = .{ .value = 1.0 } }),
                    } };
                    ast.freeAst(this.allocator, base);
                    return node;
                }

                // Post-decrement: i--
                if (this.current_token.type == .Decrement and base.* == .Identifier) {
                    this.nextToken(); // consume --
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .Assignment = .{
                        .name = base.Identifier.name,
                        .value = try this.parseBinaryExpression(.{ .Identifier = .{ .name = base.Identifier.name } }, .Minus, .{ .FloatLiteral = .{ .value = 1.0 } }),
                    } };
                    ast.freeAst(this.allocator, base);
                    return node;
                }

                return base;
            },
            .LParen => return try this.parseArrowFunction(),
            .Increment => {
                // Handle pre-increment operator like ++i
                this.nextToken();
                if (this.current_token.type == .Identifier) {
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .Assignment = .{
                        .name = this.current_token.literal,
                        .value = try this.parseBinaryExpression(.{ .Identifier = .{ .name = this.current_token.literal } }, .Plus, .{ .FloatLiteral = .{ .value = 1.0 } }),
                    } };
                    this.nextToken();
                    return node;
                } else {
                    return error.UnexpectedToken;
                }
            },
            .Minus => {
                // Handle minus: could be negative number or -- prefix already handled by lexer
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
                    return error.UnexpectedToken;
                }
            },
            .Decrement => {
                // Handle pre-decrement operator like --i
                this.nextToken();
                if (this.current_token.type == .Identifier) {
                    const node = try this.allocator.create(ast.Node);
                    node.* = .{ .Assignment = .{
                        .name = this.current_token.literal,
                        .value = try this.parseBinaryExpression(.{ .Identifier = .{ .name = this.current_token.literal } }, .Minus, .{ .FloatLiteral = .{ .value = 1.0 } }),
                    } };
                    this.nextToken();
                    return node;
                } else {
                    return error.UnexpectedToken;
                }
            },
            .LBrace => {
                var base = try this.parseObjectLiteral();
                while (true) {
                    if (this.current_token.type == .LBracket) {
                        base = try this.parseArrayIndex(base);
                    } else if (this.current_token.type == .Dot) {
                        base = try this.parseMemberAccessOrCall(base);
                    } else {
                        break;
                    }
                }
                return base;
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

    fn parseStringLiteral(this: *Parser) !*ast.Node {
        const node = try this.allocator.create(ast.Node);
        node.* = .{ .StringLiteral = .{ .value = this.current_token.literal } };
        this.nextToken();
        return node;
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
            const element = try this.parseExpression();
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
            const key = switch (this.current_token.type) {
                .String => this.current_token.literal,
                .Identifier => this.current_token.literal,
                else => return error.ExpectedPropertyName,
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

        // Parse initialization (optional)
        var init_stmt: ?*ast.Node = null;
        if (this.current_token.type != .Semicolon) {
            init_stmt = try this.parseStatement();
        }
        if (this.current_token.type != .Semicolon) {
            // Clean up on error
            if (init_stmt) |init_node| {
                ast.freeAst(this.allocator, init_node);
            }
            return error.ExpectedSemicolon;
        }
        this.nextToken(); // consume ';'

        // Parse condition (optional)
        var condition: ?*ast.Node = null;
        if (this.current_token.type != .Semicolon) {
            condition = try this.parseExpression();
        }
        if (this.current_token.type != .Semicolon) {
            // Clean up on error
            if (init_stmt) |init_node| {
                ast.freeAst(this.allocator, init_node);
            }

            if (condition) |cond_node| {
                ast.freeAst(this.allocator, cond_node);
            }
            return error.ExpectedSemicolon;
        }
        this.nextToken(); // consume ';'

        // Parse increment (optional) - debe ser una expresión, no un statement
        var increment: ?*ast.Node = null;
        if (this.current_token.type != .RParen) {
            increment = try this.parseExpression();
        }
        if (this.current_token.type != .RParen) {
            // Clean up on error
            if (init_stmt) |init_node| {
                ast.freeAst(this.allocator, init_node);
            }
            if (condition) |cond_node| {
                ast.freeAst(this.allocator, cond_node);
            }
            if (increment) |inc_node| {
                ast.freeAst(this.allocator, inc_node);
            }
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

        const condition = try this.parseExpression();

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

    fn parseIfStatement(this: *Parser) !*ast.Node {
        this.nextToken(); // consume 'if'
        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        const condition = try this.parseExpression();

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

    fn parseFunctionDeclaration(this: *Parser) !*ast.Node {
        var name: []const u8 = "";
        if (this.peek_token.type == .Identifier) {
            this.nextToken(); // consume 'fn'
            name = this.current_token.literal;
            this.nextToken(); // consume identifier
        } else {
            this.nextToken(); // consume 'fn' (anonymous function)
        }

        if (this.current_token.type != .LParen) {
            return error.ExpectedLParen;
        }
        this.nextToken(); // consume '('

        var parameters = try std.ArrayList([]const u8).initCapacity(this.allocator, 4);
        defer parameters.deinit(this.allocator);

        while (this.current_token.type != .RParen) {
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

        const body = try this.parseStatement();

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .FunctionDeclaration = .{
            .name = name,
            .parameters = try parameters.toOwnedSlice(this.allocator),
            .body = body,
        } };
        return node;
    }

    fn parseArrowFunction(this: *Parser) !*ast.Node {
        this.nextToken(); // consume '('

        var parameters = try std.ArrayList([]const u8).initCapacity(this.allocator, 4);
        defer parameters.deinit(this.allocator);

        while (this.current_token.type != .RParen) {
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

        const body = try this.parseStatement();

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .ArrowFunction = .{
            .parameters = try parameters.toOwnedSlice(this.allocator),
            .body = body,
        } };
        return node;
    }

    fn parseMemberAccessOrCall(this: *Parser, object: *ast.Node) anyerror!*ast.Node {
        // Si esta función falla, debemos liberar el object
        errdefer ast.freeAst(this.allocator, object);

        this.nextToken(); // consume '.'

        if (this.current_token.type != .Identifier) {
            return error.ExpectedIdentifier;
        }

        const property = this.current_token.literal;
        this.nextToken(); // consume property name

        // Si hay paréntesis, es una llamada a método
        if (this.current_token.type == .LParen) {
            this.nextToken(); // consume '('

            var arguments = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
            defer arguments.deinit(this.allocator);
            errdefer {
                for (arguments.items) |arg| {
                    ast.freeAst(this.allocator, arg);
                }
            }

            while (this.current_token.type != .RParen) {
                const arg = try this.parseExpression();
                // ⭐ CRÍTICO: errdefer INMEDIATAMENTE después de parsear
                errdefer ast.freeAst(this.allocator, arg);

                try arguments.append(this.allocator, arg);

                if (this.current_token.type == .RParen) break;

                if (this.current_token.type != .Comma) {
                    return error.ExpectedComma;
                }
                this.nextToken(); // consume ','
            }
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

    fn parseFunctionCall(this: *Parser) anyerror!*ast.Node {
        const name = this.current_token.literal;
        this.nextToken(); // consume identifier
        this.nextToken(); // consume '('

        var arguments = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
        defer arguments.deinit(this.allocator);
        errdefer {
            for (arguments.items) |arg| {
                ast.freeAst(this.allocator, arg);
            }
        }

        while (this.current_token.type != .RParen) {
            const arg = try this.parseExpression();
            // ⭐ CRÍTICO: errdefer INMEDIATAMENTE después de parsear
            errdefer ast.freeAst(this.allocator, arg);

            try arguments.append(this.allocator, arg);

            if (this.current_token.type == .RParen) break;

            if (this.current_token.type != .Comma) {
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }
        this.nextToken(); // consume ')'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .FunctionCall = .{
            .name = name,
            .arguments = try arguments.toOwnedSlice(this.allocator),
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

    fn parseFunctionCallFromBase(this: *Parser, base: *ast.Node) anyerror!*ast.Node {
        if (base.* != .Identifier) {
            ast.freeAst(this.allocator, base);
            return error.InvalidFunctionCall;
        }

        const name = base.Identifier.name;
        ast.freeAst(this.allocator, base);
        this.nextToken(); // consume '('

        var arguments = try std.ArrayList(*ast.Node).initCapacity(this.allocator, 4);
        defer arguments.deinit(this.allocator);
        errdefer {
            for (arguments.items) |arg| {
                ast.freeAst(this.allocator, arg);
            }
        }

        while (this.current_token.type != .RParen) {
            const arg = try this.parseExpression();
            // ⭐ CRÍTICO: errdefer INMEDIATAMENTE después de parsear
            errdefer ast.freeAst(this.allocator, arg);

            try arguments.append(this.allocator, arg);

            if (this.current_token.type == .RParen) break;

            if (this.current_token.type != .Comma) {
                return error.ExpectedComma;
            }
            this.nextToken(); // consume ','
        }
        this.nextToken(); // consume ')'

        const node = try this.allocator.create(ast.Node);
        node.* = .{ .FunctionCall = .{
            .name = name,
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
