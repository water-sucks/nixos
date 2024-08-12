const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const argparse = @import("../argparse.zig");
const argError = argparse.argError;
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;
const ArgParseError = argparse.ArgParseError;

const Constants = @import("../constants.zig");

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

// Reusing specialization and switch-to-configuration logic
// from `nixos apply`, because I'm lazy.
const findSpecialization = @import("../apply.zig").findSpecialization;

pub const GenerationSwitchCommand = struct {
    verbose: bool = false,
    dry: bool = false,
    specialization: ?[]const u8 = null,
    yes: bool = false,
    gen_number: ?[]const u8 = null,

    const usage =
        \\Activate an arbitrary existing NixOS generation.
        \\
        \\Usage:
        \\    nixos generation switch <NUMBER> [options]
        \\
        \\Arguments:
        \\    <NUMBER>:    Number of generation to switch to
        \\
        \\Options:
        \\    -d, --dry               Show what would be activated, but do not activate
        \\    -h, --help              Show this help menu
        \\    -s, --specialisation    Activate the given specialisation
        \\    -v, --verbose           Show verbose logging
        \\    -y, --yes               Automatically confirm activation
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *GenerationSwitchCommand) !?[]const u8 {
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
            } else if (argparse.isFlag(arg)) {
                return arg;
            } else {
                if (parsed.gen_number != null) {
                    return arg;
                }

                _ = std.fmt.parseInt(usize, arg, 10) catch |err| {
                    switch (err) {
                        error.InvalidCharacter => argError("'{s}' is not a number", .{arg}),
                        error.Overflow => argError("unable to parse number '{s}'", .{arg}),
                    }
                    return ArgParseError.InvalidArgument;
                };

                parsed.gen_number = arg;
            }

            next_arg = argv.next();
        }

        if (parsed.gen_number == null) {
            argError("missing required argument <NUMBER>", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        return null;
    }
};

const GenerationSwitchError = error{
    PermissionDenied,
    ResourceAccessFailed,
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
} || Allocator.Error;

var exit_status: u8 = 0;
var verbose: bool = false;

pub fn setNixEnvProfile(allocator: Allocator, profile_dirname: []const u8, generation: []const u8, dry: bool) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-env", "--profile", profile_dirname, "--switch-generation", generation });

    if (verbose) log.cmd(argv.items);

    if (dry) return;

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return GenerationSwitchError.SetNixProfileFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationSwitchError.SetNixProfileFailed;
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
    }) catch return GenerationSwitchError.SwitchToConfigurationFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationSwitchError.SwitchToConfigurationFailed;
    }
}

pub fn switchGeneration(allocator: Allocator, args: GenerationSwitchCommand, profile_name: []const u8) GenerationSwitchError!void {
    const generation = args.gen_number.?;
    verbose = args.verbose;

    if (linux.geteuid() != 0) {
        utils.execAsRoot(allocator) catch |err| {
            log.err("unable to re-exec this command as root: {s}", .{@errorName(err)});
            return GenerationSwitchError.PermissionDenied;
        };
    }

    // Generate profile directory name
    const base_profile_dirname = if (mem.eql(u8, profile_name, "system"))
        Constants.nix_profiles
    else
        Constants.nix_system_profiles;

    // $base_profile_dirname/$profile_name-$gen_number-link
    const profile_link = try fmt.allocPrint(allocator, "{s}/{s}-{s}-link", .{ base_profile_dirname, profile_name, generation });
    defer allocator.free(profile_link);

    const current_profile_dirname = try fs.path.join(allocator, &.{ base_profile_dirname, profile_name });
    defer allocator.free(current_profile_dirname);

    // Check if generation exists. There are rare cases in which a Nix profile can
    // point to a nonexistent store path, such as in the case that someone manually
    // deletes stuff, but this shouldn't really happen much, if at all.
    fs.cwd().access(profile_link, .{}) catch |err| {
        log.err("unexpected error encountered opening {s}: {s}", .{ profile_link, @errorName(err) });
        return GenerationSwitchError.ResourceAccessFailed;
    };

    log.step("Comparing changes...", .{});
    const diff_cmd_status = utils.generation.diff(allocator, Constants.current_system, profile_link, verbose) catch |err| blk: {
        log.warn("diff command failed to run: {s}", .{@errorName(err)});
        break :blk 0;
    };
    if (diff_cmd_status != 0) {
        log.warn("diff command exited with status {d}", .{diff_cmd_status});
    }

    // Ask for confirmation, if needed
    if (!args.yes) {
        const prompt = try fmt.allocPrint(allocator, "Activate generation {s}", .{generation});
        defer allocator.free(prompt);
        const confirm = utils.confirmationInput(prompt) catch |err| {
            log.err("unable to read stdin for confirmation: {s}", .{@errorName(err)});
            return GenerationSwitchError.ResourceAccessFailed;
        };
        if (!confirm) {
            log.warn("confirmation was not given, not proceeding with activation", .{});
            return;
        }
    }

    log.step("Activating generation {s}...", .{generation});

    // Switch generation profile
    setNixEnvProfile(allocator, current_profile_dirname, generation, args.dry) catch {
        log.err("failed to set system profile with nix-env", .{});
        return GenerationSwitchError.SetNixProfileFailed;
    };

    // Switch to configuration
    const specialization = args.specialization orelse findSpecialization(allocator) catch blk: {
        log.warn("using base configuration without specialisations", .{});
        break :blk null;
    };

    const stc = if (specialization) |spec|
        try fs.path.join(allocator, &.{ current_profile_dirname, "specialisation", spec, "/bin/switch-to-configuration" })
    else
        try fs.path.join(allocator, &.{ current_profile_dirname, "/bin/switch-to-configuration" });
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

pub fn generationSwitchMain(allocator: Allocator, args: GenerationSwitchCommand, profile: ?[]const u8) u8 {
    const profile_name = profile orelse "system";

    switchGeneration(allocator, args, profile_name) catch |err| {
        switch (err) {
            GenerationSwitchError.SetNixProfileFailed, GenerationSwitchError.SwitchToConfigurationFailed => {
                return if (exit_status != 0) exit_status else 1;
            },
            GenerationSwitchError.ResourceAccessFailed => return 4,
            GenerationSwitchError.PermissionDenied => return 13,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };

    return 0;
}
