//! A replacement for `nixos-rebuild`.

const std = @import("std");
const opts = @import("options");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const meta = std.meta;
const posix = std.posix;
const process = std.process;
const linux = std.os.linux;

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = process.ArgIterator;
const ComptimeStringMap = std.ComptimeStringMap;

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argIs = argparse.argIs;
const argIn = argparse.argIn;
const argError = argparse.argError;
const getNextArgs = argparse.getNextArgs;

const config = @import("config.zig");
const Config = config.Config;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const toml = @import("toml");

const utils = @import("utils.zig");
const FlakeRef = utils.FlakeRef;
const fileExistsAbsolute = utils.fileExistsAbsolute;
const readFile = utils.readFile;
const runCmd = utils.runCmd;
const isExecutable = utils.isExecutable;

pub const ApplyCommand = struct {
    dry: bool = false,
    flake: ?[]const u8 = null,
    install_bootloader: bool = false,
    no_activate: bool = false,
    no_boot: bool = false,
    output: ?[]const u8 = null,
    profile_name: ?[]const u8 = null,
    specialization: ?[]const u8 = null,
    upgrade_channels: bool = false,
    upgrade_all_channels: bool = false,
    tag: ?[]const u8 = null,
    use_nom: bool = false,
    vm: bool = false,
    vm_with_bootloader: bool = false,
    yes: bool = false,

    build_options: ArrayList([]const u8),
    flake_options: ArrayList([]const u8),

    const Self = @This();

    const usage =
        \\Build and activate a NixOS system from a given configuration.
        \\
        \\Usage:
        \\
    ++ (if (opts.flake)
        \\    nixos apply [FLAKE-REF] [options]
        \\
        \\Arguments:
        \\    [FLAKE-REF]    Flake ref to build configuration from (default: $NIXOS_CONFIG)
        \\
    else
        \\    nixos apply [options]
        \\
    ) ++
        \\
        \\Options:
        \\    -d, --dry                      Show what would be built or ran but do not actually run it
        \\    -h, --help                     Show this help menu
        \\        --install-bootloader       (Re)install the bootloader on the configured device(s)
        \\        --no-activate              Do not activate the built configuration
        \\        --no-boot                  Do not create boot entry for this generation
        \\    -o, --output <LOCATION>        Symlink the output to a location
        \\    -p, --profile-name <NAME>      Name of the system profile to use
        \\    -s, --specialisation <NAME>    Activate the given specialisation
        \\    -t, --tag <MESSAGE>            Tag this generation with a description
    ++ utils.optionalArgString(!opts.flake,
        \\    -u, --upgrade                  Upgrade the root user's `nixos` channel
        \\        --upgrade-all              Upgrade all of the root user's channels
    ) ++
        \\        --use-nom                  Use `nix-output-monitor` for building
        \\    -v, --verbose                  Show verbose logging
        \\        --vm                       Build a script that starts a NixOS VM
        \\        --vm-with-bootloader       Build a script that starts a NixOS VM through the configured bootloader
        \\    -y, --yes                      Automatically confirm activation
        \\
        \\This command also forwards Nix options passed here to all relevant Nix invocations.
        \\Check the Nix manual page for more details on what options are available.
        \\
    ;

    pub fn init(allocator: Allocator) Self {
        return ApplyCommand{
            .build_options = ArrayList([]const u8).init(allocator),
            .flake_options = ArrayList([]const u8).init(allocator),
        };
    }

    /// Parse arguments from the command line and construct a BuildArgs struct
    /// with the provided arguments. Caller owns a BuildArgs instance.
    pub fn parseArgs(args: *ArgIterator, parsed: *ApplyCommand) !?[]const u8 {
        const c = config.getConfig();

        var next_arg: ?[]const u8 = args.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--dry", "-d")) {
                parsed.dry = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--install-bootloader", null)) {
                parsed.install_bootloader = true;
            } else if (argIs(arg, "--no-activate", null)) {
                parsed.no_activate = true;
            } else if (argIs(arg, "--no-boot", null)) {
                parsed.no_boot = true;
            } else if (argIs(arg, "--output", "-o")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                parsed.output = next;
            } else if (argIs(arg, "--profile-name", "-p")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                parsed.profile_name = next;
            } else if (argIs(arg, "--specialisation", "-s")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                parsed.specialization = next;
            } else if (argIs(arg, "--tag", "-t")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                parsed.tag = next;
            } else if (argIs(arg, "--upgrade", "-u") and !opts.flake) {
                parsed.upgrade_channels = true;
            } else if (argIs(arg, "--upgrade-all", null) and !opts.flake) {
                parsed.upgrade_channels = true;
                parsed.upgrade_all_channels = true;
            } else if (argIs(arg, "--use-nom", null)) {
                parsed.use_nom = true;
            } else if (argIn(arg, &.{ "--verbose", "-v", "-vv", "-vvv", "-vvvv", "-vvvvv" })) {
                verbose = true;
                try parsed.build_options.append(arg);
            } else if (argIs(arg, "--vm", null)) {
                parsed.vm = true;
            } else if (argIs(arg, "--vm-with-bootloader", null)) {
                parsed.vm_with_bootloader = true;
            } else if (argIs(arg, "--yes", "-y")) {
                parsed.yes = true;
            } else if (argIn(arg, &.{ "--quiet", "--print-build-logs", "-L", "--no-build-output", "-Q", "--show-trace", "--keep-going", "-k", "--keep-failed", "-K", "--fallback", "--refresh", "--repair", "--impure", "--offline", "--no-net" })) {
                try parsed.build_options.append(arg);
            } else if (argIn(arg, &.{ "-I", "--max-jobs", "-j", "--cores", "--builders", "--log-format" })) {
                const next = (try getNextArgs(args, arg, 1))[0];
                try parsed.build_options.append(arg);
                try parsed.build_options.append(next);
            } else if (argIs(arg, "--option", null)) {
                const next_args = try getNextArgs(args, arg, 2);
                try parsed.build_options.appendSlice(&.{ arg, next_args[0], next_args[1] });
            } else if (argIn(arg, &.{ "--recreate-lock-file", "--no-update-lock-file", "--no-write-lock-file", "--no-registries", "--commit-lock-file" }) and opts.flake) {
                try parsed.flake_options.append(arg);
            } else if (argIs(arg, "--update-input", null) and opts.flake) {
                const next = (try getNextArgs(args, arg, 1))[0];
                try parsed.flake_options.append(arg);
                try parsed.flake_options.append(next);
            } else if (argIs(arg, "--override-input", null) and opts.flake) {
                const next_args = try getNextArgs(args, arg, 2);
                try parsed.build_options.appendSlice(&.{ arg, next_args[0], next_args[1] });
            } else {
                if (opts.flake and parsed.flake == null) {
                    parsed.flake = arg;
                } else {
                    return arg;
                }
            }

            next_arg = args.next();
        }

        if (parsed.tag != null and opts.flake) {
            const is_impure = blk: {
                for (parsed.build_options.items) |arg| {
                    if (mem.eql(u8, arg, "--impure")) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (!is_impure and !c.apply.imply_impure_with_tag) {
                argError("--impure is required when using --tag for flake configurations", .{});
                return ArgParseError.ConflictingOptions;
            } else if (!is_impure and c.apply.imply_impure_with_tag) {
                try parsed.build_options.append("--impure");
            }
        }

        if (parsed.dry and parsed.output != null) {
            argError("--dry cannot be used together with --output", .{});
            return ArgParseError.ConflictingOptions;
        }

        if (parsed.vm and parsed.vm_with_bootloader) {
            argError("--vm cannot be used together with --vm-with-bootloader", .{});
            return ArgParseError.ConflictingOptions;
        }

        if (parsed.no_activate and parsed.specialization != null) {
            argError("--specialization can only be specified when activating, remove --no-activate", .{});
            return ArgParseError.ConflictingOptions;
        }

        if (parsed.no_activate and parsed.no_boot and parsed.install_bootloader) {
            argError("--install-bootloader requires activation, remove --no-activate and/or --no-boot", .{});
            return ArgParseError.ConflictingOptions;
        }

        return null;
    }

    pub fn deinit(self: *Self) void {
        self.build_options.deinit();
        self.flake_options.deinit();
    }
};

// Verbose output
// This is easier than to use a field in ApplyArgs and pass it around.
var verbose: bool = false;

pub const ApplyError = error{
    ConfigurationNotFound,
    NixBuildFailed,
    PermissionDenied,
    ResourceCreationFailed,
    ResourceAccessFailed,
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
    UnknownSpecialization,
    UpgradeChannelsFailed,
} || process.GetEnvMapError || Allocator.Error;

pub const BuildType = enum {
    System,
    SystemActivation,
    VM,
    VMWithBootloader,
};

// Global exit status indicator for runCmd, so
// that the correct exit code from a failed command
// can be returned.
var exit_status: u8 = 0;

const channel_directory = Constants.nix_profiles ++ "/per-user/root/channels";

/// Iterate through all Nix channels and upgrade them if necessary
fn upgradeChannels(allocator: Allocator, all: bool) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.appendSlice(&.{ "nix-channel", "--update" });

    if (!all) {
        try argv.append("nixos");

        var dir = fs.openDirAbsolute(channel_directory, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    log.err("unable to open {s}: permission denied", .{channel_directory});
                    return ApplyError.PermissionDenied;
                },
                error.DeviceBusy => log.err("unable to open {s}: device busy", .{channel_directory}),
                error.FileNotFound => log.err("unable to {s}: no such file or directory", .{channel_directory}),
                error.NotDir => log.err("{s} is not a directory", .{channel_directory}),

                error.SymLinkLoop => log.err("encountered symlink loop while opening {s}", .{channel_directory}),
                else => log.err("unexpected error encountered opening {s}: {s}", .{ channel_directory, @errorName(err) }),
            }
            return err;
        };
        defer dir.close();

        // Upgrade channels with ".update-on-nixos-rebuild"
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                const filename = try fs.path.join(allocator, &.{ channel_directory, entry.name, ".update-on-nixos-rebuild" });
                defer allocator.free(filename);
                if (fileExistsAbsolute(filename)) {
                    try argv.append(entry.name);
                }
            }
        }
    }

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return ApplyError.UpgradeChannelsFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.UpgradeChannelsFailed;
    }
}

/// Build a legacy-style NixOS configuration
fn nixBuild(
    allocator: Allocator,
    build_type: BuildType,
    options: struct {
        build_options: []const []const u8,
        result_dir: ?[]const u8 = null,
        dry: bool = false,
        use_nom: bool = false,
        tag: ?[]const u8 = null,
    },
) ![]const u8 {
    const attribute = switch (build_type) {
        .VM => "vm",
        .VMWithBootloader => "vmWithBootLoader",
        else => "system",
    };

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    const nix_command = if (options.use_nom) "nom-build" else "nix-build";

    // ${nix_command} -A ${attribute} [-k] [--out-link <dir>] [${build_options}]
    try argv.appendSlice(&.{ nix_command, "<nixpkgs/nixos>", "-A", attribute });

    // Mimic `nixos-rebuild` behavior of using -k option
    // for all commands except for switch and boot
    if (build_type != .SystemActivation) {
        try argv.append("-k");
    }

    if (options.result_dir) |dir| {
        try argv.append("--out-link");
        try argv.append(dir);
    } else {
        try argv.append("--no-out-link");
    }

    try argv.appendSlice(options.build_options);

    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();

    if (options.tag) |message| {
        try env_map.put("NIXOS_GENERATION_TAG", message);
    }

    if (verbose) log.cmd(argv.items);

    // The stdout is the real output path, so no need to readlink anything
    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .env_map = &env_map,
    }) catch return ApplyError.NixBuildFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.NixBuildFailed;
    }

    return result.stdout.?;
}

const GitMessageError = error{
    GitTreeDirty,
    NotGitRepo,
    CommandFailed,
} || Allocator.Error;

/// Find the most recent Git commit message.
///
/// This will only be relevant for clean Git trees, to mirror the
/// behavior of Nix. This is done by using `git diff --quiet`.
fn fetchLastGitCommitMessage(allocator: Allocator) GitMessageError![]const u8 {
    const check_argv = &.{ "git", "diff", "--quiet" };
    errdefer log.warn("skipping commit message retrieval", .{});

    const dirty_check_result = runCmd(.{
        .allocator = allocator,
        .argv = check_argv,
        .stdout_type = .Inherit,
    }) catch |err| {
        log.err("`git diff` for status check failed: {s}", .{@errorName(err)});
        return GitMessageError.CommandFailed;
    };

    if (dirty_check_result.status == 1) {
        log.warn("git tree is dirty, ignoring use_git_commit_msg setting", .{});
        return GitMessageError.GitTreeDirty;
    } else if (dirty_check_result.status == 129) {
        log.warn("configuration directory is not a git repository", .{});
        return error.NotGitRepo;
    }

    const diff_argv = &.{ "git", "log", "-1", "--pretty=%B" };

    const commit_message_result = runCmd(.{
        .allocator = allocator,
        .argv = diff_argv,
    }) catch |err| {
        log.warn("`git log` failed to run: {s}", .{@errorName(err)});
        return GitMessageError.CommandFailed;
    };
    defer allocator.free(commit_message_result.stdout.?);

    if (commit_message_result.status == 1) {
        log.warn("`git log` exited with status {d}", .{commit_message_result.status});
        return GitMessageError.CommandFailed;
    }

    return try allocator.dupe(u8, mem.sliceTo(commit_message_result.stdout.?, '\n'));
}

/// Build a NixOS configuration located in a flake
fn nixBuildFlake(
    allocator: Allocator,
    build_type: BuildType,
    flake_ref: FlakeRef,
    options: struct {
        build_options: []const []const u8,
        flake_options: []const []const u8,
        result_dir: ?[]const u8 = null,
        dry: bool = false,
        use_nom: bool = false,
        tag: ?[]const u8 = null,
    },
) ![]const u8 {
    const attr_to_build = switch (build_type) {
        .VM => "vm",
        .VMWithBootloader => "vmWithBootLoader",
        else => "toplevel",
    };

    const attribute = try fmt.allocPrint(
        allocator,
        "{s}#nixosConfigurations.{s}.config.system.build.{s}",
        .{ flake_ref.uri, flake_ref.system, attr_to_build },
    );
    defer allocator.free(attribute);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    const nix_command = if (options.use_nom) "nom" else "nix";

    // ${nix_command} build ${attribute} [--out-link <dir>] [${build_options}] [${flake_options}]
    try argv.append(nix_command);
    try argv.appendSlice(&.{ "build", attribute, "--print-out-paths" });

    if (options.result_dir) |dir| {
        try argv.append("--out-link");
        try argv.append(dir);
    } else {
        try argv.append("--no-link");
    }

    if (options.dry) {
        try argv.append("--dry-run");
    }

    try argv.appendSlice(options.build_options);
    try argv.appendSlice(options.flake_options);

    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();

    if (options.tag) |message| {
        try env_map.put("NIXOS_GENERATION_TAG", message);
    }

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .env_map = &env_map,
    }) catch return ApplyError.NixBuildFailed;
    defer if (result.stdout) |stdout| allocator.free(stdout);

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.NixBuildFailed;
    }

    return try allocator.dupe(u8, result.stdout.?);
}

/// Set the target system's NixOS system profile to the newly built generation
/// to prepare for --activate or --boot
fn setNixEnvProfile(allocator: Allocator, profile: ?[]const u8, config_path: []const u8) ApplyError!void {
    var profile_dir: []const u8 = undefined;

    if (profile) |name| {
        if (!mem.eql(u8, name, "system")) {
            // Create profile name directory if needed; this is grossly stupid
            // and requires root execution of `nixos`, because yeah.
            // How do I fix this?
            posix.mkdir(Constants.nix_system_profiles, 0o755) catch |err| blk: {
                switch (err) {
                    error.AccessDenied => {
                        log.err("unable to create system profile directory {s}: permission denied", .{Constants.nix_system_profiles});
                        return ApplyError.PermissionDenied;
                    },
                    error.PathAlreadyExists => break :blk,
                    error.FileNotFound => log.err("unable to create system profile directory {s}: no such file or directory", .{Constants.nix_system_profiles}),
                    error.NotDir => log.err("unable to create system profile directory {s}: not a directory", .{Constants.nix_system_profiles}),
                    error.NoSpaceLeft => log.err("unable to create system profile directory {s}: no space left on device", .{Constants.nix_system_profiles}),
                    else => log.err("unexpected error creating system profile directory {s}: {s}", .{ Constants.nix_system_profiles, @errorName(err) }),
                }
                return ApplyError.ResourceCreationFailed;
            };

            profile_dir = try fs.path.join(allocator, &.{ Constants.nix_system_profiles, name });
        }
    } else {
        profile_dir = try fs.path.join(allocator, &.{ Constants.nix_profiles, "system" });
    }
    defer allocator.free(profile_dir);

    const argv = &.{ "nix-env", "-p", profile_dir, "--set", config_path };

    if (verbose) log.cmd(argv);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
    }) catch return ApplyError.SetNixProfileFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.SetNixProfileFailed;
    }
}

// Find specialization name by looking at nixos-cli settings in
// current generation's directory. Caller does not own returned
// memory.
pub fn findSpecialization(allocator: Allocator) !?[]const u8 {
    var parser = toml.Parser(config.Config).init(allocator);
    defer parser.deinit();

    const config_location = Constants.current_system ++ "/etc/nixos-cli/config.toml";
    const config_str = readFile(allocator, config_location) catch |err| {
        switch (err) {
            error.FileNotFound => log.warn("no settings file, unable to find specialisation to activate", .{}),
            else => log.warn("unable to access new settings to find specialisation to activate: {s}", .{@errorName(err)}),
        }
        return err;
    };
    defer allocator.free(config_str);

    const parsed_config = parser.parseString(config_str) catch |err| {
        log.warn("error parsing new settings: {s}", .{@errorName(err)});
        return err;
    };
    defer parsed_config.deinit();
    const c = parsed_config.value;

    return c.apply.specialisation;
}

/// Run the switch-to-configuration.pl script
fn runSwitchToConfiguration(
    allocator: Allocator,
    location: []const u8,
    command: []const u8,
    options: struct { install_bootloader: bool = false },
) !void {
    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();
    if (options.install_bootloader) {
        try env_map.put("NIXOS_INSTALL_BOOTLOADER", "1");
    }

    const argv = &.{ location, command };

    if (verbose) log.cmd(argv);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = &env_map,
    }) catch return ApplyError.SwitchToConfigurationFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.SwitchToConfigurationFailed;
    }
}

fn apply(allocator: Allocator, args: ApplyCommand) ApplyError!void {
    const c = config.getConfig();

    const build_type: BuildType = if (args.vm)
        .VM
    else if (args.vm_with_bootloader)
        .VMWithBootloader
    else if (args.no_activate and args.no_boot)
        .System
    else
        .SystemActivation;

    if (linux.geteuid() != 0 and build_type == .SystemActivation) {
        utils.execAsRoot(allocator) catch |err| {
            log.err("unable to re-exec this command as root: {s}", .{@errorName(err)});
            return ApplyError.PermissionDenied;
        };
    }

    if (verbose) log.step("Looking for configuration...", .{});

    // Find flake if unset, and parse it into its separate components
    var flake_ref: FlakeRef = undefined;
    var hostname_buf: [posix.HOST_NAME_MAX]u8 = undefined;

    // The directory name where the configuration is, if it is a path.
    // This could not be the case with remotely-defined configurations.
    var config_dirname: []const u8 = undefined;

    if (opts.flake) {
        if (verbose) log.info("looking for flake configuration", .{});
        flake_ref = blk: {
            if (args.flake) |flake| {
                break :blk FlakeRef.fromSlice(flake);
            } else {
                if (verbose) log.info("no flake ref specified, using $NIXOS_CONFIG to locate configuration", .{});
                break :blk utils.findFlakeRef() catch return ApplyError.ConfigurationNotFound;
            }
        };
        if (flake_ref.system.len == 0 and verbose) log.info("inferring system name using hostname", .{});
        flake_ref.inferSystemNameIfNeeded(&hostname_buf) catch return ApplyError.ConfigurationNotFound;

        if (verbose) log.info("found flake configuration {s}#{s}", .{ flake_ref.uri, flake_ref.system });
        config_dirname = flake_ref.uri;
    } else {
        config_dirname = utils.findLegacyConfiguration(verbose) catch return ApplyError.ConfigurationNotFound;
    }

    var config_dir: ?fs.Dir = fs.cwd().openDir(config_dirname, .{}) catch |err| blk: {
        // A rough heuristic for determining if this was intended
        // to be a path to a configuration or not. Only absolute
        // paths are allowed; in the case of non-paths such as
        // remote flake refs, do not display any warnings.
        if (fs.path.isAbsolute(config_dirname)) {
            log.warn("unable to open {s}: {s}", .{ config_dirname, @errorName(err) });
            log.warn("some features that depend on this existing will be unavailable", .{});
        }
        break :blk null;
    };
    defer if (config_dir) |*dir| dir.close();
    if (config_dir) |dir| {
        if (verbose) log.info("setting working directory to {s}", .{config_dirname});
        dir.setAsCwd() catch |err| {
            log.err("unable to set {s} as working dir: {s}", .{ config_dirname, @errorName(err) });
            return ApplyError.ResourceAccessFailed;
        };
    }

    // Upgrade all channels
    if (!opts.flake and args.upgrade_channels) {
        log.step("Upgrading channels...", .{});

        upgradeChannels(allocator, args.upgrade_all_channels) catch |err| {
            log.err("upgrading channels failed", .{});
            if (err == error.PermissionDenied) {
                return ApplyError.PermissionDenied;
            } else if (err == error.OutOfMemory) {
                return ApplyError.OutOfMemory;
            }
            return ApplyError.UpgradeChannelsFailed;
        };
    }

    if (build_type == .VM or build_type == .VMWithBootloader) {
        log.step("Building VM configuration...", .{});
    } else {
        log.step("Building system configuration...", .{});
    }

    // Dry activation requires a real build, so --dry-run shouldn't be set
    // if --activate or --boot is set
    const dry_build = args.dry and (build_type == .System);

    // Location of the resulting NixOS generation
    var result: []const u8 = undefined;

    var use_nom = args.use_nom or c.apply.use_nom;
    const nom_found = isExecutable("nom");
    if (args.use_nom and !nom_found) {
        log.err("--use-nom was specified, but `nom` is not executable", .{});
        return ApplyError.NixBuildFailed;
    } else if (c.apply.use_nom and !nom_found) {
        log.warn("apply.use_nom is specified in config, but `nom` is not executable", .{});
        log.warn("falling back to `nix` command for building", .{});
        use_nom = false;
    }

    var tag_alloc = false;
    const tag: ?[]const u8 = blk: {
        if (args.tag) |t| {
            if (c.apply.use_git_commit_msg) {
                log.info("explicit generation tag was given, ignoring apply.use_git_commit_msg setting", .{});
            }
            break :blk t;
        }

        if (c.apply.use_git_commit_msg) {
            const message = fetchLastGitCommitMessage(allocator) catch break :blk null;
            tag_alloc = true;
            break :blk message;
        }

        break :blk null;
    };
    defer if (tag_alloc and tag != null) allocator.free(tag.?);

    if (opts.flake) {
        result = nixBuildFlake(allocator, build_type, flake_ref, .{
            .build_options = args.build_options.items,
            .flake_options = args.flake_options.items,
            .result_dir = args.output,
            .dry = dry_build,
            .use_nom = use_nom,
            .tag = args.tag,
        }) catch |err| {
            log.err("failed to build the system configuration", .{});
            if (err == error.PermissionDenied) {
                return ApplyError.PermissionDenied;
            } else if (err == error.OutOfMemory) {
                return ApplyError.OutOfMemory;
            }
            return ApplyError.NixBuildFailed;
        };
    } else {
        result = nixBuild(allocator, build_type, .{
            .build_options = args.build_options.items,
            .result_dir = args.output,
            .dry = dry_build,
            .use_nom = use_nom,
            .tag = args.tag,
        }) catch |err| {
            log.err("failed to build the system configuration", .{});
            if (err == error.PermissionDenied) {
                return ApplyError.PermissionDenied;
            } else if (err == error.OutOfMemory) {
                return ApplyError.OutOfMemory;
            }
            return ApplyError.NixBuildFailed;
        };
    }

    // Yes, this is all just to mimic the behavior of nixos-rebuild to print
    // a message saying the VM can be ran with a command. Stupid, I know.
    if ((build_type == .VM or build_type == .VMWithBootloader) and !args.dry) {
        const dirname = try fs.path.join(allocator, &.{ result, "bin" });
        defer allocator.free(dirname);

        var dir = fs.openDirAbsolute(dirname, .{ .iterate = true }) catch @panic("unable to open /bin in result dir");
        defer dir.close();

        var filename: ?[]const u8 = null;

        var iter = dir.iterate();
        while (iter.next() catch @panic("unable to iterate VM result directory")) |entry| {
            if (mem.startsWith(u8, entry.name, "run-") and mem.endsWith(u8, entry.name, "-vm")) {
                filename = entry.name;
                break;
            }
        }

        if (filename) |f| {
            log.print("Done. The virtual machine can be started by running {s}/{s}.\n", .{ dirname, f });
        } else @panic("virtual machine not located in /bin of result dir");

        return;
    }

    if (build_type != .SystemActivation) {
        if (verbose) log.info("this is a dry build; no activation will take place", .{});
        return;
    }

    log.step("Comparing changes...", .{});
    const diff_cmd_status = utils.generation.diff(allocator, Constants.current_system, result, verbose) catch |err| blk: {
        log.warn("diff command failed to run: {s}", .{@errorName(err)});
        break :blk 0;
    };
    if (diff_cmd_status != 0) {
        log.warn("diff command exited with status {d}", .{diff_cmd_status});
    }

    // Ask for confirmation, if needed
    if (!args.yes and !c.no_confirm and !args.dry) {
        log.print("\n", .{});
        const confirm = utils.confirmationInput("Activate this configuration") catch |err| {
            log.err("unable to read stdin for confirmation: {s}", .{@errorName(err)});
            return ApplyError.ResourceAccessFailed;
        };
        if (!confirm) {
            log.warn("confirmation was not given, not proceeding with activation", .{});
            return;
        }
    }

    // Set nix-env profile, if needed
    if (!args.dry) {
        if (verbose) {
            log.step("Setting system profile...", .{});
        }
        setNixEnvProfile(allocator, args.profile_name, result) catch |err| {
            log.err("failed to set system profile with nix-env", .{});
            return err;
        };
    }

    log.step("Activating configuration...", .{});

    if (args.dry) {
        log.info("this is a dry activation, no real activation will take place", .{});
    }

    // Run switch-to-configuration script, if needed. This will use the
    // specialization in /etc/NIXOS_SPECIALISATION, or it will default
    // to no specialization if no explicit specialization is provided.
    const specialization = args.specialization orelse findSpecialization(allocator) catch blk: {
        log.warn("using base configuration without specialisations", .{});
        break :blk null;
    };

    const stc = if (specialization) |spec|
        try fs.path.join(allocator, &.{ result, "specialisation", spec, "bin", "switch-to-configuration" })
    else
        try fs.path.join(allocator, &.{ result, "bin", "switch-to-configuration" });
    defer allocator.free(stc);

    // Assert the specialization exists
    if (specialization) |spec| {
        if (!fileExistsAbsolute(stc)) {
            log.err("failed to find specialization {s}", .{spec});
            return ApplyError.UnknownSpecialization;
        }
    }

    const stc_action = if (args.dry and !args.no_activate)
        "dry-activate"
    else if (!args.no_activate and !args.no_boot)
        "switch"
    else if (args.no_activate and !args.no_boot)
        "boot"
    else if (!args.no_activate and args.no_boot)
        "test"
    else
        unreachable;

    // No need to print error message, the script will do that.
    try runSwitchToConfiguration(allocator, stc, stc_action, .{
        .install_bootloader = args.install_bootloader,
    });
}

// Run apply and provide the relevant exit code
pub fn applyMain(allocator: Allocator, args: ApplyCommand) u8 {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the apply command is currently unsupported on non-NixOS systems", .{});
        return 3;
    }

    apply(allocator, args) catch |err| {
        switch (err) {
            ApplyError.NixBuildFailed, ApplyError.SetNixProfileFailed, ApplyError.UpgradeChannelsFailed, ApplyError.SwitchToConfigurationFailed => {
                return if (exit_status != 0) exit_status else 1;
            },
            ApplyError.PermissionDenied => return 13,
            ApplyError.ResourceCreationFailed => return 4,
            ApplyError.ResourceAccessFailed => return 3,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
            else => return 1,
        }
    };
    return 0;
}
