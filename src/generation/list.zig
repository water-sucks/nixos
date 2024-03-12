const std = @import("std");

const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const argIs = argparse.argIs;
const argError = argparse.argError;
const ArgParseError = argparse.ArgParseError;

const GenerationInfo = @import("../generation.zig").GenerationInfo;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
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

    pub fn parseArgs(argv: *ArgIterator) !GenerationListArgs {
        var result = GenerationListArgs{};

        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--json", "-j")) {
                result.json = true;
            } else {
                if (argparse.isFlag(arg)) {
                    argError("unrecognised flag '{s}'", .{arg});
                } else {
                    argError("argument '{s}' is not valid in this context", .{arg});
                }
                return ArgParseError.InvalidArgument;
            }

            next_arg = argv.next();
        }

        return result;
    }
};

const GenerationListError = error{
    PermissionDenied,
    ResourceAccessFailed,
} || Allocator.Error;

// Detailed Metadata about a NixOS generation
pub const Generation = struct {
    // Generation number
    generation: usize,
    // Date of generation creation
    date: []const u8,
    // If this generation is the currently activated one
    current: bool = false,
    // NixOS version of generation
    nixos_version: []const u8,
    // Version of active kernel in generation
    kernel_version: []const u8,
    // Configuration revision (if it exists)
    configuration_revision: []const u8,
    // Generation specialisation (if not base config)
    specialisations: [][]const u8,

    const Self = @This();

    // Caller owns returned memory, free with .deinit(allocator).
    pub fn getGenerationInfo(allocator: Allocator, path: fs.Dir, gen_number: usize) !Self {
        // Read NixOS version from nixos-version file for configuration rev
        var nixos_version_contents = blk: {
            const file = path.openFile("nixos-version.json", .{}) catch break :blk null;
            defer file.close();

            const contents = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch break :blk null;
            defer allocator.free(contents);

            break :blk std.json.parseFromSlice(GenerationInfo, allocator, contents, .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            }) catch null;
        };
        defer if (nixos_version_contents) |json| json.deinit();
        const nixos_version_info: GenerationInfo = if (nixos_version_contents) |contents| contents.value else GenerationInfo{};

        var nixos_version: ?[]const u8 = blk: {
            if (path.openFile("nixos-version", .{})) |file| {
                defer file.close();
                break :blk file.readToEndAlloc(allocator, 1000) catch |err| {
                    log.warn("unable to read NixOS version file for generation {d}: {s}", .{ gen_number, @errorName(err) });
                    break :blk null;
                };
            } else |err| {
                log.warn("unable to open NixOS version file for generation {d}: {s}", .{ gen_number, @errorName(err) });
            }
            break :blk null;
        };

        if (nixos_version == null) {
            nixos_version = try fmt.allocPrint(allocator, "unknown", .{});
        }

        errdefer if (nixos_version != null) allocator.free(nixos_version.?);

        // Get time of creation for generation
        // (uses ctime, so may be inaccurate if tampered with)
        const gen_stat = path.stat() catch |err| {
            switch (err) {
                error.AccessDenied => {
                    log.err("unable to stat: permission denied", .{});
                    return GenerationListError.PermissionDenied;
                },
                else => log.err("unable to stat: {s}", .{@errorName(err)}),
            }

            return GenerationListError.ResourceAccessFailed;
        };

        const date = try todateiso8601(allocator, gen_stat.ctime);

        // Get kernel version of generation from lib/modules/${version} directory
        const kernel_modules_dir = path.realpathAlloc(allocator, "kernel-modules/lib/modules") catch |err| {
            log.err("unable to determine realpath of kernel modules dir: {s}", .{@errorName(err)});
            return GenerationListError.ResourceAccessFailed;
        };
        defer allocator.free(kernel_modules_dir);

        // This version directory should exist, but on the off chance it doesn't,
        // don't take chances.
        var kernel_dir = std.fs.openIterableDirAbsolute(kernel_modules_dir, .{}) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    log.err("unable to open {s}: permission denied", .{kernel_modules_dir});
                    return GenerationListError.PermissionDenied;
                },
                error.DeviceBusy => log.err("unable to open {s}: device busy", .{kernel_modules_dir}),
                error.FileNotFound => log.err("unable to {s}: no such file or directory", .{kernel_modules_dir}),
                error.NotDir => log.err("{s} is not a directory", .{kernel_modules_dir}),

                error.SymLinkLoop => log.err("encountered symlink loop while opening {s}", .{kernel_modules_dir}),
                else => log.err("unexpected error encountered opening {s}: {s}", .{ kernel_modules_dir, @errorName(err) }),
            }
            return GenerationListError.ResourceAccessFailed;
        };
        var iter = kernel_dir.iterate();
        const version_dir = iter.next() catch return GenerationListError.ResourceAccessFailed;

        var kernel_version: []const u8 = undefined;

        if (version_dir != null) {
            kernel_version = try allocator.dupe(u8, std.fs.path.basename(version_dir.?.name));
        } else {
            kernel_version = try fmt.allocPrint(allocator, "unknown", .{});
        }

        var specializations_list = ArrayList([]const u8).init(allocator);
        errdefer specializations_list.deinit();
        errdefer {
            for (specializations_list.items) |s| {
                allocator.free(s);
            }
        }

        // Find specialisations in NixOS generation
        if (path.openIterableDir("specialisation", .{})) |*dir| {
            // HACK: why is @constCast needed to close the directory?
            defer @constCast(dir).close();
            iter = dir.iterate();
            while (iter.next() catch return GenerationListError.ResourceAccessFailed) |entry| {
                try specializations_list.append(try allocator.dupe(u8, entry.name));
            }
        } else |err| {
            log.warn("unable to find specialisations: {s}", .{@errorName(err)});
        }

        const configuration_revision = if (nixos_version_info.configurationRevision) |rev|
            try allocator.dupe(u8, rev)
        else
            try fmt.allocPrint(allocator, "unknown", .{});

        const specializations = try specializations_list.toOwnedSlice();
        mem.sort([]const u8, specializations, {}, stringLessThan);

        return Generation{
            .generation = gen_number,
            .date = date,
            .nixos_version = nixos_version.?,
            .kernel_version = kernel_version,
            .current = false, // This is determined where we have access to the generation directory string.
            .configuration_revision = configuration_revision,
            .specialisations = specializations,
        };
    }

    pub fn lessThan(_: void, lhs: Generation, rhs: Generation) bool {
        return lhs.generation < rhs.generation;
    }

    // Explicitly pass the allocator here in order to avoid
    // JSON serialization problems.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.nixos_version);
        allocator.free(self.kernel_version);
        allocator.free(self.date);

        for (self.specialisations) |s| {
            allocator.free(s);
        }
        allocator.free(self.specialisations);
    }
};

fn todateiso8601(allocator: Allocator, timestamp: i128) ![]const u8 {
    // Remove nanoseconds
    var lean: u128 = @intCast(@divFloor(timestamp, 1_000_000_000));

    const second = @mod(lean, 60);
    lean = @divFloor(lean, 60);
    const minute = @mod(lean, 60);
    lean = @divFloor(lean, 60);
    const hour = @mod(lean, 24);
    lean = @divFloor(lean, 24);

    var daysSinceEpoch: u128 = lean;
    var year: u128 = 1970;

    while (true) {
        var daysInYear: u16 = 365;
        if (@mod(year, 4) == 0) {
            if (@mod(year, 100) != 0 or @mod(year, 400) == 0) {
                daysInYear = 366;
            }
        }

        if (daysSinceEpoch < daysInYear) {
            break;
        }

        daysSinceEpoch -= daysInYear;
        year += 1;
    }

    var month: u8 = 1;
    while (month <= 12) : (month += 1) {
        var daysInMonth: u8 = 0;
        switch (month) {
            4, 6, 9, 11 => daysInMonth = 30,
            2 => {
                daysInMonth = 28;
                if (@mod(year, 4) == 0) {
                    if (@mod(year, 100) != 0 or @mod(year, 400) == 0) {
                        daysInMonth = 29;
                    }
                }
            },
            else => daysInMonth = 31,
        }

        if (daysSinceEpoch < daysInMonth) {
            break;
        }

        daysSinceEpoch -= daysInMonth;
    }

    const day = daysSinceEpoch + 1;

    return fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{ year, month, day, hour, minute, second });
}

fn listGenerations(allocator: Allocator, profile_name: []const u8, args: GenerationListArgs) GenerationListError!void {
    var profile_dirname = if (mem.eql(u8, profile_name, "system"))
        "/nix/var/nix/profiles"
    else
        "/nix/var/nix/profiles/system-profiles";

    var generations: ArrayList(Generation) = ArrayList(Generation).init(allocator);
    defer generations.deinit();
    defer {
        for (generations.items) |*generation| {
            defer generation.deinit(allocator);
        }
    }

    var generations_dir = fs.openIterableDirAbsolute(profile_dirname, .{}) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to open {s}: permission denied", .{profile_dirname});
                return GenerationListError.PermissionDenied;
            },
            error.DeviceBusy => log.err("unable to open {s}: device busy", .{profile_dirname}),
            error.FileNotFound => log.err("unable to {s}: no such file or directory", .{profile_dirname}),
            error.NotDir => log.err("{s} is not a directory", .{profile_dirname}),

            error.SymLinkLoop => log.err("encountered symlink loop while opening {s}", .{profile_dirname}),
            else => log.err("unexpected error encountered opening {s}: {s}", .{ profile_dirname, @errorName(err) }),
        }
        return GenerationListError.ResourceAccessFailed;
    };

    var path_buf: [os.PATH_MAX]u8 = undefined;

    const current_generation_dirname = try fs.path.join(allocator, &.{ profile_dirname, profile_name });
    defer allocator.free(current_generation_dirname);

    // Check if generation is the current generation
    const link_name = os.readlink(current_generation_dirname, &path_buf) catch |err| {
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
                switch (err) {
                    error.AccessDenied => {
                        log.err("unable to open {s}: permission denied", .{generation_dirname});
                        return GenerationListError.PermissionDenied;
                    },
                    error.DeviceBusy => log.err("unable to open {s}: device busy", .{generation_dirname}),
                    error.FileNotFound => log.err("unable to {s}: no such file or directory", .{generation_dirname}),
                    error.NotDir => log.err("{s} is not a directory", .{generation_dirname}),

                    error.SymLinkLoop => log.err("encountered symlink loop while opening {s}", .{generation_dirname}),
                    else => log.err("unexpected error encountered opening {s}: {s}", .{ generation_dirname, @errorName(err) }),
                }
                return GenerationListError.ResourceAccessFailed;
            };
            defer generation_dir.close();

            var generation = try Generation.getGenerationInfo(allocator, generation_dir, generation_number);
            errdefer generation.deinit(allocator);

            if (mem.eql(u8, link_name, entry.name)) {
                generation.current = true;
            }

            try generations.append(generation);
        }
    }

    // I like sorted output.
    mem.sort(Generation, generations.items, {}, Generation.lessThan);

    const stdout = io.getStdOut().writer();

    if (args.json) {
        std.json.stringify(generations.items, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
        print(stdout, "\n", .{});
        return;
    }

    const headers: []const []const u8 = &.{ "Generation", "Build Date", "NixOS Version", "Kernel Version", "Configuration Revision", "Specialisations" };

    var max_row_len = comptime blk: {
        var tmp: []const usize = &[_]usize{};
        inline for (headers) |header| {
            tmp = tmp ++ [_]usize{header.len};
        }
        var new: [tmp.len]usize = undefined;
        std.mem.copy(usize, &new, tmp);
        break :blk new;
    };

    var i: usize = 0;

    var generation_numbers = try allocator.alloc([]const u8, generations.items.len);
    defer {
        var j: usize = 0;
        while (j < i) : (j += 1) {
            allocator.free(generation_numbers[j]);
        }
        allocator.free(generation_numbers);
    }
    var specialization_lists = try allocator.alloc([]const u8, generations.items.len);
    defer {
        var j: usize = 0;
        while (j < i) : (j += 1) {
            allocator.free(specialization_lists[j]);
        }
        allocator.free(specialization_lists);
    }

    for (generations.items, generation_numbers, specialization_lists) |gen, *num, *spec| {
        num.* = try fmt.allocPrint(allocator, "{d}{s}", .{ gen.generation, if (gen.current) "*" else "" });
        spec.* = try concatStringsSep(allocator, gen.specialisations, ",");
        i += 1;

        max_row_len[0] = @max(max_row_len[0], num.*.len); // Generation
        max_row_len[1] = @max(max_row_len[1], gen.date.len); // Date
        max_row_len[2] = @max(max_row_len[2], gen.nixos_version.len); // NixOS Version
        max_row_len[3] = @max(max_row_len[3], gen.kernel_version.len); // Kernel Version
        max_row_len[4] = @max(max_row_len[4], gen.configuration_revision.len); // Configuration Revision
        max_row_len[5] = @max(max_row_len[5], spec.*.len); // Specialisations
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

    for (generations.items, generation_numbers, specialization_lists, 0..) |gen, num, spec, idx| {
        const row = [_][]const u8{ num, gen.date, gen.nixos_version, gen.kernel_version, gen.configuration_revision, spec };
        for (row, 0..) |col, j| {
            print(stdout, "{s}", .{col});
            var k: usize = 4 + max_row_len[j] - col.len;
            while (k > 0) {
                print(stdout, " ", .{});
                k -= 1;
            }
        }
        if (idx < generations.items.len - 1) print(stdout, "\n", .{});
    }
    print(stdout, "\n", .{});
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
