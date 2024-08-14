const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const log = @import("../log.zig");

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;

const utils = @import("../utils.zig");
const ansi = utils.ansi;
const runCmd = utils.runCmd;
const GenerationMetadata = utils.generation.GenerationMetadata;
const CandidateStruct = utils.search.CandidateStruct;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub const OptionSearchTUI = struct {
    allocator: Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    should_quit: bool = false,
    text_input: TextInput,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var tty = try vaxis.Tty.init();
        errdefer tty.deinit();

        var vx = try vaxis.init(allocator, .{});
        errdefer vx.deinit(allocator, tty.anyWriter());

        var text_input = TextInput.init(allocator, &vx.unicode);
        errdefer text_input.deinit();

        return OptionSearchTUI{
            .allocator = allocator,
            .tty = tty,
            .vx = vx,
            .text_input = text_input,
        };
    }

    pub fn run(self: *Self) !void {
        var loop: vaxis.Loop(Event) = .{ .tty = &self.tty, .vaxis = &self.vx };
        try loop.init();

        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        while (!self.should_quit) {
            // NOTE: This is an arena for drawing stuff, do not remove. This
            // serves a different purpose than the existing self.allocator.
            var event_arena = std.heap.ArenaAllocator.init(self.allocator);
            defer event_arena.deinit();
            const event_alloc = event_arena.allocator();

            const event = loop.nextEvent();
            try self.update(event_alloc, event);
        }
    }

    pub fn update(self: *Self, allocator: Allocator, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                } else {
                    try self.text_input.update(.{ .key_press = key });
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
        }

        try self.draw(allocator);
        try self.vx.render(self.tty.anyWriter());
    }

    fn draw(self: *Self, allocator: Allocator) !void {
        _ = allocator;

        const root_win = self.vx.window();
        root_win.clear();

        _ = try self.drawResultsList();
        _ = try self.drawSearchBar();
        _ = try self.drawResultPreview();
    }

    fn drawResultsList(self: *Self) !vaxis.Window {
        const root_win = self.vx.window();

        var main_win = root_win.child(.{
            .width = .{ .limit = root_win.width / 2 },
            .height = .{ .limit = root_win.height - 3 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });

        const title_seg: vaxis.Segment = .{
            .text = "Results",
            .style = .{ .bold = true },
        };
        const title_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });

        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        return main_win;
    }

    fn drawSearchBar(self: *Self) !vaxis.Window {
        const root_win = self.vx.window();

        const search_bar_win = root_win.child(.{
            .y_off = root_win.height - 3,
            .width = .{ .limit = root_win.width / 2 },
            .height = .{ .limit = 3 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });

        const placeholder_seg: vaxis.Segment = .{ .text = "Search for options...", .style = .{
            .fg = .{ .index = 4 },
        } };

        _ = try search_bar_win.printSegment(.{ .text = ">" }, .{});

        var input_win = search_bar_win.child(.{
            .x_off = 2,
            .width = .{ .limit = search_bar_win.width - 2 },
        });
        self.text_input.draw(input_win);
        if (self.text_input.buf.items.len == 0) {
            _ = try input_win.printSegment(placeholder_seg, .{});
        }

        return search_bar_win;
    }

    fn drawResultPreview(self: *Self) !vaxis.Window {
        const root_win = self.vx.window();

        const main_win = root_win.child(.{
            .x_off = root_win.width / 2,
            .width = .{ .limit = root_win.width / 2 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });

        const title_seg: vaxis.Segment = .{
            .text = "Option Preview",
            .style = .{ .bold = true },
        };
        const title_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });

        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        return main_win;
    }

    pub fn deinit(self: *Self) void {
        self.text_input.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }
};

pub fn optionSearchUI(allocator: Allocator) !void {
    var app = try OptionSearchTUI.init(allocator);
    defer app.deinit();

    try app.run();
}
