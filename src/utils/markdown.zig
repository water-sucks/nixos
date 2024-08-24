const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const ansi = @import("./ansi.zig");

const log = @import("../log.zig");

const koino = @import("koino");
const MDParser = koino.parser.Parser;
const Options = koino.Options;
const AstNode = koino.nodes.AstNode;

pub fn renderMarkdownANSI(allocator: Allocator, slice: []const u8) ![]const u8 {
    var p = try MDParser.init(allocator, .{});
    try p.feed(slice);

    var doc = try p.finish();
    p.deinit();

    defer doc.deinit();

    var result = ArrayList(u8).init(allocator);
    const writer = result.writer();

    var formatter = makeANSIFormatter(writer, allocator, p.options);

    try formatter.format(doc, false);

    return result.toOwnedSlice();
}

pub fn makeANSIFormatter(writer: anytype, allocator: std.mem.Allocator, options: Options) ANSIFormatter(@TypeOf(writer)) {
    return ANSIFormatter(@TypeOf(writer)).init(writer, allocator, options);
}

pub fn ANSIFormatter(comptime Writer: type) type {
    return struct {
        writer: Writer,
        allocator: std.mem.Allocator,
        options: Options,
        last_was_lf: bool = true,

        const Self = @This();

        pub fn init(writer: Writer, allocator: std.mem.Allocator, options: Options) Self {
            return .{
                .writer = writer,
                .allocator = allocator,
                .options = options,
            };
        }

        fn cr(self: *Self) !void {
            if (!self.last_was_lf) {
                try self.writeAll("\n");
            }
        }

        pub fn writeAll(self: *Self, s: []const u8) !void {
            if (s.len == 0) {
                return;
            }
            try self.writer.writeAll(s);
            self.last_was_lf = s[s.len - 1] == '\n';
        }

        pub fn format(self: *Self, input_node: *AstNode, plain: bool) !void {
            const Phase = enum { Pre, Post };
            const StackEntry = struct {
                node: *AstNode,
                plain: bool,
                phase: Phase,
            };

            var stack = ArrayList(StackEntry).init(self.allocator);
            defer stack.deinit();

            try stack.append(.{ .node = input_node, .plain = plain, .phase = .Pre });

            while (stack.popOrNull()) |entry| {
                switch (entry.phase) {
                    .Pre => {
                        var new_plain: bool = undefined;
                        if (entry.plain) {
                            switch (entry.node.data.value) {
                                .Text, .HtmlInline, .Code => |literal| {
                                    try self.writeAll(literal);
                                },
                                .LineBreak, .SoftBreak => {
                                    try self.writeAll(" ");
                                },
                                else => {},
                            }
                            new_plain = entry.plain;
                        } else {
                            try stack.append(.{ .node = entry.node, .plain = false, .phase = .Post });
                            new_plain = try self.fnode(entry.node, true);
                        }

                        var it = entry.node.reverseChildrenIterator();
                        while (it.next()) |ch| {
                            try stack.append(.{ .node = ch, .plain = new_plain, .phase = .Pre });
                        }
                    },
                    .Post => {
                        std.debug.assert(!entry.plain);
                        _ = try self.fnode(entry.node, false);
                    },
                }
            }
        }

        fn fnode(self: *Self, node: *AstNode, entering: bool) !bool {
            switch (node.data.value) {
                .Document => {},
                .BlockQuote => {
                    if (entering) {
                        try self.writeAll("\n");
                    } else {
                        try self.cr();
                    }
                },
                .List => |_| {
                    if (entering) {
                        try self.cr();
                    } else {
                        try self.writeAll("\n");
                    }
                },
                .Item => |parent| {
                    if (entering) {
                        try self.cr();
                        if (parent.list_type == .Bullet) {
                            try self.writeAll("• ");
                        } else {
                            try self.writer.print("{d}. ", .{parent.start});
                        }
                    } else {
                        try self.cr();
                    }
                },
                .Heading => |nch| {
                    if (entering) {
                        try self.cr();
                        for (0..(nch.level + 1)) |_| {
                            try self.writeAll("#");
                        }
                        try self.writeAll(" ");
                    } else {
                        try self.writeAll("\n");
                    }
                },
                .CodeBlock => |ncb| {
                    if (entering) {
                        try self.cr();
                        const got_language = if (ncb.info) |info| codeTag: {
                            if (info.len == 0) break :codeTag false;

                            var first_tag: usize = 0;
                            while (first_tag < ncb.info.?.len and !ascii.isWhitespace(ncb.info.?[first_tag])) {
                                first_tag += 1;
                            }

                            try self.writer.print(ansi.WHITE ++ "```{s}" ++ ansi.DEFAULT, .{info[0..first_tag]});
                            try self.writeAll("\n");

                            break :codeTag true;
                        } else false;

                        if (!got_language) {
                            try self.writeAll("```\n");
                        }

                        try self.writeAll(ansi.YELLOW);
                        try self.writeAll(ncb.literal.items);
                        try self.writeAll(ansi.DEFAULT);

                        try self.writeAll(ansi.WHITE ++ "```\n\n" ++ ansi.DEFAULT);
                    }
                },
                .HtmlBlock => |_| {
                    if (entering) {
                        try self.cr();
                        try self.writeAll("<!-- raw HTML omitted -->");
                        try self.cr();
                    }
                },
                .ThematicBreak => {
                    if (entering) {
                        try self.cr();
                        try self.writeAll("____________________________________________________\n");
                    }
                },
                .Paragraph => {
                    const tight = node.parent != null and node.parent.?.parent != null and switch (node.parent.?.parent.?.data.value) {
                        .List => |nl| nl.tight,
                        else => false,
                    };

                    if (!tight and !entering) {
                        try self.writeAll("\n\n");
                    }
                },
                .Text => |literal| {
                    const skip = blk: {
                        if (node.parent) |prev| {
                            const active_tag = std.meta.activeTag(prev.data.value);
                            if (active_tag == .Link or active_tag == .Image) {
                                break :blk true;
                            }
                        }
                        break :blk false;
                    };

                    if (entering and !skip) {
                        try self.writeAll(literal);
                    }
                },
                .LineBreak, .SoftBreak => {
                    if (entering) {
                        try self.writeAll("\n");
                    }
                },
                .Code => |literal| {
                    if (entering) {
                        try self.writeAll(ansi.YELLOW);
                        try self.writeAll(literal);
                        try self.writeAll(ansi.DEFAULT);
                    }
                },
                .HtmlInline => |_| {
                    if (entering) {
                        try self.writeAll("<!-- raw HTML omitted -->");
                    }
                },
                .Strong => {
                    try self.writeAll(if (entering) ansi.BOLD else ansi.R_BOLD);
                },
                .Emph => {
                    try self.writeAll(if (entering) ansi.ITALIC else ansi.R_ITALIC);
                },
                .Strikethrough => {
                    try self.writeAll(if (entering) ansi.STRIKE else ansi.R_STRIKE);
                },
                .Link => |nl| {
                    // This is quite an ugly hack for getting the real title.
                    // The title node shows up inside the link node, so we just
                    // take the first child and run with it if it's of type `Text`.
                    // This probably won't work with marked-up titles, so this
                    // will handle that semi-gracefully to avoid panics.
                    //
                    // This is likely a parsing issue as the title field should be empty.
                    const title = blk: {
                        if (node.first_child) |child| {
                            if (std.meta.activeTag(child.data.value) == .Text) {
                                break :blk child.data.value.Text;
                            }
                        }
                        break :blk "";
                    };

                    if (entering) {
                        try self.writer.print(ansi.GREEN ++ "{s} " ++ ansi.BLUE ++ ansi.UNDERLINE ++ "{s}" ++ ansi.DEFAULT ++ ansi.R_UNDERLINE, .{ title, nl.url });
                    }
                },
                .Image => |nl| {
                    // This is quite an ugly hack for getting the real title.
                    // The title node shows up inside the image node, so we just
                    // take the first child and run with it if it's of type `Text`.
                    // This probably won't work with marked-up titles, so this
                    // will handle that semi-gracefully to avoid panics.
                    //
                    // This is likely a parsing issue as the title field should not be empty.
                    const title = blk: {
                        if (node.first_child) |child| {
                            if (std.meta.activeTag(child.data.value) == .Text) {
                                break :blk child.data.value.Text;
                            }
                        }
                        break :blk "";
                    };

                    if (entering) {
                        try self.writer.print(ansi.GREEN ++ "!{s}" ++ ansi.BLUE ++ " {s} " ++ ansi.DEFAULT, .{ title, nl.url });
                    }
                },
                // Tables are quite uncommon, so they should just be printed verbatim.
                // Don't try to format these, as they take too much effort to decode
                // and will likely obscure the meaning conveyed.
                .Table => {
                    if (entering) {
                        try self.cr();
                        try self.writeAll(node.data.content.items);
                    }
                },
                .TableRow, .TableCell => {},
            }
            return false;
        }
    };
}
