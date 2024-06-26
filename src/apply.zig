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
const conflict = argparse.conflict;
const require = argparse.require;

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
const isExectuable = utils.isExecutable;

pub const ApplyArgs = struct {
    // Show what would be built or ran but do not actually run it
    dry: bool = false,
    // Build the NixOS system from the specified flake ref
    flake: ?[]const u8 = null,
    // (Re)install the bootloader on the device specified by the relevant configuration options
    install_bootloader: bool = false,
    // Do not activate the built configuration
    no_activate: bool = false,
    // Do not create a boot entry for this generation
    no_boot: bool = false,
    // Symlink the output to a location (default: ./result, none on system activation)
    output: ?[]const u8 = null,
    // Name of the system profile to use
    profile_name: ?[]const u8 = null,
    // Activate the given specialisation
    specialization: ?[]const u8 = null,
    // Upgrade the root user's 'nixos' channel
    upgrade_channels: bool = false,
    // Upgrade all of the root user's channels
    upgrade_all_channels: bool = false,
    // Use nix-output-monitor for building
    use_nom: bool = false,
    // Build a script that starts a NixOS VM directly
    vm: bool = false,
    // Build a script that starts a NixOS VM through the configured bootloader
    vm_with_bootloader: bool = false,

    /// All options passed through to `nix` invocations
    build_options: ArrayList([]const u8),
    /// All options passed through to `nix` invocations that involve flakes
    flake_options: ArrayList([]const u8),

    const Self = @This();

    const conflicts = .{
        // --dry cannot be used with --output
        .{ "dry", .{"output"} },
        // VM options can only be set by themselves, and not with boot or activate
        .{ "vm", .{ "vm_with_bootloader", "activate", "boot" } },
        // Specializations require `switch-to-configuration` to be ran with `switch` or `test`
        .{ "specialization", .{"no_activate"} },
    };

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
    ++ utils.optionalArgString(!opts.flake,
        \\    -u, --upgrade                  Upgrade the root user's `nixos` channel
        \\        --upgrade-all              Upgrade all of the root user's channels
    ) ++
        \\        --use-nom                  Use `nix-output-monitor` for building
        \\    -v, --verbose                  Show verbose logging
        \\        --vm                       Build a script that starts a NixOS VM
        \\        --vm-with-bootloader       Build a script that starts a NixOS VM through the configured bootloader
        \\
        \\This command also forwards Nix options passed here to all relevant Nix invocations.
        \\Check the Nix manual page for more details on what options are available.
        \\
    ;

    fn init(allocator: Allocator) Self {
        return ApplyArgs{
            .build_options = ArrayList([]const u8).init(allocator),
            .flake_options = ArrayList([]const u8).init(allocator),
        };
    }

    /// Parse arguments from the command line and construct a BuildArgs struct
    /// with the provided arguments. Caller owns a BuildArgs instance.
    pub fn parseArgs(allocator: Allocator, args: *ArgIterator) !ApplyArgs {
        var result: ApplyArgs = ApplyArgs.init(allocator);
        errdefer result.deinit();

        var next_arg: ?[]const u8 = args.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--dry", "-d")) {
                result.dry = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--install-bootloader", null)) {
                result.install_bootloader = true;
            } else if (argIs(arg, "--no-activate", null)) {
                result.no_activate = true;
            } else if (argIs(arg, "--no-boot", null)) {
                result.no_boot = true;
            } else if (argIs(arg, "--output", "-o")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                result.output = next;
            } else if (argIs(arg, "--profile-name", "-p")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                result.profile_name = next;
            } else if (argIs(arg, "--specialisation", "-s")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                result.specialization = next;
            } else if (argIs(arg, "--upgrade", "-u") and !opts.flake) {
                result.upgrade_channels = true;
            } else if (argIs(arg, "--upgrade-all", null) and !opts.flake) {
                result.upgrade_channels = true;
                result.upgrade_all_channels = true;
            } else if (argIs(arg, "--use-nom", null)) {
                result.use_nom = true;
            } else if (argIn(arg, &.{ "--verbose", "-v", "-vv", "-vvv", "-vvvv", "-vvvvv" })) {
                verbose = true;
                try result.build_options.append(arg);
            } else if (argIs(arg, "--vm", null)) {
                result.vm = true;
            } else if (argIs(arg, "--vm-with-bootloader", null)) {
                result.vm_with_bootloader = true;
            } else if (argIn(arg, &.{ "--quiet", "--print-build-logs", "-L", "--no-build-output", "-Q", "--show-trace", "--keep-going", "-k", "--keep-failed", "-K", "--fallback", "--refresh", "--repair", "--impure", "--offline", "--no-net" })) {
                try result.build_options.append(arg);
            } else if (argIn(arg, &.{ "-I", "--max-jobs", "-j", "--cores", "--builders", "--log-format" })) {
                const next = (try getNextArgs(args, arg, 1))[0];
                try result.build_options.append(arg);
                try result.build_options.append(next);
            } else if (argIs(arg, "--option", null)) {
                const next_args = try getNextArgs(args, arg, 2);
                try result.build_options.appendSlice(&.{ arg, next_args[0], next_args[1] });
            } else if (argIn(arg, &.{ "--recreate-lock-file", "--no-update-lock-file", "--no-write-lock-file", "--no-registries", "--commit-lock-file" }) and opts.flake) {
                try result.flake_options.append(arg);
            } else if (argIs(arg, "--update-input", null) and opts.flake) {
                const next = (try getNextArgs(args, arg, 1))[0];
                try result.flake_options.append(arg);
                try result.flake_options.append(next);
            } else if (argIs(arg, "--override-input", null) and opts.flake) {
                const next_args = try getNextArgs(args, arg, 2);
                try result.build_options.appendSlice(&.{ arg, next_args[0], next_args[1] });
            } else {
                if (argparse.isFlag(arg)) {
                    argError("unrecognised flag '{s}'", .{arg});
                    return ArgParseError.InvalidArgument;
                } else if (opts.flake and result.flake == null) {
                    result.flake = arg;
                } else {
                    argError("argument '{s}' is not valid in this context", .{arg});
                    return ArgParseError.InvalidArgument;
                }
            }

            next_arg = args.next();
        }

        if (result.no_activate and result.specialization != null) {
            argError("--install-bootloader requires activation, remove --no-activate and/or --no-boot", .{});
            return ArgParseError.ConflictingOptions;
        }

        return result;
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
    SetNixProfileFailed,
    SwitchToConfigurationFailed,
    UnknownHostname,
    UnknownSpecialization,
    UpgradeChannelsFailed,
} || process.GetEnvMapError || Allocator.Error;

pub const BuildType = enum {
    System,
    SystemActivation,
    VM,
    VMWithBootloader,
};

// Yes, I'm really this lazy. I don't want to use an allocator for this.
var hostname_buffer: [posix.HOST_NAME_MAX]u8 = undefined;

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
    }

    try argv.appendSlice(options.build_options);

    if (verbose) log.cmd(argv.items);

    // The stdout is the real output path, so no need to readlink anything
    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return ApplyError.NixBuildFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.NixBuildFailed;
    }

    return result.stdout.?;
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
    try argv.appendSlice(&.{ "build", attribute });

    if (options.result_dir) |dir| {
        try argv.append("--out-link");
        try argv.append(dir);
    }

    if (options.dry) {
        try argv.append("--dry-run");
    }

    try argv.appendSlice(options.build_options);
    try argv.appendSlice(options.flake_options);

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return ApplyError.NixBuildFailed;

    if (result.stdout) |stdout| {
        allocator.free(stdout);
    }

    if (result.status != 0) {
        exit_status = result.status;
        return ApplyError.NixBuildFailed;
    }

    // No stdout output is emitted by nix build without --print-out-paths,
    // avoiding that option here to support Nix versions without it.
    // Reading the symlink suffices.
    const result_dir = options.result_dir orelse "./result";
    var path_buf: [posix.PATH_MAX]u8 = undefined;
    const path = posix.readlink(result_dir, &path_buf) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to readlink {s}: permission denied", .{result_dir});
                return ApplyError.PermissionDenied;
            },
            error.FileNotFound => @panic("result dir not found after building"),
            error.FileSystem => log.err("unable to readlink {s}: i/o error", .{result_dir}),
            error.NotLink, error.NotDir => @panic("result dir is not a symlink"),
            error.SymLinkLoop => @panic("result dir is a symlink loop"),
            error.SystemResources => return error.OutOfMemory, // corresponds to errno NOMEM when reading link
            else => log.err("unexpected error encountered when reading symlink {s}: {s}", .{ result_dir, @errorName(err) }),
        }
        return err;
    };
    return allocator.dupe(u8, path);
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

fn apply(allocator: Allocator, args: ApplyArgs) ApplyError!void {
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

    if (verbose) log.info("looking for configuration...", .{});
    // Find flake if unset, and parse it into its separate components
    var flake_ref: FlakeRef = undefined;

    if (opts.flake) flake_config: {
        if (args.flake) |flake| {
            // Parse flake arg if explicitly specified as a positional argument.
            flake_ref = FlakeRef.fromSlice(flake);
            if (flake_ref.system.len == 0) {
                flake_ref.system = posix.gethostname(&hostname_buffer) catch {
                    log.err("unable to determine hostname", .{});
                    return ApplyError.UnknownHostname;
                };
            }

            if (verbose) log.info("found flake configuration {s}#{s}", .{ flake_ref.uri, flake_ref.system });

            break :flake_config;
        }

        // Check for existence of flake.nix in the NIXOS_CONFIG
        // or location specified in settings for `apply.config_location`
        const nixos_config = posix.getenv("NIXOS_CONFIG") orelse c.apply.config_location;

        const nixos_config_is_flake = blk: {
            const filename = try fs.path.join(allocator, &.{ nixos_config, "flake.nix" });
            defer allocator.free(filename);
            break :blk fileExistsAbsolute(filename);
        };

        if (nixos_config_is_flake) {
            const dir = try fmt.allocPrint(allocator, "{s}#", .{nixos_config});

            flake_ref = FlakeRef.fromSlice(dir);
            if (flake_ref.system.len == 0) {
                flake_ref.system = posix.gethostname(&hostname_buffer) catch {
                    log.err("unable to determine hostname", .{});
                    return ApplyError.UnknownHostname;
                };
            }
        } else {
            log.err("configuration at {s} is not a flake", .{nixos_config});
            return ApplyError.ConfigurationNotFound;
        }

        if (verbose) log.info("found flake configuration {s}#{s}", .{ flake_ref.uri, flake_ref.system });
    } else {
        // Verify legacy configuration exists, if needed (no need to store location,
        // because it is implicitly used by `nix-build "<nixpkgs/nixos>"`)
        if (posix.getenv("NIXOS_CONFIG")) |dir| {
            const filename = try fs.path.join(allocator, &.{ dir, "default.nix" });
            defer allocator.free(filename);
            if (!fileExistsAbsolute(filename)) {
                log.err("no configuration found, expected {s} to exist", .{filename});
                return ApplyError.ConfigurationNotFound;
            } else {
                if (verbose) log.info("found legacy configuration at {s}", .{filename});
            }
        } else {
            const nix_path = posix.getenv("NIX_PATH") orelse "";
            var paths = mem.tokenize(u8, nix_path, ":");

            var configuration: ?[]const u8 = null;
            while (paths.next()) |path| {
                var kv = mem.tokenize(u8, path, "=");
                if (mem.eql(u8, kv.next() orelse "", "nixos-config")) {
                    configuration = kv.next();
                    break;
                }
            }

            if (configuration) |conf| {
                if (verbose) log.info("found legacy configuration at {s}", .{conf});
            } else {
                log.err("no configuration found, expected 'nixos-config' attribute to exist in NIX_PATH", .{});
                return ApplyError.ConfigurationNotFound;
            }
        }
    }

    // Upgrade all channels
    if (!opts.flake and args.upgrade_channels) {
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

    // Create temporary directory for artifacts
    const tmpdir_base = try fs.path.join(allocator, &.{ posix.getenv("TMPDIR") orelse "/tmp", "nixos-apply" });
    defer allocator.free(tmpdir_base);
    const tmpdir = utils.mkTmpDir(allocator, tmpdir_base) catch |err| {
        if (err == error.PermissionDenied) {
            return ApplyError.PermissionDenied;
        } else if (err == error.OutOfMemory) {
            return ApplyError.OutOfMemory;
        }
        return ApplyError.ResourceCreationFailed;
    };
    defer allocator.free(tmpdir);
    defer {
        fs.deleteTreeAbsolute(tmpdir) catch |err| {
            log.warn("unable to remove temporary directory {s}: {s}", .{ tmpdir, @errorName(err) });
        };
    }

    // Build the system configuration
    log.print("building the system configuration...\n", .{});

    // Dry activation requires a real build, so --dry-run shouldn't be set
    // if --activate or --boot is set
    const dry_build = args.dry and (build_type == .System);

    // Only use this temporary directory for builds to be activated with
    const tmp_result_dir = try fs.path.join(allocator, &.{ tmpdir, "result" });
    defer allocator.free(tmp_result_dir);

    // Location of the resulting NixOS generation
    var result: []const u8 = undefined;

    var use_nom = args.use_nom or c.apply.use_nom;
    const nom_found = isExectuable("nom");
    if (args.use_nom and !nom_found) {
        log.err("--use-nom was specified, but `nom` is not executable", .{});
        return ApplyError.NixBuildFailed;
    } else if (c.apply.use_nom and !nom_found) {
        log.warn("apply.use_nom is specified in config, but `nom` is not executable", .{});
        log.warn("falling back to `nix` command for building", .{});
        use_nom = false;
    }
    if (opts.flake) {
        result = nixBuildFlake(allocator, build_type, flake_ref, .{
            .build_options = args.build_options.items,
            .flake_options = args.flake_options.items,
            .result_dir = if (args.output) |output|
                output
            else if (build_type == .SystemActivation)
                tmp_result_dir
            else
                null,
            .dry = dry_build,
            .use_nom = use_nom,
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
            .result_dir = if (args.output) |output|
                output
            else if (build_type == .SystemActivation)
                tmp_result_dir
            else
                null,
            .dry = dry_build,
            .use_nom = use_nom,
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
    }

    if (build_type != .SystemActivation) {
        return;
    }

    // Set nix-env profile, if needed
    if (!args.dry) {
        setNixEnvProfile(allocator, args.profile_name, result) catch |err| {
            log.err("failed to set system profile with nix-env", .{});
            return err;
        };
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

    const stc_options = .{
        .install_bootloader = args.install_bootloader,
    };

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
    try runSwitchToConfiguration(allocator, stc, stc_action, stc_options);
}

// Run apply and provide the relevant exit code
pub fn applyMain(allocator: Allocator, args: ApplyArgs) u8 {
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
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
            else => return 1,
        }
    };
    return 0;
}
