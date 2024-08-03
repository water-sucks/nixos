const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;

const log = @import("../log.zig");

const zeit = @import("zeit");

const utils = @import("../utils.zig");
const TimeSpan = utils.time.TimeSpan;

pub const GenerationDeleteCommand = struct {
    all: bool = false,
    from: ?usize = null,
    to: ?usize = null,
    older_than: ?TimeSpan = null,
    min: ?usize = null,
    keep: ArrayList(usize),
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
        \\
        \\Values:
        \\    <GEN>       Generation number
        \\    <PERIOD>    systemd.time span (i.e. "30d 2h 1m")
        \\
        \\These flags and arguments can be combined ad-hoc, except for --all.
        \\
    ;
    // TODO: add manpage examples

    fn parseGenNumber(candidate: []const u8) !usize {
        return fmt.parseInt(usize, candidate, 10) catch {
            argError("'{s}' is not a valid generation number", .{candidate});
            return ArgParseError.InvalidArgument;
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
            } else if (argIs(arg, "--older-than", "-o")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.older_than = TimeSpan.fromSlice(next) catch |err| {
                    argError("'{s}' is not formatted correctly: {s}", .{ next, @errorName(err) });
                    return ArgParseError.InvalidArgument;
                };
            } else if (argIs(arg, "--to", "-t")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.to = try parseGenNumber(next);
            } else {
                if (argparse.isFlag(arg)) {
                    return arg;
                }

                try parsed.remove.append(try parseGenNumber(arg));
            }

            next_arg = argv.next();
        }

        return null;
    }

    pub fn init(allocator: Allocator) Self {
        return GenerationDeleteCommand{
            .keep = ArrayList(usize).init(allocator),
            .remove = ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.keep.deinit();
        self.remove.deinit();
    }
};

pub fn generationDeleteMain(allocator: Allocator, args: GenerationDeleteCommand, profile: ?[]const u8) u8 {
    _ = allocator;
    _ = profile;

    log.info("remove", .{});
    for (args.remove.items) |gen| {
        log.print("{d} ", .{gen});
    }
    log.print("\n", .{});

    log.info("keep", .{});
    for (args.keep.items) |gen| {
        log.print("{d} ", .{gen});
    }
    log.print("\n", .{});

    if (args.older_than) |time| {
        const now = zeit.instant(.{ .source = .now }) catch unreachable;
        const before_instant = zeit.instant(.{ .source = .{ .unix_nano = (now.timestamp - time.toEpochTime()) } }) catch unreachable;

        const t = before_instant.time();
        log.info("older than: {s} {d}, {d} {d}:{d}:{d}", .{ t.month.name(), t.day, t.year, t.hour, t.minute, t.second });
    }
    log.info("from: {?d}", .{args.from});
    log.info("to: {?d}", .{args.to});
    log.info("min: {?d}", .{args.min});

    return 0;
}
