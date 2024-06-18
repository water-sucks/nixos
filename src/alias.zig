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

    const c = config.getConfig();
    if (c.aliases == null or c.aliases.?.count() == 0) {
        println(stdout, "No aliases are configured.", .{});
        return;
    }

    const alias_map = c.aliases.?;

    // Let's align the alias column to the max length.alias =
    // I freaking love alignment.
    const max_column_len = blk: {
        var max_len: usize = 0;
        var it = alias_map.iterator();
        while (it.next()) |kv| {
            const alias = kv.key_ptr.*;
            max_len = @max(alias.len, max_len);
        }
        break :blk max_len;
    };

    var it = alias_map.iterator();
    while (it.next()) |kv| {
        const alias = kv.key_ptr.*;
        const resolved = kv.value_ptr.array.items;

        print(stdout, "{s}", .{alias});
        var k: usize = max_column_len - alias.len;
        while (k > 0) {
            print(stdout, " ", .{});
            k -= 1;
        }
        print(stdout, " :: ", .{});
        if (resolved.len == 1) {
            println(stdout, "{s}", .{resolved[0].string});
        } else if (resolved.len > 1) {
            for (resolved[0..(resolved.len - 1)]) |arg| {
                print(stdout, "{s} ", .{arg.string});
            }
            println(stdout, "{s}", .{resolved[resolved.len - 1].string});
        }
    }
}
