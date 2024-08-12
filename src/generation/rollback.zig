const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;
const ArgParseError = argparse.ArgParseError;

const config = @import("../config.zig");

const Constants = @import("../constants.zig");

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

// Reusing specialization logic from `nixos apply`, because I'm lazy.
const findSpecialization = @import("../apply.zig").findSpecialization;

pub const GenerationRollbackCommand = struct {
    verbose: bool = false,
    dry: bool = false,
    specialization: ?[]const u8 = null,
    yes: bool = false,

    const usage =
        \\Rollback to the previous NixOS generation.
        \\
        \\Usage:
        \\    nixos generation rollback [options]
        \\
        \\Options:
        \\    -d, --dry               Show what would be activated, but do not activate
        \\    -h, --help              Show this help menu
        \\    -s, --specialisation    Activate the given specialisation
        \\    -v, --verbose           Show verbose logging
        \\    -y, --yes               Automatically confirm activation
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationRollbackCommand) !?[]const u8 {
        var next_arg = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--dry", "-d")) {
                parsed.dry = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--specialisation", "-s")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.specialization = next;
            } else if (argIs(arg, "--verbose", "-v")) {
                parsed.verbose = true;
            } else if (argIs(arg, "--yes", "-y")) {
                parsed.yes = true;
            } else {
                return arg;
            }

            next_arg = argv.next();
        }

        return null;
    }
};

const GenerationRollbackError = error{
    PermissionDenied,
    ResourceAccessFailed,
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
} || Allocator.Error;

var exit_status: u8 = 0;
var verbose: bool = false;

pub fn setNixEnvProfile(allocator: Allocator, profile_dirname: []const u8, dry: bool, gen_number: usize) !void {
    const gen_number_str = try fmt.allocPrint(allocator, "{d}", .{gen_number});
    defer allocator.free(gen_number_str);

    const argv = &.{ "nix-env", "--profile", profile_dirname, "--switch-generation", gen_number_str };

    if (verbose) log.cmd(argv);

    if (dry) return;

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
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

fn rollbackGeneration(allocator: Allocator, args: GenerationRollbackCommand, profile_name: []const u8) !void {
    verbose = args.verbose;

    const c = config.getConfig();

    if (linux.geteuid() != 0) {
        utils.execAsRoot(allocator) catch |err| {
            log.err("unable to re-exec this command as root: {s}", .{@errorName(err)});
            return GenerationRollbackError.PermissionDenied;
        };
    }

    const base_profile_dirname = if (mem.eql(u8, profile_name, "system"))
        Constants.nix_profiles
    else
        Constants.nix_system_profiles;
    const profile_dirname = try fs.path.join(allocator, &.{ base_profile_dirname, profile_name });
    defer allocator.free(profile_dirname);

    // While it is possible to use the `rollback` command, we still need
    // to find the previous generation number ourselves in order to run
    // `nvd` or `nix store diff-closures` properly.
    const gen_list = utils.generation.gatherGenerationsFromProfile(allocator, profile_name) catch return GenerationRollbackError.ResourceAccessFailed;
    defer allocator.free(gen_list);

    const current_gen_idx = blk: {
        for (gen_list, 0..) |gen, i| {
            if (gen.current) break :blk i;
        }

        log.err("no current generation detected in generations list", .{});
        return GenerationRollbackError.ResourceAccessFailed;
    };

    if (current_gen_idx == 0) {
        log.err("no generation older than the current one ({d}) exists", .{gen_list[current_gen_idx].generation.?});
        return GenerationRollbackError.ResourceAccessFailed;
    }

    const prev_gen = gen_list[current_gen_idx - 1];
    const prev_gen_number = prev_gen.generation.?;

    const prev_gen_dirname = try fmt.allocPrint(allocator, "{s}/{s}-{d}-link", .{ base_profile_dirname, profile_name, prev_gen_number });
    defer allocator.free(prev_gen_dirname);

    log.step("Comparing changes...", .{});
    const diff_cmd_status = utils.generation.diff(allocator, Constants.current_system, prev_gen_dirname, verbose) catch |err| blk: {
        log.warn("diff command failed to run: {s}", .{@errorName(err)});
        break :blk 0;
    };
    if (diff_cmd_status != 0) {
        log.warn("diff command exited with status {d}", .{diff_cmd_status});
    }

    // Ask for confirmation, if needed
    if (!args.yes and !c.no_confirm) {
        log.print("\n", .{});
        const confirm = utils.confirmationInput("Activate previous generation") catch |err| {
            log.err("unable to read stdin for confirmation: {s}", .{@errorName(err)});
            return GenerationRollbackError.ResourceAccessFailed;
        };
        if (!confirm) {
            log.warn("confirmation was not given, not proceeding with activation", .{});
            return;
        }
    }

    log.step("Activating previous generation...", .{});

    // Rollback and set generation profile
    setNixEnvProfile(allocator, profile_dirname, args.dry, prev_gen_number) catch |err| {
        log.err("failed to set system profile with nix-env", .{});
        return err;
    };

    // Switch to configuration
    const specialization = args.specialization orelse findSpecialization(allocator) catch blk: {
        log.warn("using base configuration without specialisations", .{});
        break :blk null;
    };

    const stc = if (specialization) |spec|
        try fs.path.join(allocator, &.{ profile_dirname, "specialisation", spec, "/bin/switch-to-configuration" })
    else
        try fs.path.join(allocator, &.{ profile_dirname, "/bin/switch-to-configuration" });
    defer allocator.free(stc);

    if (specialization) |spec| {
        if (!fileExistsAbsolute(stc)) {
            log.warn("could not find specialisation '{s}'", .{spec});
            log.warn("using base configuration without specialisations", .{});
        }
    }

    const action = if (args.dry) "dry-activate" else "switch";
    try runSwitchToConfiguration(allocator, stc, action);
}

pub fn generationRollbackMain(allocator: Allocator, args: GenerationRollbackCommand, profile: ?[]const u8) u8 {
    const profile_name = profile orelse "system";

    rollbackGeneration(allocator, args, profile_name) catch |err| {
        switch (err) {
            GenerationRollbackError.PermissionDenied => return 13,
            GenerationRollbackError.ResourceAccessFailed => return 3,
            GenerationRollbackError.SetNixProfileFailed, GenerationRollbackError.SwitchToConfigurationFailed => {
                return if (exit_status != 0) exit_status else 1;
            },
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };

    return 0;
}
