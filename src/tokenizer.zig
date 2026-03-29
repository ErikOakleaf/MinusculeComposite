const std = @import("std");

const Token = union(enum) {
    Stirng: []const u8,
    Identifier: []const u8,
    LParen,
    RParen,
    Equals,
};

const Lexer = struct {
    input: []const u8,
    pos: u32, // current position in input (points to current char)
    read_pos: u32, // current reading position in input (after current char)
    ch: u8, // current char under examination

    fn init(input: []const u8) Lexer {
        var lexer = Lexer{ .input = input };
        lexer.read_ch();
        return lexer;
    }

    fn next_token(self: *Lexer) Token {
        const token = switch (self.ch) {
            '(' => Token.LParen,
            ')' => Token.RParen,
            '=' => Token.Equals,
            '"' => {
                const str = self.read_str();
                return Token.String(str);
            },
            else => {
                const identifier = read_identifier(self);
                return Token.Identifier(identifier);
            }
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
        while (self.ch == ' ') {
            self.read_ch();
        }
    }

    fn read_identifier(self: *Lexer) []const u8 {
        const start_pos = self.pos;

        while (is_letter(self.ch)) {
            self.read_ch();
        }

        return self.input[start_pos..self.pos];
    }

    fn read_str(self: *Lexer) []const u8 {
        self.read_ch(); // skip the first ' " ' so it does not get caught in the loop

        const start_pos = self.pos;

        while (self.ch != '"' and self.ch != 0) {
            self.read_ch();
        }

        if (self.ch == 0) {
            @panic("unterminated string literal");
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
