const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const argError = argparse.argError;
const argIs = argparse.argIs;
const ArgParseError = argparse.ArgParseError;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

// Reusing specialization logic from `nixos build`, because I'm lazy.
const build = @import("../build.zig");
const findSpecialization = build.findSpecialization;

pub const GenerationRollbackArgs = struct {
    verbose: bool = false,
    dry: bool = false,

    const usage =
        \\Rollback to the previous NixOS generation.
        \\
        \\Usage:
        \\    nixos generation rollback [options]
        \\
        \\Options:
        \\    -d, --dry        Show what would be activated, but do not activate
        \\    -h, --help       Show this help menu
        \\    -v, --verbose    Show verbose logging
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator) !GenerationRollbackArgs {
        var result: GenerationRollbackArgs = GenerationRollbackArgs{};

        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--dry", "-d")) {
                result.dry = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--verbose", "-v")) {
                result.verbose = true;
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

const GenerationRollbackError = error{
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
    UnknownSpecialization,
} || Allocator.Error;

var exit_status: u8 = 0;
var verbose: bool = false;

pub fn setNixEnvProfile(allocator: Allocator, profile_dirname: []const u8) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-env", "--profile", profile_dirname, "--rollback" });

    if (verbose) log.cmd(argv.items);

    var result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return GenerationRollbackError.SetNixProfileFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationRollbackError.SetNixProfileFailed;
    }
}

fn runSwitchToConfiguration(
    allocator: Allocator,
    location: []const u8,
    command: []const u8,
) !void {
    const argv = &.{ location, command };

    if (verbose) log.cmd(argv);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
    }) catch return GenerationRollbackError.SwitchToConfigurationFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationRollbackError.SwitchToConfigurationFailed;
    }
}

fn rollbackGeneration(allocator: Allocator, args: GenerationRollbackArgs, profile_name: []const u8) !void {
    verbose = args.verbose;

    const profile_dirname = if (mem.eql(u8, profile_name, "system"))
        try fmt.allocPrint(allocator, "/nix/var/nix/profiles/system", .{})
    else
        try fmt.allocPrint(allocator, "/nix/var/nix/system-profiles/{s}", .{profile_name});

    // Rollback and set generation profile
    try setNixEnvProfile(allocator, profile_dirname);

    // Switch to configuration
    const specialization = findSpecialization(allocator) catch blk: {
        log.warn("using base configuration without specialisations", .{});
        break :blk null;
    };

    const stc = if (specialization) |spec|
        try fmt.allocPrint(allocator, "{s}/specialisation/{s}/bin/switch-to-configuration", .{ profile_dirname, spec })
    else
        try fmt.allocPrint(allocator, "{s}/bin/switch-to-configuration", .{profile_dirname});
    defer allocator.free(stc);

    if (specialization) |spec| {
        if (!fileExistsAbsolute(stc)) {
            log.err("failed to find specialization {s}", .{spec});
            return GenerationRollbackError.UnknownSpecialization;
        }
    }

    try runSwitchToConfiguration(allocator, stc, "switch");
}

pub fn generationRollbackMain(allocator: Allocator, args: GenerationRollbackArgs, profile: ?[]const u8) u8 {
    const profile_name = profile orelse "system";

    rollbackGeneration(allocator, args, profile_name) catch |err| {
        switch (err) {
            GenerationRollbackError.SetNixProfileFailed, GenerationRollbackError.SwitchToConfigurationFailed => {
                return if (exit_status != 0) exit_status else 1;
            },
            GenerationRollbackError.UnknownSpecialization => return 1,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };

    return 0;
}
