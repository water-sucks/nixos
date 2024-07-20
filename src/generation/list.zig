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

fn printGenerationTable(allocator: Allocator, generations: []const GenerationMetadata) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    const stdout = io.getStdOut().writer();

    const headers: []const []const u8 = &.{ "Generation", "Build Date", "NixOS Version", "Kernel Version", "Configuration Revision", "Nixpkgs Revision", "Specialisations" };

    var max_row_len = comptime blk: {
        var tmp: []const usize = &[_]usize{};
        for (headers) |header| {
            tmp = tmp ++ [_]usize{header.len};
        }
        var new: [tmp.len]usize = undefined;
        std.mem.copyForwards(usize, &new, tmp);
        break :blk new;
    };

    var i: usize = 0;

    const generation_numbers = try alloc.alloc([]const u8, generations.len);
    const date_list = try alloc.alloc([]const u8, generations.len);
    const specialization_list = try alloc.alloc([]const u8, generations.len);

    for (generations, generation_numbers, date_list, specialization_list) |gen, *num, *date, *spec| {
        num.* = try fmt.allocPrint(alloc, "{d}{s}", .{ gen.generation.?, if (gen.current) "*" else "" });
        date.* = if (gen.date) |d| try d.toDateISO8601(alloc) else try fmt.allocPrint(alloc, "unknown", .{});
        spec.* = try concatStringsSep(alloc, gen.specialisations orelse &.{}, ",");
        i += 1;

        max_row_len[0] = @max(max_row_len[0], num.*.len); // Generation
        max_row_len[1] = @max(max_row_len[1], date.*.len); // Date
        max_row_len[2] = @max(max_row_len[2], if (gen.nixos_version) |v| v.len else 4);
        max_row_len[3] = @max(max_row_len[3], if (gen.kernel_version) |v| v.len else 4);
        max_row_len[4] = @max(max_row_len[4], if (gen.configuration_revision) |v| v.len else 4);
        max_row_len[5] = @max(max_row_len[4], if (gen.nixpkgs_revision) |v| v.len else 4);
        max_row_len[6] = @max(max_row_len[5], spec.*.len); // Specialisations
    }

    for (headers, 0..) |header, j| {
        print(stdout, "{s}", .{header});
        var k: usize = 4 + max_row_len[j] - header.len;
        while (k > 0) {
            print(stdout, " ", .{});
            k -= 1;
        }
    }
    print(stdout, "\n", .{});

    for (generations, generation_numbers, date_list, specialization_list, 0..) |gen, num, date, spec, idx| {
        const row = [_]?[]const u8{ num, date, gen.nixos_version, gen.kernel_version, gen.configuration_revision, gen.nixpkgs_revision, spec };
        for (row, 0..) |col, j| {
            print(stdout, "{?s}", .{col});
            var k: usize = 4 + max_row_len[j] - if (col) |c| c.len else 4;
            while (k > 0) {
                print(stdout, " ", .{});
                k -= 1;
            }
        }
        if (idx < generations.len - 1) print(stdout, "\n", .{});
    }
    print(stdout, "\n", .{});
}

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

    try printGenerationTable(allocator, generations.items);
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
