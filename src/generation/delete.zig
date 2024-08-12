const std = @import("std");
const opts = @import("options");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const linux = std.os.linux;
const posix = std.posix;
const sort = std.sort;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;

const Constants = @import("../constants.zig");

const log = @import("../log.zig");

const zeit = @import("zeit");

const utils = @import("../utils.zig");
const GenerationMetadata = utils.generation.GenerationMetadata;
const TimeSpan = utils.time.TimeSpan;
const runCmd = utils.runCmd;

pub const GenerationDeleteCommand = struct {
    all: bool = false,
    from: ?usize = null,
    keep: ArrayList(usize),
    min: ?usize = null,
    older_than: ?TimeSpan = null,
    to: ?usize = null,
    yes: bool = false,
    remove: ArrayList(usize), // Positional args, not using an option

    const Self = @This();

    const usage =
        \\Delete NixOS generations from this system.
        \\
        \\Usage:
        \\    nixos generation delete [GEN...] [options]
        \\
        \\Arguments:
        \\    [GEN...]    Generation numbers to delete
        \\
        \\Options:
        \\    -a, --all                    Delete all generations except the current one
        \\    -f, --from <GEN>             Delete all generations after <GEN>, inclusive
        \\    -h, --help                   Show this help menu
        \\    -k, --keep <GEN>             Always keep this generation; can be used multiple times
        \\    -m, --min <NUM>              Keep a minimum of <NUM> generations
        \\    -o, --older-than <PERIOD>    Delete all generations older than <PERIOD>
        \\    -t, --to <GEN>               Delete this generation
        \\    -y, --yes                    Automatically confirm deletion of generations
        \\
        \\Values:
        \\    <GEN>       Generation number
        \\    <PERIOD>    systemd.time span (i.e. "30d 2h 1m")
        \\
        \\These options and arguments can be combined ad-hoc.
        \\
    ;
    // TODO: add manpage examples

    fn parseGenNumber(candidate: []const u8) !usize {
        return fmt.parseInt(usize, candidate, 10) catch {
            argError("'{s}' is not a valid generation number", .{candidate});
            return ArgParseError.InvalidArgument;
        };
    }

    pub fn init(allocator: Allocator) Self {
        return GenerationDeleteCommand{
            .keep = ArrayList(usize).init(allocator),
            .remove = ArrayList(usize).init(allocator),
        };
    }

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationDeleteCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--all", "-a")) {
                parsed.all = true;
            } else if (argIs(arg, "--from", "-f")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.from = try parseGenNumber(next);
            } else if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--keep", "-k")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                try parsed.keep.append(try parseGenNumber(next));
            } else if (argIs(arg, "--min", "-m")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.min = fmt.parseInt(usize, next, 10) catch {
                    argError("'{s}' is not a number", .{next});
                    return ArgParseError.InvalidArgument;
                };
                if (parsed.min == 0) {
                    argError("--min must be at least 1", .{});
                    return ArgParseError.InvalidArgument;
                }
            } else if (argIs(arg, "--older-than", "-o")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.older_than = TimeSpan.fromSlice(next) catch |err| {
                    argError("'{s}' is not formatted correctly: {s}", .{ next, @errorName(err) });
                    return ArgParseError.InvalidArgument;
                };
            } else if (argIs(arg, "--to", "-t")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.to = try parseGenNumber(next);
            } else if (argIs(arg, "--yes", "-y")) {
                parsed.yes = true;
            } else {
                if (argparse.isFlag(arg)) {
                    return arg;
                }

                try parsed.remove.append(try parseGenNumber(arg));
            }

            next_arg = argv.next();
        }

        for (parsed.remove.items) |remove| {
            for (parsed.keep.items) |keep| {
                if (remove == keep) {
                    argError("generation {d} cannot be both removed and kept", .{remove});
                    return ArgParseError.ConflictingOptions;
                }
            }
        }

        if (parsed.all) {
            if (parsed.from != null) {
                log.warn("--all was specified, ignoring --from", .{});
            }
            if (parsed.older_than != null) {
                log.warn("--all was specified, ignoring --older-than", .{});
            }
            if (parsed.to != null) {
                log.warn("--all was specified, ignoring --to", .{});
            }
            if (parsed.remove.items.len > 0) {
                log.warn("--all was specified, ignoring positional arguments", .{});
            }
        }

        if (!parsed.all and
            parsed.from == null and
            parsed.keep.items.len == 0 and
            parsed.min == null and
            parsed.older_than == null and
            parsed.to == null and
            parsed.remove.items.len == 0)
        {
            argError("no generations or deletion parameters were given", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        return null;
    }

    pub fn deinit(self: Self) void {
        self.keep.deinit();
        self.remove.deinit();
    }
};

pub const GenerationDeleteError = error{
    CurrentGenerationRequested,
    ResourceAccessFailed,
    InvalidParameter,
    PermissionDenied,
    CommandFailed,
} || Allocator.Error;

pub fn printDeleteSummary(allocator: Allocator, generations: []GenerationMetadata) !void {
    log.print("The following generations will be deleted:\n\n", .{});

    const headers: []const []const u8 = &.{ "#", "Description", "Creation Date" };

    var max_row_len = comptime blk: {
        var tmp: []const usize = &[_]usize{};
        for (headers) |header| {
            tmp = tmp ++ [_]usize{header.len};
        }
        var new: [tmp.len]usize = undefined;
        std.mem.copyForwards(usize, &new, tmp);
        break :blk new;
    };

    var num_list = try ArrayList([]const u8).initCapacity(allocator, generations.len);
    defer {
        for (num_list.items) |num| allocator.free(num);
        num_list.deinit();
    }

    var date_list = try ArrayList([]const u8).initCapacity(allocator, generations.len);
    defer {
        for (date_list.items) |date| allocator.free(date);
        date_list.deinit();
    }

    for (generations) |gen| {
        const t = gen.date.?;

        const num = try fmt.allocPrint(allocator, "{d}", .{gen.generation.?});
        num_list.appendAssumeCapacity(num);
        const date = try fmt.allocPrint(allocator, "{d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2}", .{ t.year, t.month.name(), t.day, t.hour, t.minute, t.second });
        date_list.appendAssumeCapacity(date);

        max_row_len[0] = @max(max_row_len[0], num.len);
        max_row_len[1] = @max(max_row_len[1], (gen.description orelse "").len);
        max_row_len[2] = @max(max_row_len[2], date.len);
    }

    for (headers, 0..) |header, j| {
        var k: usize = 4 + max_row_len[j];

        const start_idx = (max_row_len[j] / 2) - (header.len / 2);

        var i: usize = 0;
        while (i < start_idx) : (i += 1) {
            log.print(" ", .{});
            k -= 1;
        }

        log.print("{s}", .{header});
        k -= header.len;

        while (k > 0) : (k -= 1) {
            log.print(" ", .{});
        }
    }
    log.print("\n", .{});
    for (max_row_len, 0..) |len, col| {
        var lim = len + 4;
        if (col == max_row_len.len - 1) {
            lim -= 4;
        }
        var i: usize = 0;
        while (i < lim) : (i += 1) {
            log.print("-", .{});
        }
    }
    log.print("\n", .{});

    for (generations, num_list.items, date_list.items, 0..) |gen, num, date, idx| {
        const row = [_][]const u8{ num, gen.description orelse "", date };
        for (row, 0..) |col, j| {
            log.print("{s}", .{col});
            var k: usize = max_row_len[j] - col.len;
            while (k > 0) {
                log.print(" ", .{});
                k -= 1;
            }
            if (j < row.len - 1) {
                log.print(" :: ", .{});
            }
        }
        if (idx < generations.len - 1) log.print("\n", .{});
    }
    log.print("\n\n", .{});
}

var exit_status: u8 = 0;

pub fn deleteGenerations(allocator: Allocator, generations: []GenerationMetadata, profile_dirname: []const u8) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer {
        for (argv.items) |s| allocator.free(s);
        argv.deinit();
    }

    try argv.append(try allocator.dupe(u8, "nix-env"));
    try argv.append(try allocator.dupe(u8, "-p"));
    try argv.append(try allocator.dupe(u8, profile_dirname));
    try argv.append(try allocator.dupe(u8, "--delete-generations"));

    for (generations) |gen| {
        const num = try fmt.allocPrint(allocator, "{d}", .{gen.generation.?});
        try argv.append(num);
    }

    log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .stdout_type = .Ignore,
    }) catch return GenerationDeleteError.CommandFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationDeleteError.CommandFailed;
    }
}

fn regenerateBootMenu(allocator: Allocator) !void {
    const argv = &.{ Constants.current_system ++ "/bin/switch-to-configuration", "boot" };

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stdout_type = .Inherit,
    }) catch return GenerationDeleteError.CommandFailed;
    if (result.status != 0) {
        exit_status = result.status;
        return GenerationDeleteError.CommandFailed;
    }
}

pub fn generationDelete(allocator: Allocator, args: GenerationDeleteCommand, profile: ?[]const u8) GenerationDeleteError!void {
    if (linux.geteuid() != 0) {
        utils.execAsRoot(allocator) catch |err| {
            log.err("unable to re-exec this command as root: {s}", .{@errorName(err)});
            return GenerationDeleteError.PermissionDenied;
        };
    }

    const profile_name = profile orelse "system";
    const profile_dirname = if (mem.eql(u8, profile_name, "system"))
        "/nix/var/nix/profiles"
    else
        "/nix/var/nix/profiles/system-profiles";

    var generations_dir = fs.cwd().openDir(profile_dirname, .{ .iterate = true }) catch |err| {
        log.err("unable to open profile dir {s}: {s}", .{ profile_dirname, @errorName(err) });
        return GenerationDeleteError.ResourceAccessFailed;
    };
    defer generations_dir.close();

    const all_gens_info = utils.generation.gatherGenerationsFromProfile(allocator, profile_name) catch return GenerationDeleteError.ResourceAccessFailed;
    defer {
        for (all_gens_info) |*gen| gen.deinit();
        allocator.free(all_gens_info);
    }

    var all_gen_numbers = try ArrayList(usize).initCapacity(allocator, all_gens_info.len);
    defer all_gen_numbers.deinit();

    for (all_gens_info) |gen| {
        all_gen_numbers.appendAssumeCapacity(gen.generation.?);
    }

    if (all_gen_numbers.items.len < 2) {
        if (all_gen_numbers.items.len == 0) {
            log.err("no generations exist for profile {s}", .{profile_name});
        } else {
            log.err("only one generations exists for profile {s}; deletion is impossible", .{profile_name});
        }
        return;
    }

    // Make sure there are enough generations that exist.
    if (args.min) |min| {
        if (min >= all_gen_numbers.items.len) {
            log.err("there are {d} generations, but the expected minimum is {d}", .{ all_gen_numbers.items.len, min });
            log.info("keeping all generations", .{});
            return;
        }
    }

    var current_gen_number: usize = undefined;
    for (all_gens_info) |gen| {
        if (gen.current) {
            current_gen_number = gen.generation.?;
            if (mem.indexOf(usize, args.remove.items, &.{current_gen_number}) != null) {
                log.err("cannot remove generation {d}, this is the current generation!", .{current_gen_number});
                return GenerationDeleteError.InvalidParameter;
            }
        }
    }

    var gens_to_remove_set = std.AutoHashMap(usize, void).init(allocator);
    defer gens_to_remove_set.deinit();
    for (args.remove.items) |remove| {
        try gens_to_remove_set.put(remove, {});
    }

    var gens_to_keep_set = std.AutoHashMap(usize, void).init(allocator);
    defer gens_to_keep_set.deinit();
    for (args.keep.items) |keep| {
        try gens_to_keep_set.put(keep, {});
    }
    try gens_to_keep_set.put(current_gen_number, {});

    if (args.all) {
        for (all_gen_numbers.items) |gen| {
            try gens_to_remove_set.put(gen, {});
        }
    } else {
        // Add ranges
        if (args.from != null or args.to != null) {
            const upper_bound = args.to orelse all_gen_numbers.items[all_gen_numbers.items.len - 1];
            const lower_bound = args.from orelse all_gen_numbers.items[0];

            if (lower_bound > upper_bound) {
                log.err("lower bound '{d}' must be less than upper bound '{d}'", .{ lower_bound, upper_bound });
                return GenerationDeleteError.InvalidParameter;
            }

            // Make sure that ranges are within generation bounds
            if (upper_bound > all_gen_numbers.items[all_gen_numbers.items.len - 1] or upper_bound < all_gen_numbers.items[0]) {
                log.err("upper bound '{d}' is not within the range of available generations", .{upper_bound});
                return GenerationDeleteError.InvalidParameter;
            }
            if (lower_bound > all_gen_numbers.items[all_gen_numbers.items.len - 1] or lower_bound < all_gen_numbers.items[0]) {
                log.err("lower bound '{d}' is not within the range of available generations", .{lower_bound});
                return GenerationDeleteError.InvalidParameter;
            }

            for (all_gen_numbers.items) |gen| {
                if (gen >= lower_bound and gen <= upper_bound) {
                    try gens_to_remove_set.put(gen, {});
                }
            }
        }

        // Calulate generations before timestamp
        if (args.older_than) |older_than| {
            const now = zeit.instant(.{ .source = .now }) catch unreachable;
            const before_instant = zeit.instant(.{ .source = .{ .unix_nano = (now.timestamp - older_than.toEpochTime()) } }) catch unreachable;

            for (all_gen_numbers.items) |gen| {
                if (gens_to_remove_set.contains(gen)) {
                    continue;
                }
                const gen_name = try fmt.allocPrint(allocator, "system-{d}-link", .{gen});
                defer allocator.free(gen_name);

                const stat = generations_dir.statFile(gen_name) catch |err| {
                    log.err("unable to stat {s}: {s}; skipping date check", .{ gen_name, @errorName(err) });
                    continue;
                };

                if (stat.ctime < before_instant.timestamp) {
                    try gens_to_remove_set.put(gen, {});
                }
            }
        }
    }

    // Remove all members of gens_to_keep from gens_to_remove
    var keep_iter = gens_to_keep_set.keyIterator();
    while (keep_iter.next()) |keep| {
        _ = gens_to_remove_set.remove(keep.*);
    }

    // Ensure that the minimum number of generations exists.
    // Generations with higher numbers are prioritized.
    var remaining_number_of_generations = all_gen_numbers.items.len - gens_to_remove_set.count();

    if (args.min != null and remaining_number_of_generations < args.min.?) {
        const min_required = args.min.?;

        var j: usize = 0;
        while (j < all_gen_numbers.items.len - 1) : (j += 1) {
            const i = all_gen_numbers.items.len - 1 - j;
            const gen = all_gen_numbers.items[i];

            _ = gens_to_remove_set.remove(gen);

            remaining_number_of_generations = all_gen_numbers.items.len - gens_to_remove_set.count();
            if (remaining_number_of_generations == min_required) {
                break;
            }
        }
    }

    if (gens_to_remove_set.count() == 0) {
        log.warn("no generations were resolved for deletion from the given parameters", .{});
        log.info("there is nothing to do; exiting", .{});
        return;
    }

    var gens_to_remove_info = try ArrayList(GenerationMetadata).initCapacity(allocator, gens_to_remove_set.count());
    defer gens_to_remove_info.deinit();

    var remove_iter = gens_to_remove_set.keyIterator();
    while (remove_iter.next()) |gen_number| {
        for (all_gens_info) |gen| {
            if (gen.generation.? == gen_number.*) {
                gens_to_remove_info.appendAssumeCapacity(gen);
                break;
            }
        } else unreachable;
    }
    sort.block(GenerationMetadata, gens_to_remove_info.items, {}, GenerationMetadata.lessThan);

    try printDeleteSummary(allocator, gens_to_remove_info.items);
    log.print("There will be {d} generations left on this machine.\n", .{remaining_number_of_generations});

    if (!args.yes) {
        const confirm = utils.confirmationInput() catch |err| {
            log.err("unable to read stdin for confirmation: {s}", .{@errorName(err)});
            return GenerationDeleteError.ResourceAccessFailed;
        };
        if (!confirm) {
            log.warn("confirmation was not given, not proceeding", .{});
            return;
        }
    }

    log.step("Deleting generations...", .{});

    const full_profile_dirname = try fs.path.join(allocator, &.{ profile_dirname, profile_name });
    defer allocator.free(full_profile_dirname);

    try deleteGenerations(allocator, gens_to_remove_info.items, full_profile_dirname);

    log.step("Regenerating boot menu entries...", .{});

    try regenerateBootMenu(allocator);

    log.print("Success!\n", .{});
    log.info("to free up disk space from these generations, run `{s}`", .{if (opts.flake) "nix store gc" else "nix-collect-garbage"});
    if (!opts.flake) {
        log.info("if using `nix-collect-garbage`, the `-d` option frees up generations, which you may not want", .{});
    }
}

pub fn generationDeleteMain(allocator: Allocator, args: GenerationDeleteCommand, profile: ?[]const u8) u8 {
    generationDelete(allocator, args, profile) catch |err| {
        return switch (err) {
            GenerationDeleteError.ResourceAccessFailed => 3,
            GenerationDeleteError.InvalidParameter => 2,
            GenerationDeleteError.PermissionDenied => 13,
            GenerationDeleteError.CommandFailed => if (exit_status != 0) exit_status else 1,
            else => 1,
        };
    };

    return 0;
}
