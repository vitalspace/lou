const std = @import("std");

pub const TokenType = enum {
    Integer, // Enteros como 42
    Float, // Flotantes como 3.14
    BigInt, // BigInt como 42n (digit literal with 'n' suffix)
    String,
    TemplateString, // Template strings with backticks `...`
    Identifier,

    // Arithmetic
    Plus,
    Minus,
    Multiply,
    Exponent, // **
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
    PowerAssign, // **=

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
    AndAssign, // &&=
    OrAssign, // ||=
    NullishAssign, // ??=

    // Bitwise
    BitAnd, // &
    BitOr, // |
    BitXor, // ^
    BitNot, // ~
    LeftShift, // <<
    RightShift, // >>
    UnsignedRightShift, // >>>
    LeftShiftAssign, // <<=
    RightShiftAssign, // >>=
    UnsignedRightShiftAssign, // >>>=

    // Nullish coalescing
    Nullish, // ??

    // Pipeline
    Pipe, // |>

    // Ternary
    Question, // ?
    QuestionDot, // ?.
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
    Do,
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
    Delete,
    InstanceOf,
    TypeOf,
    Void,
    Class,
    Extends,
    Super,
    Static,
    Get,
    Set,
    Hash,

    // Module system
    Import,
    From,
    As,
    Export,
    Try,
    Catch,
    Finally,
    Throw,
    Using,
    Await,
    Async,

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
    Regex, // /pattern/flags
    EOF,
};

pub const Token = struct {
    type: TokenType,
    literal: []const u8,
    regex_flags: []const u8 = "",
    line: u32 = 0,
};

pub const Lexer = struct {
    input: []const u8,
    position: usize,
    read_position: usize,
    ch: u8,
    line: u32 = 1,
    prev_token_type: TokenType = .EOF,

    pub fn init(input: []const u8) Lexer {
        var l = Lexer{
            .input = input,
            .position = 0,
            .read_position = 0,
            .ch = 0,
            .line = 1,
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

        const tok_line = this.line;

        var tok: Token = switch (this.ch) {
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
                } else if (this.peekChar() == '*') {
                    this.readChar(); // consume second '*'
                    if (this.peekChar() == '=') {
                        this.readChar(); // consume '='
                        break :blk .{ .type = .PowerAssign, .literal = "**=" };
                    }
                    break :blk .{ .type = .Exponent, .literal = "**" };
                } else {
                    break :blk .{ .type = .Multiply, .literal = "*" };
                }
            },
            '/' => blk: {
                if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .DivideAssign, .literal = "/=" };
                }
                // Disambiguate division from regex literal: if the previous
                // token could end an expression, '/' is division. Otherwise
                // it starts a regex literal.
                if (canEndExpression(this.prev_token_type)) {
                    break :blk .{ .type = .Divide, .literal = "/" };
                }
                return this.readRegexLiteral(tok_line);
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
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .LeftShiftAssign, .literal = "<<=" };
                    }
                    break :blk .{ .type = .LeftShift, .literal = "<<" };
                } else {
                    break :blk .{ .type = .LessThan, .literal = "<" };
                }
            },
            '>' => blk: {
                if (this.peekChar() == '>') {
                    this.readChar();
                    if (this.peekChar() == '>') {
                        this.readChar();
                        if (this.peekChar() == '=') {
                            this.readChar();
                            break :blk .{ .type = .UnsignedRightShiftAssign, .literal = ">>>=" };
                        }
                        break :blk .{ .type = .UnsignedRightShift, .literal = ">>>" };
                    }
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .RightShiftAssign, .literal = ">>=" };
                    }
                    break :blk .{ .type = .RightShift, .literal = ">>" };
                } else if (this.peekChar() == '=') {
                    this.readChar();
                    break :blk .{ .type = .GreaterThanOrEqual, .literal = ">=" };
                } else {
                    break :blk .{ .type = .GreaterThan, .literal = ">" };
                }
            },
            '&' => blk: {
                if (this.peekChar() == '&') {
                    this.readChar();
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .AndAssign, .literal = "&&=" };
                    }
                    break :blk .{ .type = .And, .literal = "&&" };
                } else {
                    break :blk .{ .type = .BitAnd, .literal = "&" };
                }
            },
            '|' => blk: {
                if (this.peekChar() == '|') {
                    this.readChar();
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .OrAssign, .literal = "||=" };
                    }
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
                    if (this.peekChar() == '=') {
                        this.readChar();
                        break :blk .{ .type = .NullishAssign, .literal = "??=" };
                    }
                    break :blk .{ .type = .Nullish, .literal = "??" };
                } else if (this.peekChar() == '.') {
                    this.readChar();
                    break :blk .{ .type = .QuestionDot, .literal = "?." };
                } else {
                    break :blk .{ .type = .Question, .literal = "?" };
                }
            },
            ':' => .{ .type = .Colon, .literal = ":" },
            '#' => .{ .type = .Hash, .literal = "#" },
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
                } else if (std.ascii.isDigit(this.peekChar())) {
                    // Leading-dot float: .5, .125, .5e-2
                    const start = this.position; // includes the '.'
                    this.readChar(); // consume '.'
                    while (std.ascii.isDigit(this.ch) or this.ch == '_') {
                        if (this.ch == '_') {
                            const next = this.peekChar();
                            if (!std.ascii.isDigit(next)) break;
                            this.readChar();
                        }
                        this.readChar();
                    }
                    if (this.ch == 'e' or this.ch == 'E') {
                        this.readChar(); // consume 'e'/'E'
                        if (this.ch == '+' or this.ch == '-') {
                            this.readChar(); // consume sign
                        }
                        if (std.ascii.isDigit(this.ch) or this.ch == '_') {
                            while (std.ascii.isDigit(this.ch) or this.ch == '_') {
                                if (this.ch == '_') {
                                    const next = this.peekChar();
                                    if (!std.ascii.isDigit(next)) break;
                                    this.readChar();
                                }
                                this.readChar();
                            }
                        }
                    }
                    this.prev_token_type = .Float;
                    return .{ .type = .Float, .literal = this.input[start..this.position], .line = tok_line };
                } else {
                    break :blk .{ .type = .Dot, .literal = "." };
                }
            },
            0 => return .{ .type = .EOF, .literal = "", .line = tok_line },
            '"' => {
                var t = this.readString('"');
                t.line = tok_line;
                return t;
            },
            '\'' => {
                var t = this.readString('\'');
                t.line = tok_line;
                return t;
            },
            '`' => {
                var t = this.readTemplateString();
                t.line = tok_line;
                return t;
            },
            else => if (std.ascii.isDigit(this.ch)) {
                const start = this.position;
                var has_fraction = false;

                // Check for hex/octal/binary prefix: 0xFF, 0o77, 0b1010
                if (this.ch == '0') {
                    this.readChar(); // consume '0'
                    const prefix = this.ch;
                    if (prefix == 'x' or prefix == 'X') {
                        this.readChar(); // consume 'x'
                        if (!std.ascii.isHex(this.ch)) {
                            // Invalid hex: 0x with no hex digits. Return just "0".
                            this.prev_token_type = .Integer;
                            return .{ .type = .Integer, .literal = this.input[start..(start + 1)], .line = tok_line };
                        }
                        while (std.ascii.isHex(this.ch) or this.ch == '_') {
                            if (this.ch == '_') {
                                const next = this.peekChar();
                                if (!std.ascii.isHex(next)) break;
                                this.readChar();
                            }
                            this.readChar();
                        }
                        this.prev_token_type = .Integer;
                        return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
                    } else if (prefix == 'o' or prefix == 'O') {
                        this.readChar(); // consume 'o'
                        if (this.ch < '0' or this.ch > '7') {
                            // Invalid octal: 0o with no octal digits. Return just "0".
                            this.prev_token_type = .Integer;
                            return .{ .type = .Integer, .literal = this.input[start..(start + 1)], .line = tok_line };
                        }
                        while ((this.ch >= '0' and this.ch <= '7') or this.ch == '_') {
                            if (this.ch == '_') {
                                const next = this.peekChar();
                                if (next < '0' or next > '7') break;
                                this.readChar();
                            }
                            this.readChar();
                        }
                        this.prev_token_type = .Integer;
                        return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
                    } else if (prefix == 'b' or prefix == 'B') {
                        this.readChar(); // consume 'b'
                        if (this.ch != '0' and this.ch != '1') {
                            // Invalid binary: 0b with no binary digits. Return just "0".
                            this.prev_token_type = .Integer;
                            return .{ .type = .Integer, .literal = this.input[start..(start + 1)], .line = tok_line };
                        }
                        while (this.ch == '0' or this.ch == '1' or this.ch == '_') {
                            if (this.ch == '_') {
                                const next = this.peekChar();
                                if (next != '0' and next != '1') break;
                                this.readChar();
                            }
                            this.readChar();
                        }
                        this.prev_token_type = .Integer;
                        return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
                    }
                    // Not a hex/oct/binary prefix — continue with normal decimal parsing.
                    // '0' has already been consumed; position is at the non-prefix char.
                }

                while (std.ascii.isDigit(this.ch) or this.ch == '_') {
                    if (this.ch == '_') {
                        const next = this.peekChar();
                        if (!std.ascii.isDigit(next)) break;
                        this.readChar();
                    }
                    this.readChar();
                }
                if (this.ch == '.') {
                    has_fraction = true;
                    this.readChar();
                    while (std.ascii.isDigit(this.ch) or this.ch == '_') {
                        if (this.ch == '_') {
                            const next = this.peekChar();
                            if (!std.ascii.isDigit(next)) break;
                            this.readChar();
                        }
                        this.readChar();
                    }
                }
                // Exponential notation: 1e10, 3.14e-2, 2.5E+3, 1e-5
                if (this.ch == 'e' or this.ch == 'E') {
                    this.readChar(); // consume 'e'/'E'
                    if (this.ch == '+' or this.ch == '-') {
                        this.readChar(); // consume sign
                    }
                    if (!std.ascii.isDigit(this.ch)) {
                        // Invalid exponent: e with no digits. Backtrack and
                        // return what we have so far as a plain number.
                        return .{ .type = if (has_fraction) .Float else .Integer, .literal = this.input[start..this.position], .line = tok_line };
                    }
                    while (std.ascii.isDigit(this.ch) or this.ch == '_') {
                        if (this.ch == '_') {
                            const next = this.peekChar();
                            if (!std.ascii.isDigit(next)) break;
                            this.readChar();
                        }
                        this.readChar();
                    }
                    this.prev_token_type = .Float;
                    return .{ .type = .Float, .literal = this.input[start..this.position], .line = tok_line };
                }
                if (this.ch == 'n') {
                    // BigInt literal like `42n`. Strip the trailing 'n' from the
                    // literal so downstream code only sees the digit string.
                    this.readChar();
                    this.prev_token_type = .BigInt;
                    return .{ .type = .BigInt, .literal = this.input[start .. this.position - 1], .line = tok_line };
                }
                if (has_fraction) {
                    this.prev_token_type = .Float;
                    return .{ .type = .Float, .literal = this.input[start..this.position], .line = tok_line };
                }
                this.prev_token_type = .Integer;
                return .{ .type = .Integer, .literal = this.input[start..this.position], .line = tok_line };
            } else if (isIdStartByte(this.ch)) {
                const start = this.position;
                // Stop on LineTerminator lead bytes (0x0A, 0x0D are filtered by
                // isIdContinueByte, but U+2028/U+2029 use 0xE2 which is >= 0x80
                // and would otherwise be considered an identifier continuation).
                while (isIdContinueByte(this.ch) and !isLineSeparator(this)) {
                    this.readChar();
                }
                const literal = this.input[start..this.position];
                const token_type: TokenType = getKeywordType(literal);
                this.prev_token_type = token_type;
                return .{ .type = token_type, .literal = literal, .line = tok_line };
            } else {
                return .{ .type = .EOF, .literal = "", .line = tok_line };
            },
        };

        this.readChar();
        tok.line = tok_line;
        this.prev_token_type = tok.type;
        return tok;
    }

    fn readChar(this: *Lexer) void {
        if (this.read_position >= this.input.len) {
            this.ch = 0;
            this.position = this.read_position;
            this.read_position += 1;
        } else {
            this.ch = this.input[this.read_position];
            this.position = this.read_position;
            // Decode UTF-8: advance read_position by the full codepoint byte
            // sequence (1, 2, 3, or 4 bytes). The lead byte is stored in
            // `this.ch` so the dispatch on `this.ch` keeps working for ASCII
            // tokens. Continuation bytes (0x80-0xBF) are never visited
            // individually.
            const seq_len = std.unicode.utf8ByteSequenceLength(this.ch) catch 1;
            const remaining = this.input.len - this.read_position;
            const step: usize = if (seq_len <= remaining) seq_len else 1;
            this.read_position += step;
        }
        // ECMAScript LineTerminator :: <LF> <CR> <LS> <PS>
        if (this.ch == '\n' or isLineSeparator(this)) this.line += 1;
    }

    fn peekChar(this: *Lexer) u8 {
        if (this.read_position >= this.input.len) {
            return 0;
        } else {
            return this.input[this.read_position];
        }
    }

    /// Identifier start: ASCII letter, `_`, `$`, or any byte >= 0x80 (part of
    /// a UTF-8 multi-byte sequence). The pragmatic approach accepts all
    /// non-ASCII bytes as identifier characters; downstream stages treat
    /// literals as opaque UTF-8 byte slices, so this round-trips mappings,
    /// property access, and `typeof`.
    fn isIdStartByte(b: u8) bool {
        return std.ascii.isAlphabetic(b) or b == '_' or b == '$' or b >= 0x80;
    }

    /// Identifier continue: id-start, ASCII digit, or any byte >= 0x80.
    fn isIdContinueByte(b: u8) bool {
        return isIdStartByte(b) or std.ascii.isDigit(b);
    }

    /// True if `this.ch` is the lead byte of U+2028 (LINE SEPARATOR) or
    /// U+2029 (PARAGRAPH SEPARATOR). Both encode as 3-byte UTF-8 sequences
    /// sharing the prefix `0xE2 0x80`; only the third byte differs (`0xA8`
    /// vs `0xA9`). Per ECMAScript, these are valid LineTerminator chars that
    /// parallel LF (`\n`) and CR (`\r`): they terminate single-line comments,
    /// reject regex literals, and increment the source-line counter.
    ///
    /// `readChar` lands `this.ch` on the lead byte and stores the FULL
    /// sequence start in `this.position`, so continuation bytes (0x80, 0xA8,
    /// 0xA9) live at `position + 1` and `position + 2` respectively.
    fn isLineSeparator(this: *Lexer) bool {
        if (this.ch != 0xE2) return false;
        if (this.position + 2 >= this.input.len) return false;
        return this.input[this.position + 1] == 0x80 and
            (this.input[this.position + 2] == 0xA8 or
                this.input[this.position + 2] == 0xA9);
    }

    fn skipWhitespace(this: *Lexer) void {
        // U+2028 / U+2029 act as line terminators between tokens too.
        while (this.ch == ' ' or this.ch == '\t' or this.ch == '\n' or this.ch == '\r' or
            isLineSeparator(this))
        {
            this.readChar();
        }
    }

    fn skipComments(this: *Lexer) void {
        // Single-line comments: // ...
        if (this.ch == '/' and this.peekChar() == '/') {
            // Comment runs until any LineTerminator (LF, CR, LS, PS) or EOF.
            while (this.ch != '\n' and this.ch != '\r' and this.ch != 0 and
                !isLineSeparator(this))
            {
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
            if (this.ch == '\\') {
                this.readChar(); // consume backslash
                if (this.ch == 0) {
                    return .{ .type = .EOF, .literal = "" }; // unterminated escape at EOF
                }
                // Consume the escaped character (keeps \X in the literal;
                // the parser's processStringEscapes handles the conversion).
                this.readChar();
            } else {
                this.readChar();
            }
        }
        if (this.ch == 0) {
            return .{ .type = .EOF, .literal = "" }; // unterminated string
        }
        const literal = this.input[start..this.position];
        this.readChar(); // consume closing quote
        this.prev_token_type = .String;
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
        this.prev_token_type = .TemplateString;
        return .{ .type = .TemplateString, .literal = literal };
    }

    fn canEndExpression(tt: TokenType) bool {
        // Returns true if the given token type can end a JavaScript expression,
        // meaning '/' following it should be interpreted as division, not regex.
        return switch (tt) {
            .Identifier,
            .Integer,
            .Float,
            .BigInt,
            .String,
            .TemplateString,
            .Null,
            .Undefined,
            .True,
            .False,
            .RParen,
            .RBracket,
            .Increment,
            .Decrement,
            .Regex,
            => true,
            else => false,
        };
    }

    fn readRegexLiteral(this: *Lexer, line: u32) Token {
        const pattern_start = this.position + 1; // skip opening '/'
        this.readChar(); // consume opening '/'
        // Read pattern until the closing '/', respecting escaped slashes
        // and bracket depth ([/] inside character classes should not terminate).
        var bracket_depth: u32 = 0;
        while (true) {
            // Reject line terminators per ES spec (LineTerminator :: <LF> <CR> <LS> <PS>)
            if (this.ch == '\n' or this.ch == '\r' or isLineSeparator(this)) {
                return .{ .type = .EOF, .literal = "", .line = line };
            }
            if (this.ch == 0) break; // unterminated regex

            if (this.ch == '\\') {
                this.readChar(); // consume backslash
                if (this.ch == 0) break;
                this.readChar(); // consume escaped character (could be /, ], etc.)
            } else if (this.ch == '[') {
                bracket_depth += 1;
                this.readChar();
            } else if (this.ch == ']' and bracket_depth > 0) {
                bracket_depth -= 1;
                this.readChar();
            } else if (this.ch == '/' and bracket_depth == 0) {
                break; // closing slash (not inside a character class)
            } else {
                this.readChar();
            }
        }
        if (this.ch != '/') {
            return .{ .type = .EOF, .literal = "", .line = line }; // unterminated regex
        }
        const pattern = this.input[pattern_start..this.position];
        this.readChar(); // consume closing '/'
        // Read flags
        const flags_start = this.position;
        while (this.ch == 'g' or this.ch == 'i' or this.ch == 'm' or
            this.ch == 's' or this.ch == 'u' or this.ch == 'y' or
            this.ch == 'd' or this.ch == 'v')
        {
            this.readChar();
        }
        const flags = this.input[flags_start..this.position];
        this.prev_token_type = .Regex;
        return .{ .type = .Regex, .literal = pattern, .regex_flags = flags, .line = line };
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
        .{ "function", .Fn },
        .{ "return", .Return },
        .{ "if", .If },
        .{ "else", .Else },
        .{ "for", .For },
        .{ "while", .While },
        .{ "do", .Do },
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
        .{ "delete", .Delete },
        .{ "instanceof", .InstanceOf },
        .{ "typeof", .TypeOf },
        .{ "void", .Void },
        .{ "try", .Try },
        .{ "catch", .Catch },
        .{ "finally", .Finally },
        .{ "throw", .Throw },
        .{ "using", .Using },
        .{ "await", .Await },
        .{ "async", .Async },
        .{ "class", .Class },
        .{ "extends", .Extends },
        .{ "super", .Super },
        .{ "static", .Static },
        .{ "get", .Get },
        .{ "set", .Set },
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

test "dollar identifiers" {
    const input = "$ $x $$ $0 $_ $";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Identifier, .literal = "$" },
        .{ .type = .Identifier, .literal = "$x" },
        .{ .type = .Identifier, .literal = "$$" },
        .{ .type = .Identifier, .literal = "$0" },
        .{ .type = .Identifier, .literal = "$_" },
        .{ .type = .Identifier, .literal = "$" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "unicode identifiers: 2-byte UTF-8 (Latin accented)" {
    // café (é = U+00E9 = 0xC3 0xA9), naïve (ï = 0xC3 0xAF)
    const input = "café naïve résumé";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "café", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "naïve", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "résumé", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "unicode identifiers: 2-byte UTF-8 (Greek)" {
    // π (U+03C0 = 0xCF 0x80), Σ (U+03A3 = 0xCE 0xA3)
    const input = "π Σ λambda";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "π", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "Σ", tok.literal);

    // Mixed: λambda is a single identifier mixing Greek letter with ASCII.
    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "λambda", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "unicode identifiers: 3-byte UTF-8 (CJK)" {
    // 变 (U+53D8 = 0xE5 0xA4 0x89), 数 (U+6570 = 0xE6 0x95 0xB0)
    // 名前 (3+3 bytes), 変数 (3+3 bytes)
    const input = "変 数 名前 変数";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "変", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "数", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "名前", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "変数", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "unicode identifiers: 4-byte UTF-8 (emoji/extended)" {
    // Musical symbol G clef (U+1D11E) is surrogate-pair-encoded in UTF-16
    // but in UTF-8 it's 4 bytes: 0xF0 0x9D 0x84 0x9E.
    const input = "\u{1D11E} \u{1D11E}abc";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "\u{1D11E}", tok.literal);

    // Mixed: emoji + ASCII suffix.
    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "\u{1D11E}abc", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "unicode identifiers: digit-after is part of identifier" {
    // Test 1n parses as BigInt (digit+letter boundary), but π1 should be one identifier.
    const input = "π1 変数42";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "π1", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "変数42", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "unicode identifiers: delimiters and operators still work" {
    // Ensure multi-byte read doesn't break ASCII tokenization adjacent to unicode.
    const input = "café = \"coffee\";";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "café", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Assign, tok.type);
    try std.testing.expectEqualSlices(u8, "=", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.String, tok.type);
    try std.testing.expectEqualSlices(u8, "coffee", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Semicolon, tok.type);
    try std.testing.expectEqualSlices(u8, ";", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "unicode identifiers: utf-8 inside string literal" {
    // Strings are byte accumulators, so UTF-8 inside should still tokenize correctly.
    const input = "\"café\" 'naïve'";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.String, tok.type);
    try std.testing.expectEqualSlices(u8, "café", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.String, tok.type);
    try std.testing.expectEqualSlices(u8, "naïve", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "U+2028 line terminator increments line counter" {
    // U+2028 = 0xE2 0x80 0xA8 (3 bytes). Separates `a` (line 1) from `b` (line 2).
    var lexer = Lexer.init("a\u{2028}b");
    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "a", tok.literal);
    try std.testing.expectEqual(@as(u32, 1), tok.line);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "b", tok.literal);
    try std.testing.expectEqual(@as(u32, 2), tok.line);
}

test "U+2029 line terminator increments line counter" {
    // U+2029 = 0xE2 0x80 0xA9 (3 bytes).
    var lexer = Lexer.init("a\u{2029}b");
    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "a", tok.literal);
    try std.testing.expectEqual(@as(u32, 1), tok.line);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "b", tok.literal);
    try std.testing.expectEqual(@as(u32, 2), tok.line);
}

test "single-line comment terminates at U+2028" {
    // `// ... <LS> + 1` — the comment runs until U+2028; then `+ 1` is parsed.
    const input = "42 // caf\u{00E9}\u{2028}+ 1";
    var lexer = Lexer.init(input);

    const tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Integer, tok.type);
    try std.testing.expectEqualSlices(u8, "42", tok.literal);

    const tok2 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Plus, tok2.type);

    const tok3 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Integer, tok3.type);
    try std.testing.expectEqualSlices(u8, "1", tok3.literal);

    const tok4 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok4.type);
}

test "single-line comment terminates at U+2029" {
    const input = "42 // caf\u{00E9}\u{2029}+ 1";
    var lexer = Lexer.init(input);

    const tok1 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Integer, tok1.type);

    var sum: i64 = 0;
    while (true) {
        const t = lexer.nextToken();
        if (t.type == TokenType.EOF) break;
        if (t.type == TokenType.Plus) continue;
        if (t.type == TokenType.Integer) sum += std.fmt.parseInt(i64, t.literal, 10) catch 0;
    }
    try std.testing.expectEqual(@as(i64, 1), sum);
}

test "regex literal rejects U+2028 in pattern" {
    var lexer = Lexer.init("/hello\u{2028}world/");
    const tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "regex literal rejects U+2029 in pattern" {
    var lexer = Lexer.init("/hello\u{2029}world/");
    const tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "skipWhitespace consumes U+2028 and U+2029 between tokens" {
    // Two statements separated by U+2028 then U+2029 should tokenize as 4 separate tokens.
    const input = "a;\u{2028}b;\u{2029}c;d";
    var lexer = Lexer.init(input);

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "a", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Semicolon, tok.type);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "b", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Semicolon, tok.type);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "c", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Semicolon, tok.type);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "d", tok.literal);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.EOF, tok.type);
}

test "U+2028 followed by LF still increments line once each" {
    // 'a' on line 1, 'b' on line 2 (after LF), 'c' on line 3 (after LS).
    // Read each token's line via `tok.line` (captured before any readChar in
    // the identifier loop that moves ch onto the line terminator).
    var lexer = Lexer.init("a\nb\u{2028}c");

    var t = lexer.nextToken();
    try std.testing.expectEqual(@as(u32, 1), t.line);
    try std.testing.expectEqualSlices(u8, "a", t.literal);

    t = lexer.nextToken();
    try std.testing.expectEqual(@as(u32, 2), t.line);
    try std.testing.expectEqualSlices(u8, "b", t.literal);

    t = lexer.nextToken();
    try std.testing.expectEqual(@as(u32, 3), t.line);
    try std.testing.expectEqualSlices(u8, "c", t.literal);
}

test "U+2028 not confused with 0xE2 lead byte of unrelated codepoints" {
    // U+00E2 (â) is a Latin letter (2-byte UTF-8: 0xC3 0xA2), NOT the 3-byte
    // sequence 0xE2 lead that signals LS/PS. After LS splits the identifier,
    // the next identifier simply continues to consume any >=0x80 bytes that
    // ARE legitimate ID_Continue characters (here, U+00E2 and ASCII 'c').
    var lexer = Lexer.init("a\u{2028}b\u{00E2}c");

    var tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    try std.testing.expectEqualSlices(u8, "a", tok.literal);
    try std.testing.expectEqual(@as(u32, 1), tok.line);

    tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok.type);
    // 'b' + U+00E2 (â) + 'c' is one identifier; LS already terminated the prev.
    try std.testing.expectEqualSlices(u8, "b\u{00E2}c", tok.literal);
    try std.testing.expectEqual(@as(u32, 2), tok.line);
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
        .{ .type = .Identifier, .literal = "fn" },
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
    // NOTE: '/' is context-dependent (division vs regex). Test division
    // via `x / y` where Identifier ends an expression so '/' is division.
    const input = "+ - * % & | ^ ~ x / y";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Plus, .literal = "+" },
        .{ .type = .Minus, .literal = "-" },
        .{ .type = .Multiply, .literal = "*" },
        .{ .type = .Modulo, .literal = "%" },
        .{ .type = .BitAnd, .literal = "&" },
        .{ .type = .BitOr, .literal = "|" },
        .{ .type = .BitXor, .literal = "^" },
        .{ .type = .BitNot, .literal = "~" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .Divide, .literal = "/" },
        .{ .type = .Identifier, .literal = "y" },
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

test "exponent operator (**)" {
    // Longest-match-first: `**=` before `**` before `*=` before `*`.
    const input = "2 ** 3 x **= 5 a*b";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "2" },
        .{ .type = .Exponent, .literal = "**" },
        .{ .type = .Integer, .literal = "3" },
        .{ .type = .Identifier, .literal = "x" },
        .{ .type = .PowerAssign, .literal = "**=" },
        .{ .type = .Integer, .literal = "5" },
        .{ .type = .Identifier, .literal = "a" },
        .{ .type = .Multiply, .literal = "*" },
        .{ .type = .Identifier, .literal = "b" },
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
    const input = "function add(a, b) { return a + b; }";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Fn, .literal = "function" },
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

test "unsigned right shift and compound assign" {
    const input = ">>> >>= <<= >>>= >> <<";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .UnsignedRightShift, .literal = ">>>" },
        .{ .type = .RightShiftAssign, .literal = ">>=" },
        .{ .type = .LeftShiftAssign, .literal = "<<=" },
        .{ .type = .UnsignedRightShiftAssign, .literal = ">>>=" },
        .{ .type = .RightShift, .literal = ">>" },
        .{ .type = .LeftShift, .literal = "<<" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "hex octal binary literals" {
    const input = "0xFF 0X1A 0o77 0O52 0b1010 0B1100 0 42 0xFFFFFFFF";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "0xFF" },
        .{ .type = .Integer, .literal = "0X1A" },
        .{ .type = .Integer, .literal = "0o77" },
        .{ .type = .Integer, .literal = "0O52" },
        .{ .type = .Integer, .literal = "0b1010" },
        .{ .type = .Integer, .literal = "0B1100" },
        .{ .type = .Integer, .literal = "0" },
        .{ .type = .Integer, .literal = "42" },
        .{ .type = .Integer, .literal = "0xFFFFFFFF" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "leading-dot float" {
    const input = ".5 .125 .001 .5e2 .125e-1 .5E+3 .0";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Float, .literal = ".5" },
        .{ .type = .Float, .literal = ".125" },
        .{ .type = .Float, .literal = ".001" },
        .{ .type = .Float, .literal = ".5e2" },
        .{ .type = .Float, .literal = ".125e-1" },
        .{ .type = .Float, .literal = ".5E+3" },
        .{ .type = .Float, .literal = ".0" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "exponential notation" {
    const input = "1e10 3.14e-2 2.5E+3 1E-5 6.022e23 99E0";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Float, .literal = "1e10" },
        .{ .type = .Float, .literal = "3.14e-2" },
        .{ .type = .Float, .literal = "2.5E+3" },
        .{ .type = .Float, .literal = "1E-5" },
        .{ .type = .Float, .literal = "6.022e23" },
        .{ .type = .Float, .literal = "99E0" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "string escape sequences" {
    const input = "\"hello\\nworld\" \"tab\\there\" \"quote\\\"inside\\\"\" \"back\\\\slash\" \"\\x41\\x42\" \"\\u0041\\u0042\"";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .String, .literal = "hello\\nworld" },
        .{ .type = .String, .literal = "tab\\there" },
        .{ .type = .String, .literal = "quote\\\"inside\\\"" },
        .{ .type = .String, .literal = "back\\\\slash" },
        .{ .type = .String, .literal = "\\x41\\x42" },
        .{ .type = .String, .literal = "\\u0041\\u0042" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "regex literals" {
    // Regex at start of expression (prev_token_type defaults to .EOF, not in canEndExpression)
    {
        const input = "/hello/gi";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Regex, tok.type);
        try std.testing.expectEqualSlices(u8, "hello", tok.literal);
        try std.testing.expectEqualSlices(u8, "gi", tok.regex_flags);
    }
    // Division after identifier (Identifier is in canEndExpression)
    {
        const input = "x / y";
        var lexer = Lexer.init(input);
        const tok1 = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Identifier, tok1.type);
        const tok2 = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Divide, tok2.type);
        const tok3 = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Identifier, tok3.type);
    }
    // Bracket depth: [/] inside character class should not terminate regex
    {
        const input = "/[a/b]c/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Regex, tok.type);
        try std.testing.expectEqualSlices(u8, "[a/b]c", tok.literal);
    }
    // Bracket depth: literal [/] in character class
    {
        const input = "/[/]/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Regex, tok.type);
        try std.testing.expectEqualSlices(u8, "[/]", tok.literal);
    }
    // Bracket depth: escaped ] inside character class (\] does not close bracket)
    {
        const input = "/[a\\]b]c/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Regex, tok.type);
        try std.testing.expectEqualSlices(u8, "[a\\]b]c", tok.literal);
    }
    // Bracket depth: nested-like but flat: [[abc]]
    {
        const input = "/[[abc]]/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Regex, tok.type);
        try std.testing.expectEqualSlices(u8, "[[abc]]", tok.literal);
    }
    // Line terminator: \n in pattern returns EOF (unterminated)
    {
        const input = "/hello\nworld/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.EOF, tok.type);
    }
    // Line terminator: \r in pattern returns EOF
    {
        const input = "/hello\rworld/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.EOF, tok.type);
    }
    // Unicode escape for line terminator chars: \u000A, \u000D, \u2028, \u2029 are allowed
    // (they are NOT raw line terminators, they are escape sequences)
    {
        const input = "/\\n\\r/";
        var lexer = Lexer.init(input);
        const tok = lexer.nextToken();
        try std.testing.expectEqual(TokenType.Regex, tok.type);
        try std.testing.expectEqualSlices(u8, "\\n\\r", tok.literal);
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

test "numeric separators: decimal integer" {
    const input = "1_000_000 1_0 1_000";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "1_000_000" },
        .{ .type = .Integer, .literal = "1_0" },
        .{ .type = .Integer, .literal = "1_000" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "numeric separators: hex" {
    const input = "0xFF_FF 0x1_2_A_B 0X0_0";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "0xFF_FF" },
        .{ .type = .Integer, .literal = "0x1_2_A_B" },
        .{ .type = .Integer, .literal = "0X0_0" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "numeric separators: binary" {
    const input = "0b1010_0101 0b1_0 0B0_1";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "0b1010_0101" },
        .{ .type = .Integer, .literal = "0b1_0" },
        .{ .type = .Integer, .literal = "0B0_1" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "numeric separators: octal" {
    const input = "0o7_777 0o1_2_3 0O5_0";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Integer, .literal = "0o7_777" },
        .{ .type = .Integer, .literal = "0o1_2_3" },
        .{ .type = .Integer, .literal = "0O5_0" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "numeric separators: floats" {
    const input = "1_000.5_0 3.14_15 1_0.0_1";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Float, .literal = "1_000.5_0" },
        .{ .type = .Float, .literal = "3.14_15" },
        .{ .type = .Float, .literal = "1_0.0_1" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "numeric separators: exponential" {
    const input = "1_000e1_0 6.0_2e2_3 1e1_0";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Float, .literal = "1_000e1_0" },
        .{ .type = .Float, .literal = "6.0_2e2_3" },
        .{ .type = .Float, .literal = "1e1_0" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}

test "class keywords and private hash token" {
    const input = "class extends super static get set #name";
    var lexer = Lexer.init(input);
    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Class, .literal = "class" },
        .{ .type = .Extends, .literal = "extends" },
        .{ .type = .Super, .literal = "super" },
        .{ .type = .Static, .literal = "static" },
        .{ .type = .Get, .literal = "get" },
        .{ .type = .Set, .literal = "set" },
        .{ .type = .Hash, .literal = "#" },
        .{ .type = .Identifier, .literal = "name" },
        .{ .type = .EOF, .literal = "" },
    };
    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}
test "numeric separators: leading-dot float" {
    const input = ".5_0 .1_2_5 .0_0_1";
    var lexer = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .Float, .literal = ".5_0" },
        .{ .type = .Float, .literal = ".1_2_5" },
        .{ .type = .Float, .literal = ".0_0_1" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualSlices(u8, exp.literal, tok.literal);
    }
}
