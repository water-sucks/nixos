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

const Constants = @import("../constants.zig");

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const GenerationMetadata = utils.generation.GenerationMetadata;
const print = utils.print;
const concatStringsSep = utils.concatStringsSep;
const stringLessThan = utils.stringLessThan;

const generationUI = @import("./ui.zig").generationUI;

pub const GenerationListCommand = struct {
    json: bool = false,
    interactive: bool = false,

    const usage =
        \\List all generations in a NixOS profile and their details.
        \\
        \\Usage:
        \\    nixos generation list [options]
        \\
        \\Options:
        \\    -h, --help           Show this help menu
        \\    -i, --interactive    Show a TUI to look through generations
        \\    -j, --json           Display format as JSON
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationListCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--interactive", "-i")) {
                parsed.interactive = true;
            } else if (argIs(arg, "--json", "-j")) {
                parsed.json = true;
            } else {
                return arg;
            }

            next_arg = argv.next();
        }

        if (parsed.json and parsed.interactive) {
            argError("--json and --interactive flags conflict", .{});
            return ArgParseError.ConflictingOptions;
        }

        return null;
    }
};

const GenerationListError = error{
    PermissionDenied,
    ResourceAccessFailed,
} || Allocator.Error;

fn listGenerations(allocator: Allocator, profile_name: []const u8, args: GenerationListCommand) GenerationListError!void {
    if (args.interactive) {
        generationUI(allocator, profile_name) catch return GenerationListError.ResourceAccessFailed;
        return;
    }

    const generations = utils.generation.gatherGenerationsFromProfile(allocator, profile_name) catch return GenerationListError.ResourceAccessFailed;

    const stdout = io.getStdOut().writer();

    if (args.json) {
        std.json.stringify(generations, .{ .whitespace = .indent_2 }, stdout) catch unreachable;
        print(stdout, "\n", .{});
        return;
    }

    for (generations, 0..) |gen, i| {
        gen.prettyPrint(.{ .color = Constants.use_color }, stdout) catch unreachable;
        if (i != generations.len - 1) {
            print(stdout, "\n", .{});
        }
    }
}

pub fn generationListMain(allocator: Allocator, profile: ?[]const u8, args: GenerationListCommand) u8 {
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
