const std = @import("std");
const Tokenizer = @import("tokenizer.zig");
const Loc = @import("common.zig").Loc;
const Lexer = Tokenizer.Lexer;
const Token = Tokenizer.Token;

// ---------------- Ast ----------------

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
    Direct: Token,
    Path: VarPath,
};

// ---------------- Parser ----------------

pub const ParserError = error{
    UnexpectedToken,
};

const Parser = struct {
    allocator: std.mem.Allocator,
    l: *Lexer,
    cur_token: Token,
    peek_token: Token,
    error_loc: ?Loc,

    pub fn init(l: *Lexer, allocator: std.mem.Allocator) !Parser {
        var parser = Parser{ .l = l, .allocator = allocator, .cur_token = undefined, .peek_token = undefined, .error_loc = null };

        try parser.next_token();
        try parser.next_token();

        return parser;
    }

    fn next_token(self: *Parser) !void {
        self.cur_token = self.peek_token;
        self.peek_token = try self.l.next_token();
    }

    fn cur_token_is(self: *Parser, tag: Token.Tag) bool {
        return self.cur_token.tag == tag;
    }

    fn peek_token_is(self: *Parser, tag: Token.Tag) bool {
        return self.peek_token.tag == tag;
    }

    fn expect_peek(self: *Parser, tag: Token.Tag) !void {
        if (self.peek_token_is(tag)) {
            try self.next_token();
        } else {
            self.error_loc = self.cur_token.loc;
            return error.UnexpectedToken;
        }
    }

    pub fn parse_file(self: *Parser) ![]const Node {
        var ast: std.ArrayList(Node) = .empty;
        while (self.cur_token.tag != Token.Tag.EOF) {
            const node = try self.parse_node();
            try ast.append(self.allocator, node);

            try self.next_token();
        }
        return ast.items;
    }

    fn parse_node(self: *Parser) !Node {
        return switch (self.cur_token.tag) {
            .RawText => Node{ .RawText = .{ .token = self.cur_token } },
            .Identifier => self.parse_interpolation(),
            else => @panic("TODO: implement other node types"),
        };
    }

    fn parse_interpolation(self: *Parser) !Node {
        if (!self.peek_token_is(.Dot)) {
            return Node{ .Interpolation = .{ .value = .{ .Direct = self.cur_token } } };
        }
        const namespace = self.cur_token;

        try self.next_token(); // consume Dot token

        try self.expect_peek(Token.Tag.Identifier);

        const field = self.cur_token;

        return Node{ .Interpolation = .{ .value = .{ .Path = .{ .namespace = namespace, .field = field } } } };
    }
};

fn expectEqualNodes(expected: []const Node, actual: []const Node) !void {
    try std.testing.expectEqual(expected.len, actual.len);

    for (expected, actual) |e, a| {
        try std.testing.expectEqual(
            std.meta.activeTag(e),
            std.meta.activeTag(a),
        );

        switch (e) {
            .RawText => |e_raw| {
                const a_raw = a.RawText;
                try expectEqualToken(e_raw.token, a_raw.token);
            },
            .Interpolation => |e_interp| {
                const e_interp_value = e_interp.value;
                const a_interp_value = a.Interpolation.value;

                switch (e_interp_value) {
                    .Direct => |e_direct_token| {
                        const a_direct_token = a_interp_value.Direct;
                        try expectEqualToken(e_direct_token, a_direct_token);
                    },
                    .Path => |e_path| {
                        const e_namespace_token = e_path.namespace;
                        const e_field_token = e_path.field;

                        const a_path = a_interp_value.Path;
                        const a_namespace_token = a_path.namespace;
                        const a_field_token = a_path.field;

                        try expectEqualToken(e_namespace_token, a_namespace_token);
                        try expectEqualToken(e_field_token, a_field_token);
                    },
                }
            },
            else => @panic("TODO: implement other node types"),
        }
    }
}

inline fn expectEqualToken(e: Token, a: Token) !void {
    try std.testing.expectEqual(e.tag, a.tag);
    try std.testing.expectEqual(e.loc, a.loc);
    try std.testing.expectEqualStrings(e.data, a.data);
}

test "parser returns correct nodes for interpolation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{{ variable }}{{ namespace.field }}"
    ;
    var lexer = Lexer.init(input);
    var parser = try Parser.init(&lexer, allocator);

    const ast = try parser.parse_file();

    const expected: []const Node = &[_]Node{
        // {{ variable }} -> Direct
        .{
            .Interpolation = .{
                .value = .{
                    .Direct = .{
                        .tag = .Identifier,
                        .loc = .{ .line = 0, .col = 3 },
                        .data = "variable",
                    },
                },
            },
        },
        // {{ namespace.field }} -> Path
        .{
            .Interpolation = .{
                .value = .{
                    .Path = .{
                        .namespace = .{
                            .tag = .Identifier,
                            .loc = .{ .line = 1, .col = 3 },
                            .data = "namespace",
                        },
                        .field = .{
                            .tag = .Identifier,
                            .loc = .{ .line = 1, .col = 13 },
                            .data = "field",
                        },
                    },
                },
            },
        },
    };

    try expectEqualNodes(expected, ast);
}
