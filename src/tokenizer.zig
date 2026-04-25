const std = @import("std");
const Loc = @import("common.zig").Loc;

pub const Token = struct {
    tag: Tag,
    loc: Loc,
    data: []const u8,

    pub const Tag = enum {
        RawText,
        String,
        Identifier,
        LParen,
        RParen,
        ClosingDelim,
        Equals,
        Dot,
        For,
        In,
        End,
        EOF,
    };
};

pub const LexError = error{
    IdentifierStartsWithNumber,
    UnterminatedString,
    MissingCurlyBrace,
};

const ParseMode = enum {
    RawText,
    Template,
};

pub const Lexer = struct {
    input: []const u8,
    pos: u32, // current position in input (points to current char)
    read_pos: u32, // current reading position in input (after current char)
    ch: u8, // current char under examination
    line: u32,
    col: u32,
    error_loc: ?Loc,
    parse_mode: ParseMode,

    pub fn init(input: []const u8) Lexer {
        var lexer = Lexer{
            .input = input,
            .pos = 0,
            .read_pos = 0,
            .ch = undefined,
            .line = 1,
            .col = 0,
            .error_loc = null,
            .parse_mode = ParseMode.RawText,
        };
        lexer.read_ch();
        return lexer;
    }

    fn peek(self: *Lexer) u8 {
        if (self.read_pos >= self.input.len) return 0;
        return self.input[self.read_pos];
    }

    pub fn next_token(self: *Lexer) !Token {
        return switch (self.parse_mode) {
            ParseMode.RawText => self.next_raw_text_token(),
            ParseMode.Template => next_template_token(self),
        };
    }

    fn next_raw_text_token(self: *Lexer) !Token {
        const start_loc = Loc{ .line = self.line, .col = self.col };

        if (self.ch == 0) {
            return Token{ .tag = .EOF, .loc = start_loc, .data = "" };
        }

        const raw_text = self.read_raw_text();

        if (is_all_whitespace(raw_text)) {
            return self.next_template_token();
        }

        return Token{ .tag = .RawText, .loc = start_loc, .data = raw_text };
    }

    fn next_template_token(self: *Lexer) !Token {
        self.skip_whitespace();

        const start_loc = Loc{ .line = self.line, .col = self.col };
        const start_pos = self.pos;

        var tag: Token.Tag = undefined;
        var slice: []const u8 = undefined;

        switch (self.ch) {
            '}' => {
                self.read_ch();
                if (self.ch != '}') {
                    self.error_loc = Loc{ .col = self.col, .line = self.line };
                    return error.MissingCurlyBrace;
                }
                self.read_ch();
                self.parse_mode = ParseMode.RawText;
                tag = .ClosingDelim;
                slice = self.input[start_pos..self.pos];
            },
            '(' => {
                self.read_ch();
                tag = .LParen;
                slice = self.input[start_pos..self.pos];
            },
            ')' => {
                self.read_ch();
                tag = .RParen;
                slice = self.input[start_pos..self.pos];
            },
            '=' => {
                self.read_ch();
                tag = .Equals;
                slice = self.input[start_pos..self.pos];
            },
            '.' => {
                self.read_ch();
                tag = .Dot;
                slice = self.input[start_pos..self.pos];
            },
            0 => {
                self.read_ch();
                tag = .EOF;
                slice = "";
            },
            '"' => {
                tag = .String;
                slice = try self.read_str();
                self.read_ch();
            },
            else => {
                slice = try self.read_identifier();
                tag = match_identifier(slice);
            },
        }

        const token = Token{ .tag = tag, .loc = start_loc, .data = slice };
        return token;
    }

    fn read_ch(self: *Lexer) void {
        if (self.read_pos >= self.input.len) {
            self.ch = 0;
        } else {
            self.ch = self.input[self.read_pos];
        }

        if (self.ch == '\n') {
            self.line += 1;
            self.col = 0;
        } else {
            self.col += 1;
        }

        self.pos = self.read_pos;
        self.read_pos += 1;
    }

    fn skip_whitespace(self: *Lexer) void {
        while (self.ch == ' ' or self.ch == '\n' or self.ch == '\t' or self.ch == '\r') {
            self.read_ch();
        }
    }

    fn read_identifier(self: *Lexer) ![]const u8 {
        if (self.ch >= '0' and self.ch <= '9') {
            self.error_loc = Loc{ .col = self.col, .line = self.line };
            return error.IdentifierStartsWithNumber;
        }

        const start_pos = self.pos;

        while (is_letter(self.ch)) {
            self.read_ch();
        }

        return self.input[start_pos..self.pos];
    }

    fn match_identifier(input: []const u8) Token.Tag {
        // right now this just has a simple if statement
        // if it grows to have a lot of keyword look into a
        // string map
        if (std.mem.eql(u8, input, "for")) return Token.Tag.For;
        if (std.mem.eql(u8, input, "in")) return Token.Tag.In;
        if (std.mem.eql(u8, input, "end")) return Token.Tag.End;

        return Token.Tag.Identifier;
    }

    fn read_str(self: *Lexer) ![]const u8 {
        self.read_ch(); // skip the first ' " ' so it does not get caught in the loop

        const start_pos = self.pos;

        while (self.ch != '"' and self.ch != 0) {
            self.read_ch();
        }

        if (self.ch == 0) {
            self.error_loc = Loc{ .col = self.col, .line = self.line };
            return error.UnterminatedString;
        }

        const result = self.input[start_pos..self.pos];
        return result;
    }

    fn read_raw_text(self: *Lexer) []const u8 {
        const start_pos = self.pos;

        while (self.ch != 0 and !(self.ch == '{' and self.peek() == '{')) {
            self.read_ch();
        }

        const end_pos = self.pos;

        if (self.ch == '{') {
            self.read_ch();
            self.read_ch();
            self.parse_mode = ParseMode.Template;
        }

        return self.input[start_pos..end_pos];
    }
};

// helpers

fn is_letter(ch: u8) bool {
    return switch (ch) {
        '0'...'9', 'A'...'Z', 'a'...'z', '_' => true,
        else => false,
    };
}

fn is_all_whitespace(s: []const u8) bool {
    for (s) |c| {
        if (!(c == ' ' or c == '\n' or c == '\t' or c == '\r')) {
            return false;
        }
    }
    return true;
}

// tests

test "next_token returns identifier for letter and digit sequences" {
    const input = "tester123";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, token.tag);
    try std.testing.expectEqualStrings("tester123", token.data);
}

test "next_token returns For token for \"for\"" {
    const input = "for";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.For, token.tag);
    try std.testing.expectEqualStrings("for", token.data);
}

test "next_token returns In token for \"in\"" {
    const input = "in";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.In, token.tag);
    try std.testing.expectEqualStrings("in", token.data);
}

test "next_token returns End token for \"end\"" {
    const input = "end";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.End, token.tag);
    try std.testing.expectEqualStrings("end", token.data);
}

test "next_token returns Dot token for '.'" {
    const input = ".";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Dot, token.tag);
    try std.testing.expectEqualStrings(".", token.data);
}

test "next_token returns string for sequence within \" \"" {
    const input = "\"hello world\"";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.String, token.tag);
    try std.testing.expectEqualStrings("hello world", token.data);
}

test "next_token returns Equals for '='" {
    const input = "=";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.Equals, token.tag);
    try std.testing.expectEqualStrings("=", token.data);
}

test "next_token returns LParen for '('" {
    const input = "(";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.LParen, token.tag);
    try std.testing.expectEqualStrings("(", token.data);
}

test "next_token returns RParen for ')'" {
    const input = ")";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.RParen, token.tag);
    try std.testing.expectEqualStrings(")", token.data);
}

test "next_token returns EOF at the end of the input" {
    const input = ")";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    var token = try lexer.next_token();
    token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.EOF, token.tag);
    try std.testing.expectEqualStrings("", token.data);
}

test "next_token deletes whitspace" {
    const input = "\n \r \t =";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.Equals, token.tag);
    try std.testing.expectEqualStrings("=", token.data);
}

test "next_token errors on identifier with leading number as input" {
    const input = "123something";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const err = lexer.next_token();

    try std.testing.expectError(error.IdentifierStartsWithNumber, err);
}

test "next_token returns for loop tokens in for loop" {
    const input = "for i in y";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;

    const for_token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.For, for_token.tag);
    try std.testing.expectEqualStrings("for", for_token.data);

    const i_token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, i_token.tag);
    try std.testing.expectEqualStrings("i", i_token.data);

    const in_token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.In, in_token.tag);
    try std.testing.expectEqualStrings("in", in_token.data);

    const y_token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, y_token.tag);
    try std.testing.expectEqualStrings("y", y_token.data);
}

test "next_token errors on unterminated string" {
    const input = "\"123something";
    var lexer = Lexer.init(input);
    lexer.parse_mode = ParseMode.Template;
    const err = lexer.next_token();
    try std.testing.expectError(error.UnterminatedString, err);
}

test "next_token returns raw_text token for raw text" {
    const input = "hello world";
    var lexer = Lexer.init(input);
    const token = try lexer.next_token();

    try std.testing.expectEqual(Token.Tag.RawText, token.tag);
    try std.testing.expectEqualStrings("hello world", token.data);
}

test "next_token handles mixed raw text and template tags" {
    const input = "Hi {{ name }}!";
    var lexer = Lexer.init(input);

    var token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.RawText, token.tag);
    try std.testing.expectEqualStrings("Hi ", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, token.tag);
    try std.testing.expectEqualStrings("name", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.ClosingDelim, token.tag);
    try std.testing.expectEqualStrings("}}", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.RawText, token.tag);
    try std.testing.expectEqualStrings("!", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.EOF, token.tag);
    try std.testing.expectEqualStrings("", token.data);
}

test "next_token handles two {{}} blocks with whitespace between without giving a RawText token" {
    const input = "{{ block1 }}{{ block2 }}      \n     \t \r       {{ block3 }}\nsome raw text {{ block4 }}";
    var lexer = Lexer.init(input);

    var token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, token.tag);
    try std.testing.expectEqualStrings("block1", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.ClosingDelim, token.tag);
    try std.testing.expectEqualStrings("}}", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, token.tag);
    try std.testing.expectEqualStrings("block2", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.ClosingDelim, token.tag);
    try std.testing.expectEqualStrings("}}", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, token.tag);
    try std.testing.expectEqualStrings("block3", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.ClosingDelim, token.tag);
    try std.testing.expectEqualStrings("}}", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.RawText, token.tag);
    try std.testing.expectEqualStrings("\nsome raw text ", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.Identifier, token.tag);
    try std.testing.expectEqualStrings("block4", token.data);

    token = try lexer.next_token();
    try std.testing.expectEqual(Token.Tag.ClosingDelim, token.tag);
    try std.testing.expectEqualStrings("}}", token.data);
}
