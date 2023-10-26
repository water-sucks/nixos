const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = std.process.ArgIterator;

const log = @import("../log.zig");

const utils = @import("../utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

// Reusing specialization and switch-to-configuration logic
// from `nixos build`, because I'm lazy.
const build = @import("../build.zig");
const findSpecialization = build.findSpecialization;
const runSwitchToConfiguration = build.runSwitchToConfiguration;

const GenerationSwitchError = error{
    PermissionDenied,
    ResourceAccessFailed,
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
    UnknownSpecialization,
} || Allocator.Error;

var exit_status: u8 = 0;

pub fn setNixEnvProfile(allocator: Allocator, profile_dirname: []const u8, gen_number: usize) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    var num_buf: [20]u8 = undefined;
    const generation = fmt.bufPrint(&num_buf, "{d}", .{gen_number}) catch @panic("generation number exceeded buffer size");

    try argv.appendSlice(&.{ "nix-env", "--profile", profile_dirname, "--switch-generation", generation });

    var result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return GenerationSwitchError.SetNixProfileFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return GenerationSwitchError.SetNixProfileFailed;
    }
}

pub fn switchGeneration(allocator: Allocator, gen_number: usize, profile_name: []const u8) GenerationSwitchError!void {
    // Generate profile directory name
    const base_profile_dirname = if (mem.eql(u8, profile_name, "system"))
        "/nix/var/nix/profiles"
    else
        "/nix/var/nix/profiles/system-profiles";

    // $base_profile_dirname/$profile_name-$gen_number-link
    const profile_link = try fmt.allocPrint(allocator, "{s}/{s}-{d}-link", .{ base_profile_dirname, profile_name, gen_number });
    defer allocator.free(profile_link);

    const current_profile_dirname = try fmt.allocPrint(allocator, "{s}/{s}", .{ base_profile_dirname, profile_name });
    defer allocator.free(current_profile_dirname);

    // Check if it exists
    const generation_dirname = std.fs.realpathAlloc(allocator, profile_link) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("failed to find generation {s}: permission denied", .{profile_link});
                return GenerationSwitchError.PermissionDenied;
            },
            error.FileNotFound => log.err("failed to find generation {s}: no such file or directory", .{profile_link}),
            error.SymLinkLoop => log.err("encountered symlink loop while determining realpath of {s}", .{profile_link}),
            else => log.err("unexpected error encountered when determining realpath of {s}: {s}", .{ profile_link, @errorName(err) }),
        }
        return GenerationSwitchError.ResourceAccessFailed;
    };
    defer allocator.free(generation_dirname);

    var generation_dir = fs.openDirAbsolute(generation_dirname, .{}) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to open {s}: permission denied", .{generation_dirname});
                return GenerationSwitchError.PermissionDenied;
            },
            error.DeviceBusy => log.err("unable to open {s}: device busy", .{generation_dirname}),
            error.FileNotFound => log.err("unable to {s}: no such file or directory", .{generation_dirname}),
            error.NotDir => log.err("{s} is not a directory", .{generation_dirname}),

            error.SymLinkLoop => log.err("encountered symlink loop while opening {s}", .{generation_dirname}),
            else => log.err("unexpected error encountered opening {s}: {s}", .{ generation_dirname, @errorName(err) }),
        }
        return GenerationSwitchError.ResourceAccessFailed;
    };
    defer generation_dir.close();

    log.info("activating generation {d}...", .{gen_number});

    // Switch generation profile
    try setNixEnvProfile(allocator, current_profile_dirname, gen_number);

    // Switch to configuration
    const specialization = findSpecialization(allocator) catch blk: {
        log.warn("using base configuration without specialisations", .{});
        break :blk null;
    };

    const stc = if (specialization) |spec|
        try fmt.allocPrint(allocator, "{s}/specialisation/{s}/bin/switch-to-configuration", .{ current_profile_dirname, spec })
    else
        try fmt.allocPrint(allocator, "{s}/bin/switch-to-configuration", .{current_profile_dirname});
    defer allocator.free(stc);

    if (specialization) |spec| {
        if (!fileExistsAbsolute(stc)) {
            log.err("failed to find specialization {s}", .{spec});
            return GenerationSwitchError.UnknownSpecialization;
        }
    }

    runSwitchToConfiguration(allocator, stc, "switch", .{}) catch return GenerationSwitchError.SwitchToConfigurationFailed;
}

pub fn generationSwitchMain(allocator: Allocator, gen_number: usize, profile: ?[]const u8) u8 {
    const profile_dir = profile orelse "system";

    switchGeneration(allocator, gen_number, profile_dir) catch |err| {
        switch (err) {
            GenerationSwitchError.SetNixProfileFailed, GenerationSwitchError.SwitchToConfigurationFailed => {
                return if (exit_status != 0) exit_status else 1;
            },
            GenerationSwitchError.ResourceAccessFailed => return 4,
            GenerationSwitchError.PermissionDenied => return 13,
            GenerationSwitchError.UnknownSpecialization => return 1,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };

    return 0;
}
