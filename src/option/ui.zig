const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const config = @import("../config.zig");

const log = @import("../log.zig");

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const TextView = vaxis.widgets.TextView;
const TextViewBuffer = TextView.Buffer;

const utils = @import("../utils.zig");
const ansi = utils.ansi;
const runCmd = utils.runCmd;
const CandidateStruct = utils.search.CandidateStruct;

const option_cmd = @import("../option.zig");
const NixosOption = option_cmd.NixosOption;
const OptionCandidate = CandidateStruct(NixosOption);

const zf = @import("zf");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

fn compareOptionCandidates(_: void, a: OptionCandidate, b: OptionCandidate) bool {
    if (a.rank < b.rank) return true;
    if (a.rank > b.rank) return false;

    const aa = a.value.name;
    const bb = b.value.name;

    if (aa.len < bb.len) return true;
    if (aa.len > bb.len) return false;

    for (aa, 0..) |c, i| {
        if (c < bb[i]) return true;
        if (c > bb[i]) return false;
    }

    return false;
}

pub const OptionSearchTUI = struct {
    allocator: Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    should_quit: bool = false,
    max_rank: f64,

    // Components
    search_input: TextInput,
    option_view: TextView,
    option_view_buf: TextViewBuffer,

    // Application state
    options: []const NixosOption,
    candidate_filter_buf: []OptionCandidate,
    option_results: []OptionCandidate,

    results_ctx: struct {
        start: usize = 0,
        row: usize = 0,
    } = .{},
    active_window: enum { input, preview },

    const Self = @This();

    pub fn init(allocator: Allocator, options: []const NixosOption, max_rank: f64) !Self {
        var tty = try vaxis.Tty.init();
        errdefer tty.deinit();

        var vx = try vaxis.init(allocator, .{});
        errdefer vx.deinit(allocator, tty.anyWriter());

        var text_input = TextInput.init(allocator, &vx.unicode);
        errdefer text_input.deinit();

        const candidate_filter_buf = try allocator.alloc(CandidateStruct(NixosOption), options.len);
        errdefer allocator.free(candidate_filter_buf);

        const initial_results = utils.search.rankCandidatesStruct(NixosOption, "name", candidate_filter_buf, options, &.{}, true, true);

        return OptionSearchTUI{
            .allocator = allocator,
            .tty = tty,
            .vx = vx,
            .max_rank = max_rank,

            .search_input = text_input,
            .option_view = TextView{},
            .option_view_buf = TextViewBuffer{},

            .options = options,
            .candidate_filter_buf = candidate_filter_buf,
            .option_results = initial_results,
            .active_window = .input,
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
        var ctx = &self.results_ctx;

        switch (event) {
            .key_press => |key| blk: {
                if (key.matches(vaxis.Key.tab, .{}) or key.matches(vaxis.Key.tab, .{ .shift = true })) {
                    if (self.active_window == .input) {
                        self.active_window = .preview;
                    } else {
                        self.active_window = .input;
                    }
                    break :blk;
                } else if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                    break :blk;
                }

                if (self.active_window == .input) {
                    if (key.matches(vaxis.Key.down, .{})) {
                        if (self.option_results.len == 0) break :blk;

                        if (ctx.row == 0) {
                            ctx.row = self.option_results.len - 1;
                        } else {
                            ctx.row -|= 1;
                        }
                        break :blk;
                    } else if (key.matches(vaxis.Key.up, .{})) {
                        if (self.option_results.len == 0) break :blk;

                        if (ctx.row == self.option_results.len - 1) {
                            ctx.row = 0;
                        } else {
                            ctx.row += 1;
                        }

                        break :blk;
                    } else {
                        try self.search_input.update(.{ .key_press = key });

                        const tokens = try utils.splitScalarAlloc(allocator, self.search_input.buf.items, ' ');

                        const results = utils.search.rankCandidatesStruct(NixosOption, "name", self.candidate_filter_buf, self.options, tokens, true, true);
                        std.sort.block(OptionCandidate, results, {}, compareOptionCandidates);
                        ctx.row = 0;
                        self.option_results = maxRankFilter: {
                            var end_index: usize = 0;
                            for (results) |result| {
                                if (result.rank > self.max_rank) {
                                    break;
                                }
                                end_index += 1;
                            }
                            break :maxRankFilter results[0..end_index];
                        };
                    }
                } else if (self.active_window == .preview) {
                    if (key.matchesAny(&.{ vaxis.Key.left, 'h' }, .{})) {
                        if (self.option_results.len == 0) break :blk;
                        self.option_view.scroll_view.scroll.x -|= 1;
                    } else if (key.matchesAny(&.{ vaxis.Key.down, 'j' }, .{})) {
                        if (self.option_results.len == 0) break :blk;
                        self.option_view.scroll_view.scroll.y +|= 1;
                    } else if (key.matchesAny(&.{ vaxis.Key.up, 'k' }, .{})) {
                        if (self.option_results.len == 0) break :blk;
                        self.option_view.scroll_view.scroll.y -|= 1;
                    } else if (key.matchesAny(&.{ vaxis.Key.right, 'l' }, .{})) {
                        if (self.option_results.len == 0) break :blk;
                        self.option_view.scroll_view.scroll.x +|= 1;
                    }
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
        }

        try self.draw(allocator);
        try self.vx.render(self.tty.anyWriter());
    }

    fn draw(self: *Self, allocator: Allocator) !void {
        const root_win = self.vx.window();
        root_win.clear();

        _ = try self.drawResultsList(allocator);
        _ = try self.drawSearchBar(allocator);
        _ = try self.drawResultPreview(allocator);
    }

    fn drawResultsList(self: *Self, allocator: Allocator) !vaxis.Window {
        const root_win = self.vx.window();

        var main_win = root_win.child(.{
            .width = .{ .limit = root_win.width / 2 },
            .height = .{ .limit = root_win.height - 3 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = if (self.active_window == .input) 5 else 7 } },
                .glyphs = .single_square,
            },
        });

        const query = self.search_input.buf.items;

        const title_seg: vaxis.Segment = .{
            .text = "Results",
            .style = .{ .bold = true },
        };
        const title_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });
        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        // Don't show all results if the search bar is empty.
        if (query.len == 0) {
            return main_win;
        }

        const table_win: vaxis.Window = main_win.child(.{
            .y_off = 2,
            .height = .{ .limit = main_win.height - 2 },
        });
        const options = self.option_results;

        if (options.len == 0) {
            return main_win;
        }

        var ctx = &self.results_ctx;

        const rows = @min(table_win.height, options.len);

        var end = ctx.start + rows;
        if (end > options.len) end = options.len;

        ctx.start = blk: {
            if (ctx.row == 0)
                break :blk 0;

            if (ctx.row < ctx.start)
                break :blk ctx.start - (ctx.start - ctx.row);

            if (ctx.row >= end)
                break :blk ctx.start + (ctx.row - end + 1);

            break :blk ctx.start;
        };

        end = ctx.start + rows;
        if (end > options.len) end = options.len;

        const selected_row = ctx.row;
        const tokens = try utils.splitScalarAlloc(allocator, self.search_input.buf.items, ' ');

        const matches_buf = blk: {
            var size: usize = 0;
            for (options[ctx.start..end]) |data| {
                size = @max(size, data.value.name.len);
            }
            break :blk try allocator.alloc(usize, size);
        };

        for (options[ctx.start..end], 0..) |data, i| {
            const option = data.value;

            const tile = table_win.child(.{
                .y_off = table_win.height -| i -| 1,
                .width = .{ .limit = table_win.width },
                .height = .{ .limit = 1 },
            });

            const selected = ctx.start + i == selected_row;
            const tile_bg: vaxis.Color = if (selected) .{ .index = 6 } else .{ .index = 0 };

            if (selected) {
                tile.fill(.{ .style = .{ .bg = tile_bg } });
            }

            const option_name_seg: vaxis.Segment = .{
                .text = option.name,
                .style = .{
                    .bg = tile_bg,
                },
            };
            _ = try tile.printSegment(option_name_seg, .{ .col_offset = 3 });

            const matches = zf.highlight(option.name, tokens, true, true, matches_buf);
            for (matches) |idx| {
                const cell: vaxis.Cell = .{
                    .char = .{ .grapheme = option.name[idx..(idx + 1)] },
                    .style = .{
                        .fg = .{ .index = 2 },
                        .bg = tile_bg,
                    },
                };
                tile.writeCell(3 + idx, 0, cell);
            }

            if (selected) {
                const selected_arrow_seg: vaxis.Segment = .{
                    .text = "->",
                    .style = .{
                        .fg = .{ .index = 1 },
                        .bg = tile_bg,
                    },
                };
                _ = try tile.printSegment(selected_arrow_seg, .{});
            }
        }

        return main_win;
    }

    fn drawSearchBar(self: *Self, allocator: Allocator) !vaxis.Window {
        const root_win = self.vx.window();
        const query = self.search_input.buf.items;

        const search_bar_win = root_win.child(.{
            .y_off = root_win.height - 3,
            .width = .{ .limit = root_win.width / 2 },
            .height = .{ .limit = 3 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = if (self.active_window == .input) 5 else 7 } },
                .glyphs = .single_square,
            },
        });

        const placeholder_seg: vaxis.Segment = .{
            .text = "Search for options...",
            .style = .{
                .fg = .{ .index = 4 },
            },
        };
        _ = try search_bar_win.printSegment(.{ .text = ">" }, .{});

        const count_seg: vaxis.Segment = .{
            .text = if (query.len != 0) try fmt.allocPrint(allocator, "{d} / {d}", .{ self.option_results.len, self.options.len }) else "",
            .style = .{ .fg = .{ .index = 4 } },
        };
        if (count_seg.text.len != 0) {
            _ = try search_bar_win.printSegment(count_seg, .{ .col_offset = search_bar_win.width - count_seg.text.len });
        }

        var input_win = search_bar_win.child(.{
            .x_off = 2,
            .width = .{ .limit = search_bar_win.width - 2 - count_seg.text.len },
        });
        self.search_input.draw(input_win);
        if (self.search_input.buf.items.len == 0) {
            _ = try input_win.printSegment(placeholder_seg, .{});
        }

        return search_bar_win;
    }

    fn drawResultPreview(self: *Self, allocator: Allocator) !vaxis.Window {
        const root_win = self.vx.window();

        const main_win = root_win.child(.{
            .x_off = root_win.width / 2,
            .width = .{ .limit = root_win.width / 2 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = if (self.active_window == .preview) 5 else 7 } },
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

        const info_win: vaxis.Window = main_win.child(.{
            .y_off = 2,
            .height = .{ .limit = main_win.height - 2 },
        });

        if (self.search_input.buf.items.len == 0) {
            return main_win;
        }

        if (self.option_results.len == 0) {
            _ = try info_win.printSegment(.{
                .text = "No results found.",
                .style = .{
                    .italic = true,
                    .fg = .{ .index = 1 },
                },
            }, .{});
            return main_win;
        }

        const opt = self.option_results[self.results_ctx.row].value;

        if (self.option_view.scroll_view.scroll.x > info_win.width - 1) {
            self.option_view.scroll_view.scroll.x = info_win.width - 1;
        }
        if (self.option_view.scroll_view.scroll.y > info_win.height) {
            self.option_view.scroll_view.scroll.y = info_win.height - 1;
        }

        self.option_view_buf.clear(self.allocator);

        try self.appendToBuffer("Name\n", .{ .bold = true });
        try self.appendToBuffer(opt.name, .{});
        try self.appendToBuffer("\n\n", .{});

        try self.appendToBuffer("Description\n", .{ .bold = true });
        if (opt.description) |d| {
            try self.appendToBuffer(mem.trim(u8, d, "\n"), .{});
        } else {
            try self.appendToBuffer("(none)", .{ .italic = true });
        }
        try self.appendToBuffer("\n\n", .{});

        try self.appendToBuffer("Type\n", .{ .bold = true });
        try self.appendToBuffer(opt.type, .{ .italic = true });
        try self.appendToBuffer("\n\n", .{});

        try self.appendToBuffer("Default\n", .{ .bold = true });
        if (opt.default) |d| {
            try self.appendToBuffer(mem.trim(u8, d.text, "\n"), .{ .fg = .{ .index = 7 } });
        } else {
            try self.appendToBuffer("(none)", .{ .italic = true });
        }
        try self.appendToBuffer("\n\n", .{});

        if (opt.example) |e| {
            try self.appendToBuffer("Example\n", .{ .bold = true });
            try self.appendToBuffer(mem.trim(u8, e.text, "\n"), .{ .fg = .{ .index = 7 } });
            try self.appendToBuffer("\n\n", .{});
        }

        if (opt.declarations.len > 0) {
            try self.appendToBuffer("Declared In\n", .{ .bold = true });
            for (opt.declarations) |decl| {
                try self.appendToBuffer(try fmt.allocPrint(allocator, "  - {s}\n", .{decl}), .{ .italic = true });
            }
            try self.appendToBuffer("\n", .{});
        }

        _ = self.option_view.draw(info_win, self.option_view_buf);

        return main_win;
    }

    fn appendToBuffer(self: *Self, content: []const u8, style: vaxis.Style) !void {
        const begin = self.option_view_buf.content.items.len;
        const end = begin + content.len + 1;

        try self.option_view_buf.append(self.allocator, .{
            .bytes = content,
            .gd = &self.vx.unicode.grapheme_data,
            .wd = &self.vx.unicode.width_data,
        });
        try self.option_view_buf.updateStyle(self.allocator, .{
            .begin = begin,
            .end = end,
            .style = style,
        });
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.candidate_filter_buf);
        self.option_view_buf.deinit(self.allocator);
        self.search_input.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }
};

pub fn optionSearchUI(allocator: Allocator, options: []const NixosOption) !void {
    const c = config.getConfig();

    var app = try OptionSearchTUI.init(allocator, options, c.option.max_rank);
    defer app.deinit();

    try app.run();
}
