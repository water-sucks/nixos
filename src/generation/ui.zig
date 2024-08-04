const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const vaxis = @import("vaxis");

const utils = @import("../utils.zig");
const GenerationMetadata = utils.generation.GenerationMetadata;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const GenerationTUI = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,

    pub fn init(allocator: std.mem.Allocator) !GenerationTUI {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *GenerationTUI) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *GenerationTUI) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();

        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        while (!self.should_quit) {
            loop.pollEvent();
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }
            self.draw();

            var buffered = self.tty.bufferedWriter();
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    pub fn update(self: *GenerationTUI, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }))
                    self.should_quit = true;
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
        }
    }

    pub fn draw(self: *GenerationTUI) void {
        const msg = "Hello, world!";
        const win = self.vx.window();
        win.clear();

        const child = win.child(.{
            .x_off = (win.width / 2) - 7,
            .y_off = win.height / 2 + 1,
            .width = .{ .limit = msg.len },
            .height = .{ .limit = 1 },
        });

        const style: vaxis.Style = .{
            .fg = .{
                .rgb = [3]u8{ 255, 0, 0 },
            },
        };

        _ = try child.printSegment(.{ .text = msg, .style = style }, .{});
    }
};

pub fn generationUI(allocator: Allocator, generations: []GenerationMetadata) !void {
    _ = generations;

    var app = try GenerationTUI.init(allocator);
    defer app.deinit();

    try app.run();
}
