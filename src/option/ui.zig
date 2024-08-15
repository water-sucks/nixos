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
const CandidateStruct = utils.search.CandidateStruct;

const option_cmd = @import("../option.zig");
const NixosOption = option_cmd.NixosOption;
const OptionCandidate = CandidateStruct(NixosOption);

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

fn compareOptionCandidatesReverse(_: void, a: OptionCandidate, b: OptionCandidate) bool {
    if (b.rank < a.rank) return true;
    if (b.rank > a.rank) return false;

    const bb = b.value.name;
    const aa = a.value.name;

    if (bb.len < aa.len) return true;
    if (bb.len > aa.len) return false;

    for (bb, 0..) |c, i| {
        if (c < aa[i]) return true;
        if (c > aa[i]) return false;
    }

    return false;
}

pub const OptionSearchTUI = struct {
    allocator: Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    should_quit: bool = false,

    // Components
    search_input: TextInput,

    // Application state
    options: []const NixosOption,
    candidate_filter_buf: []OptionCandidate,
    option_results: []OptionCandidate,
    option_list_ctx: vaxis.widgets.Table.TableContext,

    const Self = @This();

    pub fn init(allocator: Allocator, options: []const NixosOption) !Self {
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
            .search_input = text_input,
            .options = options,

            .candidate_filter_buf = candidate_filter_buf,
            .option_results = initial_results,
            .option_list_ctx = .{
                .selected_bg = .{ .index = 1 },
                .row = options.len - 1,
            },
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
            .key_press => |key| blk: {
                if (key.matches(vaxis.Key.up, .{})) {
                    self.option_list_ctx.row -|= 1;
                    break :blk;
                }
                if (key.matches(vaxis.Key.down, .{})) {
                    if (self.option_list_ctx.row < self.option_results.len - 1) {
                        self.option_list_ctx.row +|= 1;
                    }
                    break :blk;
                } else if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                } else {
                    try self.search_input.update(.{ .key_press = key });

                    const search_query = self.search_input.buf.items;
                    const tokens: []const []const u8 = toks: {
                        var items = ArrayList([]const u8).init(allocator);
                        errdefer items.deinit();

                        var iter = mem.tokenizeScalar(u8, search_query, ' ');
                        while (iter.next()) |token| {
                            try items.append(token);
                        }

                        break :toks try items.toOwnedSlice();
                    };

                    const results = utils.search.rankCandidatesStruct(NixosOption, "name", self.candidate_filter_buf, self.options, tokens, true, true);
                    std.sort.block(OptionCandidate, results, {}, compareOptionCandidatesReverse);
                    self.option_list_ctx.row = if (results.len > 0) results.len - 1 else 0;
                    self.option_results = results;
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

        // Don't show all results if the search bar is empty.
        if (self.search_input.buf.items.len == 0) {
            return main_win;
        }

        const table_win: vaxis.Window = main_win.child(.{
            .y_off = 2,
            .height = .{ .limit = main_win.height - 2 },
        });
        const gen_list = self.option_results;
        var ctx = self.option_list_ctx;

        const max_items = if (gen_list.len > table_win.height -| 1)
            table_win.height -| 1
        else
            gen_list.len;
        var end = ctx.start + max_items;
        if (end > gen_list.len) end = gen_list.len;
        ctx.start = tableStart: {
            if (ctx.row == 0)
                break :tableStart 0;
            if (ctx.row < ctx.start)
                break :tableStart ctx.start - (ctx.start - ctx.row);
            if (ctx.row >= gen_list.len - 1)
                ctx.row = gen_list.len - 1;
            if (ctx.row >= end)
                break :tableStart ctx.start + (ctx.row - end + 1);
            break :tableStart ctx.start;
        };
        end = ctx.start + max_items;
        if (end > gen_list.len) end = gen_list.len;

        const selected_row = ctx.row;

        for (gen_list[ctx.start..end], 0..) |data, i| {
            const option = data.value;

            const tile = table_win.child(.{
                .y_off = i,
                .width = .{ .limit = table_win.width },
                .height = .{ .limit = 1 },
            });

            const selected = ctx.start + i == selected_row;
            const tile_bg: vaxis.Color = if (selected) .{ .index = 6 } else .{ .index = 0 };

            if (selected) {
                tile.fill(.{ .style = .{ .bg = tile_bg } });
            }

            const generation_seg: vaxis.Segment = .{
                .text = option.name,
                .style = .{ .bg = tile_bg },
            };
            const selected_arrow_seg: vaxis.Segment = .{
                .text = "->",
                .style = .{ .bg = tile_bg },
            };

            _ = try tile.printSegment(generation_seg, .{ .col_offset = 3 });
            if (selected) {
                _ = try tile.printSegment(selected_arrow_seg, .{});
            }
        }

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
        self.search_input.draw(input_win);
        if (self.search_input.buf.items.len == 0) {
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
        self.allocator.free(self.candidate_filter_buf);
        self.search_input.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }
};

pub fn optionSearchUI(allocator: Allocator, options: []const NixosOption) !void {
    var app = try OptionSearchTUI.init(allocator, options);
    defer app.deinit();

    try app.run();
}
