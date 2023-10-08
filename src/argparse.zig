//! This module provides command line argument parsing facilities.
//! It operates on an `std.process.ArgIterator` and allows for parsing
//! arguments in a vaguely similar way to shell scripts.

const std = @import("std");
const mem = std.mem;
const process = std.process;
const ArgIterator = std.process.ArgIterator;

const log = @import("log.zig");

pub const ArgParseError = error{
    HelpInvoked,
    InvalidArgument,
    InvalidSubcommand,
    MissingRequiredArgument,
    ConflictingOptions,
};

/// Check if an argument is equal to a short or long version.
pub fn argIs(arg: []const u8, full: []const u8, short: ?[]const u8) bool {
    if (mem.eql(u8, arg, full)) {
        return true;
    }

    if (short) |s| {
        return mem.eql(u8, arg, s);
    }

    return false;
}

pub fn argError(comptime fmt: []const u8, args: anytype) void {
    log.err(fmt, args);
    log.print("\nFor more information, add --help.\n", .{});
}

/// Check if an argument name is equal to a list of candidates.
pub fn argIn(arg: []const u8, candidates: []const []const u8) bool {
    for (candidates) |candidate| {
        if (mem.eql(u8, arg, candidate)) {
            return true;
        }
    }

    return false;
}

/// Check if an argument is a flag or not.
pub fn isFlag(arg: []const u8) bool {
    if (arg.len > 2) {
        return mem.eql(u8, arg[0..2], "--");
    } else if (arg.len == 2) {
        // Maybe need more robust handling?
        return arg[0] == '-';
    }

    return false;
}

/// Get additional arguments for a flag or error out if
/// they are not adequately provided.
pub fn getNextArgs(args: *ArgIterator, name: []const u8, comptime amount: usize) ![]const []const u8 {
    var collected_args: [amount][]const u8 = undefined;

    var i: usize = 0;
    while (i < amount) : (i += 1) {
        const arg = args.next() orelse {
            return missingRequiredArgMessage(name, amount, i);
        };

        collected_args[i] = arg;
    }

    return &collected_args;
}

/// Log a nicely formatted message informing about an
/// inadequate number of arguments.
inline fn missingRequiredArgMessage(name: []const u8, required: usize, provided: usize) ArgParseError {
    if (provided == 0) {
        argError("{s} requires {d} argument{s}", .{ name, required, if (required > 1) "s" else "" });
    } else {
        argError("{s} requires {d} arguments, but {d} {s} given", .{ name, required, provided, if (provided > 1) "were" else "was" });
    }

    return ArgParseError.MissingRequiredArgument;
}

/// Error out if multiple fields are set to true or have a value; this
/// is used for conflicting arguments like --flake and --no-flake.
pub fn conflict(args: anytype, conflicts: anytype) ArgParseError!void {
    const TypeToCheck = @TypeOf(conflicts);
    if (@typeInfo(TypeToCheck) != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(TypeToCheck));
    }

    if (conflicts.len == 0) {
        return;
    }

    inline for (conflicts) |kv| {
        const key = kv[0];
        const fields = kv[1];
        if (isSet(@field(args, key))) {
            inline for (fields) |field| {
                if (isSet(@field(args, field))) {
                    argError("{s} and {s} flags conflict", .{ key, field });
                    return ArgParseError.ConflictingOptions;
                }
            }
        }
    }
}

/// Check if an argument is set to true or has a non-null
/// string value.
fn isSet(arg: anytype) bool {
    if (@TypeOf(arg) == bool) {
        return arg;
    } else if (@TypeOf(arg) == ?[]const u8) {
        return arg != null;
    } else {
        @compileError("arg to isSet can only be of type ?[]const u8 or bool");
    }
}

/// Error out if one of the required args are not set; this is used
/// for argument dependencies like --specialization, which is only
/// relevant with --activate.
pub fn require(args: anytype, required: anytype) ArgParseError!void {
    const TypeToCheck = @TypeOf(required);
    if (@typeInfo(TypeToCheck) != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(TypeToCheck));
    }

    if (required.len == 0) {
        return;
    }

    inline for (required) |kv| {
        const key = kv[0];
        const fields = kv[1];
        if (isSet(@field(args, key))) {
            var required_is_set = false;

            inline for (fields) |field| {
                if (isSet(@field(args, field))) {
                    required_is_set = true;
                }
            }

            if (!required_is_set) {
                return missingRequiredFlagMessage(key, fields);
            }
        }
    }
}

/// Log a nicely formatted message informing about a
/// required flag not being set.
inline fn missingRequiredFlagMessage(arg: []const u8, required: anytype) ArgParseError {
    if (required.len == 1) {
        argError("{s} requires {s} to be set", .{ arg, required[0] });
    } else if (required.len == 2) {
        argError("{s} requires either {s} or {s} to be set", .{ arg, required[0], required[1] });
    } else {
        // log.err doesn't work too well for multiple args because it adds a newline
        log.print("error: {s} requires at least one of ", .{arg});
        var i: usize = 0;
        for (required) |r| {
            if (i == required.len - 1) {
                log.print("or {s} ", .{r.name});
            } else {
                log.print("{s}, ", .{r.name});
            }
            i += 1;
        }
        log.prirt("to be set\n", .{});
        log.print("\nFor more information, add --help.\n");
    }

    return ArgParseError.MissingRequiredArgument;
}
