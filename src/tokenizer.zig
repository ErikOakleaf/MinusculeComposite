const std = @import("std");

const Token = union(enum) {
    String: []const u8,
    Identifier: []const u8,
    LParen,
    RParen,
    Equals,
    Dot,
    For,
    EOF,
};

const LexError = error{
    IdentifierStartsWithNumber,
    UnterminatedString,
};

const Lexer = struct {
    input: []const u8,
    pos: u32, // current position in input (points to current char)
    read_pos: u32, // current reading position in input (after current char)
    ch: u8, // current char under examination
    line: u32,
    col: u32,

    fn init(input: []const u8, start_line: u32, start_col: u32) Lexer {
        var lexer = Lexer{
            .input = input,
            .pos = 0,
            .read_pos = 0,
            .ch = undefined,
            .line = start_line,
            .col = start_col,
        };
        lexer.read_ch();
        return lexer;
    }

    fn next_token(self: *Lexer) !Token {
        self.skip_whitespace();

        const token = switch (self.ch) {
            '(' => Token.LParen,
            ')' => Token.RParen,
            '=' => Token.Equals,
            '.' => Token.Dot,
            0 => Token.EOF,
            '"' => Token{ .String = try self.read_str() },
            else => match_identifier(try self.read_identifier()),
        };

        self.read_ch();
        return token;
    }

    fn read_ch(self: *Lexer) void {
        if (self.read_pos >= self.input.len) {
            self.ch = 0;
        } else {
            self.ch = self.input[self.read_pos];
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
            return error.IdentifierStartsWithNumber;
        }

        const start_pos = self.pos;

        while (is_letter(self.ch)) {
            self.read_ch();
        }

        return self.input[start_pos..self.pos];
    }

    fn match_identifier(input: []const u8) Token {
        // right now this just has a simple if statement
        // if it grows to have a lot of keyword look into a
        // string map
        if (std.mem.eql(u8, input, "for")) return Token.For;

        return Token{ .Identifier = input };
    }

    fn read_str(self: *Lexer) ![]const u8 {
        self.read_ch(); // skip the first ' " ' so it does not get caught in the loop

        const start_pos = self.pos;

        while (self.ch != '"' and self.ch != 0) {
            self.read_ch();
        }

        if (self.ch == 0) {
            return error.UnterminatedString;
        }

        const result = self.input[start_pos..self.pos];
        return result;
    }
};

// helpers
fn is_letter(ch: u8) bool {
    return switch (ch) {
        '0'...'9', 'A'...'Z', 'a'...'z', '_' => true,
        else => false,
    };
}

test "next_token returns identifier for letter and digit sequences" {
    const input = "tester123";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    switch (token) {
        .Identifier => |val| try std.testing.expectEqualStrings("tester123", val),
        else => return error.TestUnexpectedResult,
    }
}

test "next_token returns For token for \"for\"" {
    const input = "for";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    try std.testing.expect(token == Token.For);
}

test "next_token returns Dot token for '.'" {
    const input = ".";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    try std.testing.expect(token == Token.Dot);
}

test "next_token returns string for sequence within \" \"" {
    const input = "\"hello world\"";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    switch (token) {
        .String => |val| try std.testing.expectEqualStrings("hello world", val),
        else => return error.TestUnexpectedResult,
    }
}

test "next_token returns Equals for '='" {
    const input = "=";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    try std.testing.expect(token == Token.Equals);
}

test "next_token returns LParen for '('" {
    const input = "(";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    try std.testing.expect(token == Token.LParen);
}

test "next_token returns RParen for ')'" {
    const input = ")";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    try std.testing.expect(token == Token.RParen);
}

test "next_token returns EOF at the end of the input" {
    const input = ")";
    var lexer = Lexer.init(input, 0, 0);
    var token = try lexer.next_token();
    token = try lexer.next_token();
    try std.testing.expect(token == Token.EOF);
}

test "next_token deletes whitspace" {
    const input = "\n \r \t =";
    var lexer = Lexer.init(input, 0, 0);
    const token = try lexer.next_token();
    try std.testing.expect(token == Token.Equals);
}

test "next_token errors on identifier with leading number as input" {
    const input = "123something";
    var lexer = Lexer.init(input, 0, 0);
    const err = lexer.next_token();
    try std.testing.expectError(error.IdentifierStartsWithNumber, err);
}

test "next_token errors on unterminated string" {
    const input = "\"123something";
    var lexer = Lexer.init(input, 0, 0);
    const err = lexer.next_token();
    try std.testing.expectError(error.UnterminatedString, err);
}
