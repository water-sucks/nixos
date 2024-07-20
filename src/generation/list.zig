const std = @import("std");

const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const json = std.json;
const mem = std.mem;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const argIs = argparse.argIs;
const argError = argparse.argError;
const ArgParseError = argparse.ArgParseError;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const GenerationMetadata = utils.generation.GenerationMetadata;
const print = utils.print;
const concatStringsSep = utils.concatStringsSep;
const stringLessThan = utils.stringLessThan;

pub const GenerationListArgs = struct {
    json: bool = false,

    const usage =
        \\List all generations in a NixOS profile and their details.
        \\
        \\Usage:
        \\    nixos generation list [options]
        \\
        \\Options:
        \\    -h, --help    Show this help menu
        \\    -j, --json    Display format as JSON
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationListArgs) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
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

const GenerationListError = error{
    PermissionDenied,
    ResourceAccessFailed,
} || Allocator.Error;

fn listGenerations(allocator: Allocator, profile_name: []const u8, args: GenerationListArgs) GenerationListError!void {
    const profile_dirname = if (mem.eql(u8, profile_name, "system"))
        "/nix/var/nix/profiles"
    else
        "/nix/var/nix/profiles/system-profiles";

    var generations: ArrayList(GenerationMetadata) = ArrayList(GenerationMetadata).init(allocator);
    defer generations.deinit();
    defer {
        for (generations.items) |*generation| {
            defer generation.deinit();
        }
    }

    var generations_dir = fs.openDirAbsolute(profile_dirname, .{ .iterate = true }) catch |err| {
        log.err("unexpected error encountered opening {s}: {s}", .{ profile_dirname, @errorName(err) });
        return GenerationListError.ResourceAccessFailed;
    };

    var path_buf: [posix.PATH_MAX]u8 = undefined;

    const current_generation_dirname = try fs.path.join(allocator, &.{ profile_dirname, profile_name });
    defer allocator.free(current_generation_dirname);

    // Check if generation is the current generation
    const current_system_name = posix.readlink(current_generation_dirname, &path_buf) catch |err| {
        log.err("unable to readlink {s}: {s}", .{ current_generation_dirname, @errorName(err) });
        return GenerationListError.ResourceAccessFailed;
    };

    var iter = generations_dir.iterate();
    while (iter.next() catch |err| {
        log.err("unexpected error while reading profile directory: {s}", .{@errorName(err)});
        return GenerationListError.ResourceAccessFailed;
    }) |entry| {
        const prefix = try fmt.allocPrint(allocator, "{s}-", .{profile_name});
        defer allocator.free(prefix);

        // I hate no regexes in this language. Big sad.
        // This works around the fact that multiple profile
        // names can share the same prefix.
        if (mem.startsWith(u8, entry.name, prefix) and
            mem.endsWith(u8, entry.name, "-link") and
            prefix.len + 5 < entry.name.len)
        {
            const gen_number_slice = entry.name[(prefix.len)..mem.indexOf(u8, entry.name, "-link").?];

            // If the number parsed is not an integer, it contains a dash
            // and is from another profile, so it is skipped.
            // Also, might as well pass this to the generation info
            // function and avoid extra work re-parsing the number.
            const generation_number = std.fmt.parseInt(usize, gen_number_slice, 10) catch continue;

            const generation_dirname = try fs.path.join(allocator, &.{ profile_dirname, entry.name });
            defer allocator.free(generation_dirname);

            var generation_dir = fs.openDirAbsolute(generation_dirname, .{}) catch |err| {
                log.err("unexpected error encountered opening {s}: {s}", .{ generation_dirname, @errorName(err) });
                return GenerationListError.ResourceAccessFailed;
            };
            defer generation_dir.close();

            var generation = try GenerationMetadata.getGenerationInfo(allocator, generation_dir, generation_number);
            errdefer generation.deinit();

            if (mem.eql(u8, current_system_name, entry.name)) {
                generation.current = true;
            }

            try generations.append(generation);
        }
    }

    // I like sorted output.
    mem.sort(GenerationMetadata, generations.items, {}, GenerationMetadata.lessThan);

    const stdout = io.getStdOut().writer();

    if (args.json) {
        std.json.stringify(generations.items, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
        print(stdout, "\n", .{});
        return;
    }

    for (generations.items, 0..) |gen, i| {
        gen.prettyPrint(.{ .color = posix.getenv("NO_COLOR") == null }, stdout) catch unreachable;
        if (i != generations.items.len - 1) {
            print(stdout, "\n", .{});
        }
    }
}

pub fn generationListMain(allocator: Allocator, profile: ?[]const u8, args: GenerationListArgs) u8 {
    const profile_name = profile orelse "system";

    listGenerations(allocator, profile_name, args) catch |err| {
        switch (err) {
            GenerationListError.ResourceAccessFailed => return 4,
            GenerationListError.PermissionDenied => return 13,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };

    return 0;
}
