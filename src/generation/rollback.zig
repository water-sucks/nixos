const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

var exit_status: u8 = 0;

// Reusing specialization and switch-to-configuration logic
// from `nixos build`, because I'm lazy.
const build = @import("../build.zig");
const findSpecialization = build.findSpecialization;
const runSwitchToConfiguration = build.runSwitchToConfiguration;

const GenerationRollbackError = error{
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
    UnknownSpecialization,
} || Allocator.Error;

pub fn setNixEnvProfile(allocator: Allocator, profile_dirname: []const u8) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-env", "--profile", profile_dirname, "--rollback" });

    var result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return GenerationRollbackError.SetNixProfileFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationRollbackError.SetNixProfileFailed;
    }
}

fn rollbackGeneration(allocator: Allocator, profile_name: []const u8) !void {
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

    runSwitchToConfiguration(allocator, stc, "switch", .{
        .exit_status = &exit_status,
    }) catch return GenerationRollbackError.SwitchToConfigurationFailed;
}

pub fn generationRollbackMain(allocator: Allocator, profile: ?[]const u8) u8 {
    const profile_dir = profile orelse "system";

    rollbackGeneration(allocator, profile_dir) catch |err| {
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
