const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const log = @import("../log.zig");

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;

const utils = @import("../utils.zig");
const GenerationMetadata = utils.generation.GenerationMetadata;
const CandidateStruct = utils.search.CandidateStruct;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub const GenerationTUI = struct {
    allocator: Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    should_quit: bool = false,
    mode: Mode,

    // Components
    search_input: TextInput,

    // Generation state
    gen_list: ArrayList(GenerationMetadata),
    gen_list_ctx: vaxis.widgets.Table.TableContext,
    candidate_filter_buf: []CandidateStruct(GenerationMetadata),
    filtered_gen_list: []CandidateStruct(GenerationMetadata),

    const Self = @This();

    const Mode = enum { normal, input };

    pub fn init(allocator: Allocator, gen_list: ArrayList(GenerationMetadata)) !Self {
        var tty = try vaxis.Tty.init();
        errdefer tty.deinit();

        var vx = try vaxis.init(allocator, .{});
        errdefer vx.deinit(allocator, tty.anyWriter());

        var text_input = TextInput.init(allocator, &vx.unicode);
        errdefer text_input.deinit();

        const candidate_filter_buf = try allocator.alloc(CandidateStruct(GenerationMetadata), gen_list.items.len);
        errdefer allocator.free(candidate_filter_buf);

        // This is to render the initial generation list.
        const initial_filtered_gen_slice = utils.search.rankCandidatesStruct(GenerationMetadata, "description", candidate_filter_buf, gen_list.items, &.{}, true, true);

        const current_gen_idx = blk: {
            for (gen_list.items, 0..) |gen, i| {
                if (gen.current) {
                    break :blk i;
                }
            }
            unreachable;
        };

        return GenerationTUI{
            .allocator = allocator,
            .tty = tty,
            .vx = vx,
            .search_input = text_input,
            .mode = .normal,

            .gen_list = gen_list,
            .gen_list_ctx = .{
                .selected_bg = .{ .index = 1 },
                .row = current_gen_idx,
            },
            .candidate_filter_buf = candidate_filter_buf,
            .filtered_gen_list = initial_filtered_gen_slice,
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
                // Arrow keys and CTRL codes should work regardless of input mode
                if (key.matches(vaxis.Key.up, .{})) {
                    self.gen_list_ctx.row -|= 1;
                    break :blk;
                } else if (key.matches(vaxis.Key.down, .{})) {
                    if (self.gen_list_ctx.row < self.filtered_gen_list.len - 1) {
                        self.gen_list_ctx.row +|= 1;
                    }
                    break :blk;
                } else if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                    break :blk;
                }

                if (self.mode == .input) {
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.mode = .normal;
                    } else {
                        try self.search_input.update(.{ .key_press = key });
                        // TODO: debounce?
                        // TODO: split tokens so that they work better
                        const search_query = self.search_input.buf.items;
                        self.filtered_gen_list = utils.search.rankCandidatesStruct(
                            GenerationMetadata,
                            "description",
                            self.candidate_filter_buf,
                            self.gen_list.items,
                            if (search_query.len > 0) &.{search_query} else &.{},
                            true,
                            true,
                        );
                    }
                } else {
                    if (key.matchesAny(&.{ vaxis.Key.up, 'k' }, .{})) {
                        self.gen_list_ctx.row -|= 1;
                    } else if (key.matchesAny(&.{ vaxis.Key.down, 'j' }, .{})) {
                        if (self.gen_list_ctx.row < self.gen_list.items.len - 1) {
                            self.gen_list_ctx.row +|= 1;
                        }
                    } else if (key.matches('q', .{})) {
                        self.should_quit = true;
                    } else if (key.matches('/', .{})) {
                        self.mode = .input;
                    }
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
        }

        try self.draw(allocator);
        try self.vx.render(self.tty.anyWriter());
    }

    fn draw(self: *Self, allocator: Allocator) !void {
        const win = self.vx.window();
        win.clear();

        _ = try self.drawGenerationTable(allocator);
        _ = try self.drawSearchBar();
        _ = try self.drawGenerationData(allocator);
        _ = try self.drawSelectedGenerations();
        _ = try self.drawKeybindList();
    }

    fn drawGenerationTable(self: *Self, allocator: Allocator) !vaxis.Window {
        const root_win = self.vx.window();

        var main_win = root_win.child(.{
            .width = .{ .limit = root_win.width / 6 },
            .height = .{ .limit = root_win.height },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });
        const title_seg: vaxis.Segment = .{
            .text = "Generations",
            .style = .{ .bold = true },
        };
        const title_bar_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });
        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_bar_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        const table_win: vaxis.Window = main_win.child(.{
            .y_off = 2,
            .height = .{ .limit = main_win.height - 2 },
        });

        const gen_list = self.filtered_gen_list;
        const ctx = self.gen_list_ctx;

        const max_items = if (gen_list.len > table_win.height -| 2)
            table_win.height -| 2
        else
            gen_list.len;
        var end = ctx.start + max_items;
        if (end > gen_list.len) end = gen_list.len;

        // TODO: fix starting point for rendering
        const selected_row = ctx.row;

        for (gen_list[ctx.start..end], 0..) |data, i| {
            const gen = data.value;

            const tile = table_win.child(.{
                .x_off = 3,
                .y_off = i,
                .width = .{ .limit = table_win.width },
                .height = .{ .limit = 1 },
            });

            const generation_segment: vaxis.Segment = .{
                .text = try fmt.allocPrint(allocator, "{d}", .{gen.generation.?}),
                .style = .{
                    .fg = if (gen.current) .{ .index = 2 } else .{ .index = 7 },
                    .bg = if (selected_row == i) .{ .index = 6 } else .{ .index = 0 },
                },
            };

            _ = try tile.printSegment(generation_segment, .{});
        }

        const mode_win: vaxis.Window = main_win.child(.{
            .y_off = main_win.height - 1,
            .height = .{ .limit = 1 },
        });
        const mode_seg: vaxis.Segment = .{ .text = try fmt.allocPrint(allocator, "{s}", .{@tagName(self.mode)}) };
        _ = try mode_win.printSegment(mode_seg, .{});

        return main_win;
    }

    /// Input bar for searching generations by description.
    fn drawSearchBar(self: *Self) !vaxis.Window {
        const root_win = self.vx.window();

        const search_bar_win = root_win.child(.{
            .x_off = root_win.width / 6,
            .y_off = root_win.height - 3,
            .width = .{ .limit = root_win.width - (root_win.width / 6) },
            .height = .{ .limit = 3 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });
        self.search_input.draw(search_bar_win);

        return search_bar_win;
    }

    fn printInfoRows(win: vaxis.Window, title: []const u8, value: []const u8, row_offset: *usize) !void {
        const gen_number_title_seg: vaxis.Segment = .{
            .text = title,
            .style = .{ .bold = true },
        };
        const gen_number_seg: vaxis.Segment = .{
            .text = value,
            .style = .{ .italic = true },
        };
        _ = try win.printSegment(gen_number_title_seg, .{ .row_offset = row_offset.*, .col_offset = 3 });
        row_offset.* += 1;
        _ = try win.printSegment(gen_number_seg, .{ .row_offset = row_offset.*, .col_offset = 3 });
        row_offset.* += 2;
    }

    /// Print the information for a selected generation.
    fn drawGenerationData(self: *Self, allocator: Allocator) !vaxis.Window {
        const root_win = self.vx.window();

        const main_win: vaxis.Window = root_win.child(.{
            .x_off = root_win.width / 6,
            .width = .{ .limit = root_win.width / 2 },
            .height = .{ .limit = root_win.height - 3 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });
        const title_seg: vaxis.Segment = .{
            .text = "Information",
            .style = .{ .bold = true },
        };
        const title_bar_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });
        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_bar_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        const info_win: vaxis.Window = main_win.child(.{
            .y_off = 2,
            .height = .{ .limit = main_win.height - 2 },
        });

        const gen_info = self.gen_list.items[self.gen_list_ctx.row];

        var row_offset: usize = 0;

        const gen_number_value = try fmt.allocPrint(allocator, "{d}{s}", .{ gen_info.generation.?, if (gen_info.current) " (current)" else "" });
        try printInfoRows(info_win, "Generation #", gen_number_value, &row_offset);

        const creation_date_value = if (gen_info.date) |date|
            try fmt.allocPrint(allocator, "{s} {d:0>2}, {d} {d:0>2}:{d:0>2}:{d:0>2}", .{ date.month.name(), date.day, date.year, date.hour, date.minute, date.second })
        else
            "(unknown)";
        try printInfoRows(info_win, "Creation Date", creation_date_value, &row_offset);

        try printInfoRows(info_win, "Description", gen_info.description orelse "(none)", &row_offset);
        try printInfoRows(info_win, "NixOS Version", gen_info.nixos_version orelse "(unknown)", &row_offset);
        try printInfoRows(info_win, "Nixpkgs Revision", gen_info.nixpkgs_revision orelse "(unknown)", &row_offset);
        try printInfoRows(info_win, "Configuration Revision", gen_info.configuration_revision orelse "(unknown)", &row_offset);
        try printInfoRows(info_win, "Kernel Version", gen_info.kernel_version orelse "(unknown)", &row_offset);

        const specialisations_value = if (gen_info.specialisations != null and gen_info.specialisations.?.len > 0)
            try utils.concatStringsSep(allocator, gen_info.specialisations.?, ", ")
        else
            "(none)";
        try printInfoRows(info_win, "Specialisations", specialisations_value, &row_offset);

        return main_win;
    }

    /// Draw the selected generations to delete (to make it easier
    /// to grok without looking at the generation list markings)
    fn drawSelectedGenerations(self: *Self) !vaxis.Window {
        const root = self.vx.window();

        const main_win: vaxis.Window = root.child(.{
            .x_off = (root.width * 2) / 3,
            .width = .{ .limit = root.width / 3 },
            .height = .{ .limit = root.height / 2 },
            .border = .{
                .where = .all,
                .style = .{
                    .fg = .{ .index = 7 },
                },
                .glyphs = .single_square,
            },
        });
        const title_seg: vaxis.Segment = .{
            .text = "Selected Generations",
            .style = .{ .bold = true },
        };
        const title_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });
        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        return main_win;
    }

    /// Draw the list of available keymaps (vaguely less-like)
    fn drawKeybindList(self: *Self) !vaxis.Window {
        const root_win = self.vx.window();

        const main_win: vaxis.Window = root_win.child(.{
            .x_off = (root_win.width * 2) / 3,
            .y_off = root_win.height / 2,
            .width = .{ .limit = root_win.width / 3 },
            .height = .{ .limit = root_win.height / 2 - 2 },
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .index = 7 } },
                .glyphs = .single_square,
            },
        });
        const title_seg: vaxis.Segment = .{
            .text = "Keybinds",
            .style = .{ .bold = true },
        };
        const title_win: vaxis.Window = main_win.child(.{ .height = .{ .limit = 1 } });
        const centered: vaxis.Window = vaxis.widgets.alignment.center(title_win, title_seg.text.len, 2);
        _ = try centered.printSegment(title_seg, .{});

        const info_win: vaxis.Window = main_win.child(.{
            .y_off = 2,
            .height = .{ .limit = main_win.height - 2 },
        });

        const keybinds: []const []const []const u8 = &.{
            &.{ "k, Up", "move up list" },
            &.{ "j, Down", "move down list" },
            &.{ "/", "search by description" },
            &.{ "<Esc>", "exit input mode" },
            &.{ "<Space>", "toggle selection" },
            &.{ "d", "delete selections" },
            &.{ "q, ^C", "quit" },
        };

        comptime var row_offset: usize = 0;
        const desc_col_offset = blk: {
            comptime var max: usize = 0;
            inline for (keybinds) |keybind| {
                max = @max(keybind[0].len, max);
            }
            break :blk max + 1;
        };

        inline for (keybinds) |keybind| {
            const key_text = keybind[0];
            const key_desc = keybind[1];

            const key_seg: vaxis.Segment = .{ .text = key_text, .style = .{
                .fg = .{ .index = 7 },
            } };
            const key_desc_seg: vaxis.Segment = .{
                .text = " :: " ++ key_desc,
            };

            _ = try info_win.printSegment(key_seg, .{ .row_offset = row_offset, .col_offset = 1 });
            _ = try info_win.printSegment(key_desc_seg, .{ .row_offset = row_offset, .col_offset = desc_col_offset });
            row_offset += 1;
        }
        // var offset: usize = 0;

        return main_win;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.candidate_filter_buf);
        self.search_input.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }
};

pub fn generationUI(allocator: Allocator, generations: ArrayList(GenerationMetadata)) !void {
    var app = try GenerationTUI.init(allocator, generations);
    defer app.deinit();

    try app.run();
}
