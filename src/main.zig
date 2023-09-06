const std = @import("std");
const mem = @import("mem");

const argparse = @import("argparse.zig");
const build = @import("build.zig");
const log = @import("log.zig");

const usage =
    \\Usage:
    \\    nixos <command> [command options]
    \\
    \\Commands:
    \\    build    Build a NixOS configuration
    \\
    \\Options:
    \\    -h, --help    Show this help menu
    \\
    \\For more information about a command, add --help.
    \\
;

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const allocator = arena_allocator.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name
    _ = args.next();

    const next_arg = args.next();

    if (next_arg == null) {
        log.print("{s}\n", .{usage});
        log.err("no subcommand specified", .{});
        return 1;
    }

    const arg = next_arg.?;

    if (argparse.argIs(arg, "--help", "-h")) {
        log.print(usage, .{});
        return 0;
    }

    if (mem.eql(u8, arg, "build")) {
        return build.buildMain(allocator, &args);
    } else {
        log.print("{s}\n", .{usage});
        if (argparse.isFlag(arg)) {
            log.err("unrecognised flag {s}", .{arg});
        } else {
            log.err("unknown subcommand {s}", .{arg});
        }
        return 1;
    }

    return 0;
}
