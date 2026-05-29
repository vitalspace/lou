const std = @import("std");

pub const TokenType = enum {
    Integer, // Enteros como 42
    Float, // Flotantes como 3.14
    String,
    TemplateString, // Template strings with backticks `...`
    Identifier,

    // Arithmetic
    Plus,
    Minus,
    Multiply,
    Divide,
    Modulo, // %
    Increment, // ++
    Decrement, // --

    // Assignment
    Assign, // =
    PlusAssign, // +=
    MinusAssign, // -=
    MultiplyAssign, // *=
    DivideAssign, // /=
    ModuloAssign, // %=

    // Comparison
    LessThan, // <
    LessThanOrEqual, // <=
    GreaterThan, // >
    GreaterThanOrEqual, // >=
    Equal, // ==
    NotEqual, // !=
    StrictEqual, // ===
    StrictNotEqual, // !==

    // Logical
    And, // &&
    Or, // ||
    Not, // !

    // Bitwise
    BitAnd, // &
    BitOr, // |
    BitXor, // ^
    BitNot, // ~
    LeftShift, // <<
    RightShift, // >>

    // Nullish coalescing
    Nullish, // ??

    // Pipeline
    Pipe, // |>

    // Ternary
    Question, // ?
    Colon, // :

    // Keywords
    Const,
    Var,
    Let,
    Null,
    Undefined,
    True,
    False,
    Fn,
    Return,
    If,
    Else,
    For,
    While,
    In,
    Of,
    Break,
    Continue,
    Switch,
    Case,
    Default,
    Match,
    Yield,
    New,

    // Module system
    Import,
    From,
    As,
    Export,

    // Delimiters
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Semicolon,
    Comma,
    Dot,
    DotDot, // ..
    DotDotDot, // ...

    // Special
    Arrow, // =>
    EOF,
};

pub const Token = struct {
    type: TokenType,
    literal: []const u8,
};

pub const Lexer = struct {
    input: []const u8,
    position: usize,
    read_position: usize,
    ch: u8,

    pub fn init(input: []const u8) Lexer {
        var l = Lexer{
            .input = input,
            .position = 0,
            .read_position = 0,
            .ch = 0,
        };
        l.readChar();
        return l;
    }

    pub fn nextToken(this: *Lexer) Token {
        while (true) {
            this.skipWhitespace();
            if (this.ch == '/' and (this.peekChar() == '/' or this.peekChar() == '*')) {
                this.skipComments();
            } else {
                break;
            }
        }

        const tok: Token = switch (this.ch) {
            '+' => blk: {
                if (this.peekChar() == '+') {
                    this.readChar();
                    break :blk .{ .type = .Increment, .literal = "++" };
                } else if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .PlusAssign, .literal = "+=" };
                } else {
                    break :blk .{ .type = .Plus, .literal = "+" };
                }
            },
            '-' => blk: {
                if (this.peekChar() == '-') {
                    this.readChar();
                    break :blk .{ .type = .Decrement, .literal = "--" };
                } else if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .MinusAssign, .literal = "-=" };
                } else {
                    break :blk .{ .type = .Minus, .literal = "-" };
                }
            },
            '*' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .MultiplyAssign, .literal = "*=" };
                } else {
                    break :blk .{ .type = .Multiply, .literal = "*" };
                }
            },
            '/' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .DivideAssign, .literal = "/=" };
                } else {
                    break :blk .{ .type = .Divide, .literal = "/" };
                }
            },
            '%' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .ModuloAssign, .literal = "%=" };
                } else {
                    break :blk .{ .type = .Modulo, .literal = "%" };
                }
            },
            '<' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .LessThanOrEqual, .literal = "<=" };
                } else if (this.peekChar() == '<') {
                    this.readChar();
                    break :blk .{ .type = .LeftShift, .literal = "<<" };
                } else {
                    break :blk .{ .type = .LessThan, .literal = "<" };
                }
            },
            '>' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .GreaterThanOrEqual, .literal = ">=" };
                } else if (this.peekChar() == '>') {
                    this.readChar();
                    break :blk .{ .type = .RightShift, .literal = ">>" };
                } else {
                    break :blk .{ .type = .GreaterThan, .literal = ">" };
                }
            },
            '&' => blk: {
                if (this.peekChar() == '&') {
                    this.readChar();
                    break :blk .{ .type = .And, .literal = "&&" };
                } else {
                    break :blk .{ .type = .BitAnd, .literal = "&" };
                }
            },
            '|' => blk: {
                if (this.peekChar() == '|') {
                    this.readChar();
                    break :blk .{ .type = .Or, .literal = "||" };
                } else if (this.peekChar() == '>') {
                    this.readChar();
                    break :blk .{ .type = .Pipe, .literal = "|>" };
                } else {
                    break :blk .{ .type = .BitOr, .literal = "|" };
                }
            },
            '^' => .{ .type = .BitXor, .literal = "^" },
            '~' => .{ .type = .BitNot, .literal = "~" },
            '!' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .StrictNotEqual, .literal = "!==" };
                    } else {
                        break :blk .{ .type = .NotEqual, .literal = "!=" };
                    }
                } else {
                    // FIX: Return Not instead of EOF for standalone !
                    break :blk .{ .type = .Not, .literal = "!" };
                }
            },
            '=' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .StrictEqual, .literal = "===" };
                    } else {
                        break :blk .{ .type = .Equal, .literal = "==" };
                    }
                } else if (this.peekChar() == '>') {
                    this.readChar();
                    break :blk .{ .type = .Arrow, .literal = "=>" };
                } else {
                    break :blk .{ .type = .Assign, .literal = "=" };
                }
            },
            '?' => blk: {
                if (this.peekChar() == '?') {
                    this.readChar();
                    break :blk .{ .type = .Nullish, .literal = "??" };
                } else {
                    break :blk .{ .type = .Question, .literal = "?" };
                }
            },
            ':' => .{ .type = .Colon, .literal = ":" },
            '(' => .{ .type = .LParen, .literal = "(" },
            ')' => .{ .type = .RParen, .literal = ")" },
            '{' => .{ .type = .LBrace, .literal = "{" },
            '}' => .{ .type = .RBrace, .literal = "}" },
            '[' => .{ .type = .LBracket, .literal = "[" },
            ']' => .{ .type = .RBracket, .literal = "]" },
            ';' => .{ .type = .Semicolon, .literal = ";" },
            ',' => .{ .type = .Comma, .literal = "," },
            '.' => blk: {
                if (this.peekChar() == '.') {
                    this.readChar();
                    if (this.peekChar() == '.') {
                        this.readChar();
                        break :blk .{ .type = .DotDotDot, .literal = "..." };
                    }
                    break :blk .{ .type = .DotDot, .literal = ".." };
                } else {
                    break :blk .{ .type = .Dot, .literal = "." };
                }
            },
            0 => return .{ .type = .EOF, .literal = "" },
            '"' => return this.readString('"'),
            '\'' => return this.readString('\''),
            '`' => return this.readTemplateString(),
            else => if (std.ascii.isDigit(this.ch)) {
                const start = this.position;
                while (std.ascii.isDigit(this.ch)) {
                    this.readChar();
                }
                if (this.ch == '.') {
                    this.readChar();
                    while (std.ascii.isDigit(this.ch)) {
                        this.readChar();
                    }
                    return .{ .type = .Float, .literal = this.input[start..this.position] };
                }
                return .{ .type = .Integer, .literal = this.input[start..this.position] };
            } else if (std.ascii.isAlphabetic(this.ch) or this.ch == '_') {
                const start = this.position;
                while (std.ascii.isAlphabetic(this.ch) or std.ascii.isDigit(this.ch) or this.ch == '_') {
                    this.readChar();
                }
                const literal = this.input[start..this.position];
                const token_type: TokenType = getKeywordType(literal);
                return .{ .type = token_type, .literal = literal };
            } else {
                return .{ .type = .EOF, .literal = "" };
            },
        };

        this.readChar();
        return tok;
    }

    fn readChar(this: *Lexer) void {
        if (this.read_position >= this.input.len) {
            this.ch = 0;
        } else {
            this.ch = this.input[this.read_position];
        }
        this.position = this.read_position;
        this.read_position += 1;
    }

    fn peekChar(this: *Lexer) u8 {
        if (this.read_position >= this.input.len) {
            return 0;
        } else {
            return this.input[this.read_position];
        }
    }

    fn skipWhitespace(this: *Lexer) void {
        while (this.ch == ' ' or this.ch == '\t' or this.ch == '\n' or this.ch == '\r') {
            this.readChar();
        }
    }

    fn skipComments(this: *Lexer) void {
        // Single-line comments: // ...
        if (this.ch == '/' and this.peekChar() == '/') {
            while (this.ch != '\n' and this.ch != '\r' and this.ch != 0) {
                this.readChar();
            }
        }
        // Multi-line comments: /* ... */
        else if (this.ch == '/' and this.peekChar() == '*') {
            this.readChar(); // consume '/'
            this.readChar(); // consume '*'
            while (this.ch != 0) {
                if (this.ch == '*' and this.peekChar() == '/') {
                    this.readChar(); // consume '*'
                    this.readChar(); // consume '/'
                    break;
                }
                this.readChar();
            }
        }
    }

    fn readString(this: *Lexer, delimiter: u8) Token {
        const start = this.position + 1; // skip opening quote
        this.readChar(); // consume opening quote
        while (this.ch != delimiter and this.ch != 0) {
            this.readChar();
        }
        if (this.ch == 0) {
            return .{ .type = .EOF, .literal = "" }; // unterminated string
        }
        const literal = this.input[start..this.position];
        this.readChar(); // consume closing quote
        return .{ .type = .String, .literal = literal };
    }

    fn readTemplateString(this: *Lexer) Token {
        const start = this.position + 1; // skip opening backtick
        this.readChar(); // consume opening backtick
        while (this.ch != '`' and this.ch != 0) {
            // Skip escaped backticks
            if (this.ch == '\\' and this.peekChar() == '`') {
                this.readChar();
                this.readChar();
            } else {
                this.readChar();
            }
        }
        if (this.ch == 0) {
            return .{ .type = .EOF, .literal = "" }; // unterminated template string
        }
        const literal = this.input[start..this.position];
        this.readChar(); // consume closing backtick
        return .{ .type = .TemplateString, .literal = literal };
    }
};

pub fn main() !void {
    const input = "3 + 4 * 2 - 1 * 10 / 2 + 5 * 8";
    var lexer = Lexer.init(input);
    const tok = lexer.nextToken();
    std.debug.print("Token: {s}\n", .{tok.literal});
}

fn getKeywordType(literal: []const u8) TokenType {
    const map = std.StaticStringMap(TokenType).initComptime(.{
        .{ "const", .Const },
        .{ "var", .Var },
        .{ "let", .Let },
        .{ "null", .Null },
        .{ "undefined", .Undefined },
        .{ "true", .True },
        .{ "false", .False },
        .{ "fn", .Fn },
        .{ "function", .Fn },
        .{ "return", .Return },
        .{ "if", .If },
        .{ "else", .Else },
        .{ "for", .For },
        .{ "while", .While },
        .{ "in", .In },
        .{ "of", .Of },
        .{ "break", .Break },
        .{ "continue", .Continue },
        .{ "switch", .Switch },
        .{ "case", .Case },
        .{ "default", .Default },
        .{ "match", .Match },
        .{ "yield", .Yield },
        .{ "import", .Import },
        .{ "from", .From },
        .{ "as", .As },
        .{ "export", .Export },
        .{ "new", .New },
    });
    return map.get(literal) orelse .Identifier;
}

// ============================================================================
// Tests
// ============================================================================

test "integer tokens" {
    const input = "42 123 0 9999";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "42" },
        .{ .type = .Integer, .literal = "123" },
        .{ .type = .Integer, .literal = "0" },
        .{ .type = .Integer, .literal = "9999" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "float tokens" {
    const input = "3.14 0.5 123.456";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Float, .literal = "3.14" },
        .{ .type = .Float, .literal = "0.5" },
        .{ .type = .Float, .literal = "123.456" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "string tokens" {
    const input =
        \\"hello" "world" "foo bar"
    ;
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .String, .literal = "hello" },
        .{ .type = .String, .literal = "world" },
        .{ .type = .String, .literal = "foo bar" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "template strings" {
    const input = "`hello ${name}` `test`";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .TemplateString, .literal = "hello ${name}" },
        .{ .type = .TemplateString, .literal = "test" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "identifiers" {
    const input = "foo _bar baz123 _test_";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Identifier, .literal = "foo" },
        .{ .type = .Identifier, .literal = "_bar" },
        .{ .type = .Identifier, .literal = "baz123" },
        .{ .type = .Identifier, .literal = "_test_" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "keywords" {
    const input = "const var let null undefined true false fn function return if else for while in break continue switch case default match";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Const, .literal = "const" },
        .{ .type = .Var, .literal = "var" },
        .{ .type = .Let, .literal = "let" },
        .{ .type = .Null, .literal = "null" },
        .{ .type = .Undefined, .literal = "undefined" },
        .{ .type = .True, .literal = "true" },
        .{ .type = .False, .literal = "false" },
        .{ .type = .Fn, .literal = "fn" },
        .{ .type = .Fn, .literal = "function" },
        .{ .type = .Return, .literal = "return" },
        .{ .type = .If, .literal = "if" },
        .{ .type = .Else, .literal = "else" },
        .{ .type = .For, .literal = "for" },
        .{ .type = .While, .literal = "while" },
        .{ .type = .In, .literal = "in" },
        .{ .type = .Break, .literal = "break" },
        .{ .type = .Continue, .literal = "continue" },
        .{ .type = .Switch, .literal = "switch" },
        .{ .type = .Case, .literal = "case" },
        .{ .type = .Default, .literal = "default" },
        .{ .type = .Match, .literal = "match" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "single character operators" {
    const input = "+ - * / % & | ^ ~";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Minus, .literal = "-" },
        .{ .type = .Multiply, .literal = "*" },
        .{ .type = .Divide, .literal = "/" },
        .{ .type = .Modulo, .literal = "%" },
        .{ .type = .BitAnd, .literal = "&" },
        .{ .type = .BitOr, .literal = "|" },
        .{ .type = .BitXor, .literal = "^" },
        .{ .type = .BitNot, .literal = "~" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "logical operators" {
    const input = "&& || !";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .And, .literal = "&&" },
        .{ .type = .Or, .literal = "||" },
        .{ .type = .Not, .literal = "!" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "comparison operators" {
    const input = "< <= > >= == === != !==";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .LessThan, .literal = "<" },
        .{ .type = .LessThanOrEqual, .literal = "<=" },
        .{ .type = .GreaterThan, .literal = ">" },
        .{ .type = .GreaterThanOrEqual, .literal = ">=" },
        .{ .type = .Equal, .literal = "==" },
        .{ .type = .StrictEqual, .literal = "===" },
        .{ .type = .NotEqual, .literal = "!=" },
        .{ .type = .StrictNotEqual, .literal = "!==" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "bit shift operators" {
    const input = "<< >>";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .LeftShift, .literal = "<<" },
        .{ .type = .RightShift, .literal = ">>" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "compound assignment operators" {
    const input = "+= -= *= /= %=";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .PlusAssign, .literal = "+=" },
        .{ .type = .MinusAssign, .literal = "-=" },
        .{ .type = .MultiplyAssign, .literal = "*=" },
        .{ .type = .DivideAssign, .literal = "/=" },
        .{ .type = .ModuloAssign, .literal = "%=" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "increment and decrement operators" {
    const input = "++ --";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Increment, .literal = "++" },
        .{ .type = .Decrement, .literal = "--" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "ternary and nullish" {
    const input = "? ??";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Question, .literal = "?" },
        .{ .type = .Nullish, .literal = "??" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "pipeline operator" {
    const input = "|>";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Pipe, .literal = "|>" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "assignment and arrow" {
    const input = "= => :";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Assign, .literal = "=" },
        .{ .type = .Arrow, .literal = "=>" },
        .{ .type = .Colon, .literal = ":" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "punctuation" {
    const input = "( ) { } [ ] ; , . ..";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .LBracket, .literal = "[" },
        .{ .type = .RBracket, .literal = "]" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .Comma, .literal = "," },
        .{ .type = .Dot, .literal = "." },
        .{ .type = .DotDot, .literal = ".." },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "whitespace handling" {
    const input = "3 \t\n + \r\n 4";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "3" },
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Integer, .literal = "4" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "single line comments" {
    const input = "42 // this is a comment\n+ 1";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "42" },
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Integer, .literal = "1" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "multi line comments" {
    const input = "42 /* this is a\nmultiline comment */ + 1";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "42" },
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Integer, .literal = "1" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "complex expression" {
    const input = "const x = 42 + 3.14 * 2;";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Const, .literal = "const" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .Assign, .literal = "=" },
        .{ .type = .Integer, .literal = "42" },
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Float, .literal = "3.14" },
        .{ .type = .Multiply, .literal = "*" },
        .{ .type = .Integer, .literal = "2" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "function declaration" {
    const input = "fn add(a, b) { return a + b; }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Fn, .literal = "fn" },
        .{ .type = .Identifier, .literal = "add" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "a" },
        .{ .type = .Comma, .literal = "," },
        .{ .type = .Identifier, .literal = "b" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Return, .literal = "return" },
        .{ .type = .Identifier, .literal = "a" },
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Identifier, .literal = "b" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "for loop" {
    const input = "for (var i = 0; i < 10; i++) { print(i); }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .For, .literal = "for" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Var, .literal = "var" },
        .{ .type = .Identifier, .literal = "i" },
        .{ .type = .Assign, .literal = "=" },
        .{ .type = .Integer, .literal = "0" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .Identifier, .literal = "i" },
        .{ .type = .LessThan, .literal = "<" },
        .{ .type = .Integer, .literal = "10" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .Identifier, .literal = "i" },
        .{ .type = .Increment, .literal = "++" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Identifier, .literal = "print" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "i" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "arrow function" {
    const input = "const double = (x) => x * 2;";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Const, .literal = "const" },
        .{ .type = .Identifier, .literal = "double" },
        .{ .type = .Assign, .literal = "=" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .Arrow, .literal = "=>" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .Multiply, .literal = "*" },
        .{ .type = .Integer, .literal = "2" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "range with dotdot" {
    const input = "for (i in 0 .. 10) { print(i); }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .For, .literal = "for" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "i" },
        .{ .type = .In, .literal = "in" },
        .{ .type = .Integer, .literal = "0" },
        .{ .type = .DotDot, .literal = ".." },
        .{ .type = .Integer, .literal = "10" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Identifier, .literal = "print" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "i" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "for...of loop" {
    const input = "for (const x of arr) { print(x); }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .For, .literal = "for" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Const, .literal = "const" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .Of, .literal = "of" },
        .{ .type = .Identifier, .literal = "arr" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Identifier, .literal = "print" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "boolean and conditionals" {
    const input = "if (true) { return false; } else { return true; }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .If, .literal = "if" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .True, .literal = "true" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Return, .literal = "return" },
        .{ .type = .False, .literal = "false" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .Else, .literal = "else" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Return, .literal = "return" },
        .{ .type = .True, .literal = "true" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "logical expression with not" {
    const input = "!true && false || !x";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Not, .literal = "!" },
        .{ .type = .True, .literal = "true" },
        .{ .type = .And, .literal = "&&" },
        .{ .type = .False, .literal = "false" },
        .{ .type = .Or, .literal = "||" },
        .{ .type = .Not, .literal = "!" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "nullish coalescing" {
    const input = "x ?? y ?? null";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .Nullish, .literal = "??" },
        .{ .type = .Identifier, .literal = "y" },
        .{ .type = .Nullish, .literal = "??" },
        .{ .type = .Null, .literal = "null" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "switch statement" {
    const input = "switch (x) { case 1: break; default: break; }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Switch, .literal = "switch" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Case, .literal = "case" },
        .{ .type = .Integer, .literal = "1" },
        .{ .type = .Colon, .literal = ":" },
        .{ .type = .Break, .literal = "break" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .Default, .literal = "default" },
        .{ .type = .Colon, .literal = ":" },
        .{ .type = .Break, .literal = "break" },
        .{ .type = .Semicolon, .literal = ";" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "match expression" {
    const input = "match x { 1 => 'one', _ => 'other' }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Match, .literal = "match" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .LBrace, .literal = "{" },
        .{ .type = .Integer, .literal = "1" },
        .{ .type = .Arrow, .literal = "=>" },
        .{ .type = .String, .literal = "one" },
        .{ .type = .Comma, .literal = "," },
        .{ .type = .Identifier, .literal = "_" },
        .{ .type = .Arrow, .literal = "=>" },
        .{ .type = .String, .literal = "other" },
        .{ .type = .RBrace, .literal = "}" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "pipeline expression" {
    const input = "x |> double |> add(1)";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .Pipe, .literal = "|>" },
        .{ .type = .Identifier, .literal = "double" },
        .{ .type = .Pipe, .literal = "|>" },
        .{ .type = .Identifier, .literal = "add" },
        .{ .type = .LParen, .literal = "(" },
        .{ .type = .Integer, .literal = "1" },
        .{ .type = .RParen, .literal = ")" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}
