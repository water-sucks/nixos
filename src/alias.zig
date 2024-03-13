const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");
const io = std.io;
const mem = std.mem;

const config = @import("config.zig");

const utils = @import("utils.zig");
const println = utils.println;
const print = utils.print;

pub fn printAliases() void {
    const stdout = io.getStdOut().writer();

    const aliases = config.getConfig().aliases orelse &.{};
    if (aliases.len == 0) {
        println(stdout, "No aliases are configured.", .{});
        return;
    }

    // Let's align the alias column to the max length.alias =
    // I freaking love alignment.
    var max_column_len = blk: {
        var max_len = aliases[0].alias.len;
        for (aliases) |alias| {
            max_len = @max(alias.alias.len, max_len);
        }
        break :blk max_len;
    };

    for (aliases) |alias| {
        print(stdout, "{s}", .{alias.alias});
        var k: usize = max_column_len - alias.alias.len;
        while (k > 0) {
            print(stdout, " ", .{});
            k -= 1;
        }
        print(stdout, " :: ", .{});
        const resolved = alias.resolve;
        if (resolved.len == 1) {
            println(stdout, "{s}", .{resolved[0]});
        } else if (resolved.len > 1) {
            for (resolved[0..(resolved.len - 1)]) |arg| {
                print(stdout, "{s} ", .{arg});
            }
            println(stdout, "{s}", .{resolved[resolved.len - 1]});
        }
    }
}
