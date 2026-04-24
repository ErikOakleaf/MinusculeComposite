const std = @import("std");
const Tokenizer = @import("tokenizer.zig");
const Lexer = Tokenizer.Lexer;
const Token = Tokenizer.Token;

const Node = union(enum) {
    RawText: RawText,
    ForLoop: ForLoop,
    Interpolation: Interpolation,
    ComponentCall: ComponentCall,
};

const RawText = struct {
    token: Token,
};

const ForLoop = struct {
    iterator: Token,
    iterable: Token,
    body: []const Node,
};

const Interpolation = struct {
    value: InterpolationValue,
};

const ComponentCall = struct {
    name: Token,
    args: []const Argument,
};

const Argument = struct {
    key: Token,
    value: ArgumentValue,
};

const ArgumentValue = union(enum) {
    String: Token,
    Variable: VarPath,
};

const VarPath = struct {
    namespace: Token,
    field: Token,
};

const InterpolationValue = union(enum) {
    Bare: Token,
    Path: VarPath,
};

const Parser = struct {
    l: *Lexer,
    cur_token: Token,
    peek_token: Token,

    pub fn init(l: *Lexer) !Parser {
        const parser = Parser{ .l = l };

        parser.cur_token = undefined;
        parser.peek_token = undefined;

        parser.next_token();
        parser.next_token();

        return parser;
    }

    fn next_token(self: *Parser) !void {
        self.cur_token = self.peek_token;
        self.peek_token = try self.l.next_token();
    }

    pub fn parse_file(self: *Parser) ![]const Node {
        return null;
    }
};


test "parser returns correct nodes for interpolation" {
    const input = "hello world";
    var lexer = Lexer.init(input);
    var parser = Parser.init(&lexer);

    const ast = parser.parse_file();

    const expected: []const Node = &[_]{. }
}
