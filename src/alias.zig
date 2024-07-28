const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");
const fmt = std.fmt;
const io = std.io;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;

const log = @import("log.zig");

const config = @import("config.zig");

const utils = @import("utils.zig");
const println = utils.println;
const print = utils.print;

pub const AliasesCommand = struct {
    json: bool = false,

    const usage =
        \\List configured aliases and what commands they resolve to.
        \\
        \\Usage:
        \\    nixos aliases [options]
        \\
        \\Options:
        \\    -h, --help    Show this help menu
        \\    -j, --json    Output aliases in JSON format
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *AliasesCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--json", "-j")) {
                parsed.json = true;
            } else {
                return arg;
            }

            next_arg = argv.next();
        }

        return null;
    }
};

pub fn printAliases(args: AliasesCommand) void {
    const stdout = io.getStdOut().writer();

    const c = config.getConfig();
    if (c.aliases == null or c.aliases.?.count() == 0) {
        if (args.json) {
            println(stdout, "[]", .{});
        } else {
            println(stdout, "No aliases are configured.", .{});
        }
        return;
    }

    const alias_map = c.aliases.?;

    if (args.json) {
        // std.json does not take well to stringifying a dynamic hashmap.
        // We'll do it ourselves.
        var it = alias_map.iterator();

        println(stdout, "{{", .{});
        while (it.next()) |kv| {
            const alias = kv.key_ptr.*;
            const resolved_args = kv.value_ptr.array.items;

            print(stdout, "  \"{s}\": [", .{alias});
            for (resolved_args, 0..) |arg, i| {
                print(stdout, "\"{s}\"", .{arg.string});
                if (i < resolved_args.len - 1) {
                    print(stdout, ", ", .{});
                }
            }
            println(stdout, "]", .{});
        }
        println(stdout, "}}", .{});
        return;
    }

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
