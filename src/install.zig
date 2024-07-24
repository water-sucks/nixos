//! A replacement for `nixos-install`.

const std = @import("std");
const builtin = @import("builtin");
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

const argparse = @import("argparse.zig");
const ArgParseError = argparse.ArgParseError;
const argIs = argparse.argIs;
const argIn = argparse.argIn;
const argError = argparse.argError;
const getNextArgs = argparse.getNextArgs;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const FlakeRef = utils.FlakeRef;
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

pub const InstallCommand = struct {
    /// Use this derivation as the `nixos` channel to copy
    channel: ?[]const u8 = null,
    // Build the NixOS system from the specified flake ref
    flake: ?[]const u8 = null,
    // Do not copy the current system's NixOS channel to the new system
    no_copy_channel: bool = false,
    /// Do not prompt for setting root password
    no_root_passwd: bool = false,
    /// Do not install bootloader
    no_bootloader: bool = false,
    /// Treat this directory as the root for installation (default: /mnt)
    root: ?[]const u8 = null,
    /// Install system from specified system closure
    system: ?[]const u8 = null,

    /// All options passed through to `nix` invocations
    build_options: ArrayList([]const u8),
    /// All options passed through to `nix` invocations that involve flakes
    flake_options: ArrayList([]const u8),
    /// App options passed through to `nix` invocations that involve `flake.lock`
    lock_options: ArrayList([]const u8),

    const Self = @This();

    const usage =
        \\Build and activate a NixOS system from a given configuration.
        \\
        \\Usage:
        \\
    ++ (if (opts.flake)
        \\    nixos install <FLAKE-URI>#<SYSTEM-NAME> [options]
        \\
        \\Arguments:
        \\    <FLAKE-URI>      Flake URI that contains NixOS system to build
        \\    <SYSTEM-NAME>    Name of NixOS system to build
        \\
    else
        \\    nixos install [options]
        \\
    ) ++
        \\
        \\Options:
        \\    -c, --channel <PATH>     Use this derivation as the `nixos` channel to copy
        \\    -h, --help               Show this help menu
        \\        --no-bootloader      Do not install bootloader on device
        \\        --no-channel-copy    Do not copy over the current system's NixOS channel
        \\        --no-root-passwd     Do not prompt for setting root password
        \\    -r, --root <DIR>         Treat this directory as the root for installation
        \\    -s, --system <PATH>      Install system from specified system closure
        \\    -v, --verbose            Show verbose logging
        \\
        \\This command also forwards some Nix options passed here to all relevant Nix
        \\invocations. Check the Nix manual page for more details on what options are
        \\available.
        \\
    ;

    pub fn init(allocator: Allocator) Self {
        return InstallCommand{
            .build_options = ArrayList([]const u8).init(allocator),
            .flake_options = ArrayList([]const u8).init(allocator),
            .lock_options = ArrayList([]const u8).init(allocator),
        };
    }

    /// Parse arguments from the command line and construct a BuildArgs struct
    /// with the provided arguments. Caller owns a BuildArgs instance.
    pub fn parseArgs(argv: *ArgIterator, parsed: *InstallCommand) !?[]const u8 {
        var next_arg: ?[]const u8 = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--channel", "-c")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.channel = next;
            } else if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--no-bootloader", null)) {
                parsed.no_bootloader = true;
            } else if (argIs(arg, "--no-channel-copy", null)) {
                parsed.no_copy_channel = true;
            } else if (argIs(arg, "--no-root-passwd", null)) {
                parsed.no_root_passwd = true;
            } else if (argIs(arg, "--root", "-r")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.root = next;
            } else if (argIs(arg, "--system", "-r")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.system = next;
            } else if (argIn(arg, &.{ "--verbose", "-v", "-vv", "-vvv", "-vvvv", "-vvvvv" })) {
                verbose = true;
                try parsed.build_options.append(arg);
            } else if (argIn(arg, &.{ "--quiet", "--print-build-logs", "-L", "--no-build-output", "-Q", "--show-trace", "--keep-going", "-k", "--keep-failed", "-K", "--fallback", "--refresh", "--repair", "--impure", "--offline", "--no-net" })) {
                try parsed.build_options.append(arg);
            } else if (argIn(arg, &.{ "-I", "--max-jobs", "-j", "--cores", "--substituters", "--log-format" })) {
                const next_args = (try getNextArgs(argv, arg, 1));
                try parsed.build_options.appendSlice(&.{ arg, next_args[0] });
            } else if (argIs(arg, "--option", null)) {
                const next_args = try getNextArgs(argv, arg, 2);
                try parsed.build_options.appendSlice(&.{ arg, next_args[0], next_args[1] });
            } else if (argIn(arg, &.{ "--recreate-lock-file", "--no-update-lock-file", "--no-write-lock-file", "--no-registries", "--commit-lock-file" }) and opts.flake) {
                try parsed.lock_options.append(arg);
            } else if (argIs(arg, "--update-input", null) and opts.flake) {
                const next_args = (try getNextArgs(argv, arg, 1));
                try parsed.lock_options.appendSlice(&.{ arg, next_args[0] });
            } else if (argIs(arg, "--override-input", null) and opts.flake) {
                const next_args = try getNextArgs(argv, arg, 2);
                try parsed.lock_options.appendSlice(&.{ arg, next_args[0], next_args[1] });
            } else {
                if (opts.flake and parsed.flake == null) {
                    parsed.flake = arg;
                } else {
                    return arg;
                }
            }

            next_arg = argv.next();
        }

        if (parsed.channel != null and parsed.no_copy_channel) {
            argError("--channel and --no-copy-channel flags conflict", .{});
            return ArgParseError.ConflictingOptions;
        }

        if (opts.flake and parsed.flake != null) {
            const split = mem.indexOf(u8, parsed.flake.?, "#");
            if (split == null or split == parsed.flake.?.len - 1) {
                argError("missing required argument <SYSTEM-NAME>", .{});
                return ArgParseError.MissingRequiredArgument;
            }
        } else if (opts.flake) {
            argError("missing required arguments <FLAKE-URI>#<SYSTEM-NAME>", .{});
            return ArgParseError.MissingRequiredArgument;
        }

        if (parsed.root) |root| {
            if (!fs.path.isAbsolute(root)) {
                argError("--root must be an absolute path", .{});
                return ArgParseError.InvalidArgument;
            }
        }

        return null;
    }

    pub fn deinit(self: *Self) void {
        self.build_options.deinit();
        self.flake_options.deinit();
        self.lock_options.deinit();
    }
};

// Verbose output
// This is easier than to use a field in InstallArgs and pass it around.
var verbose: bool = false;

pub const InstallError = error{
    BootloaderInstallFailed,
    ConfigurationNotFound,
    CopyChannelFailed,
    InvalidMountpoint,
    NixBuildFailed,
    PermissionDenied,
    ResourceCreationFailed,
    SetNixProfileFailed,
    SetRootPasswordFailed,
} || process.GetEnvMapError || Allocator.Error;

const enable_flake_flags = &.{ "--extra-experimental-features", "nix-command flakes" };

// Global exit status indicator for runCmd, so
// that the correct exit code from a failed command
// can be returned.
var exit_status: u8 = 0;

const channel_directory = Constants.nix_profiles ++ "/per-user/root/channels";

const Options = struct {
    build_options: []const []const u8,
    flake_options: []const []const u8,
    lock_options: []const []const u8,
};

// If any dir has an owner bit set below 5, this will error
// out with the name of the incorrect directory.
fn isValidMountpoint(path: []const u8) !void {
    // Check if mountpoint is directory
    var stat_buf: linux.Stat = undefined;
    var errno = linux.stat(&(try posix.toPosixPath(path)), &stat_buf);
    if (errno > 0) {
        const err = posix.errno(errno);
        switch (err) {
            .NOTDIR,
            .NOENT,
            => log.err("mountpoint {s} is not a directory", .{path}),
            .ACCES => log.err("unable to access {s}: permission denied", .{path}),
            else => log.err("unable to stat {s}: {}", .{ path, err }),
        }
        return InstallError.InvalidMountpoint;
    }

    if (!linux.S.ISDIR(stat_buf.mode)) {
        log.err("mountpoint {s} is not a directory", .{path});
        return InstallError.InvalidMountpoint;
    }

    // Make sure all directories on this path have at least 5
    // for the 'other' bit.
    var components = mem.tokenizeScalar(u8, path, '/');
    while (components.next()) |_| {
        const dirname = path[0..components.index];
        errno = linux.stat(&(try posix.toPosixPath(dirname)), &stat_buf);
        if (errno > 0) {
            log.err("unable to stat {s}: {}", .{ dirname, errno });
        }
        if (stat_buf.mode & linux.S.IRWXO < 5) {
            const incorrect_mode = stat_buf.mode & (linux.S.IRWXU | linux.S.IRWXG | linux.S.IRWXO);
            log.err("path {s} should have permissions 755, but had permissions {o}; consider running `chmod o+rx {s}`.", .{ dirname, incorrect_mode, dirname });
            return InstallError.InvalidMountpoint;
        }
    }
}

// Trust all configured substituters on initial install
const default_extra_substituters = "auto?trusted=1";

fn copyChannel(allocator: Allocator, mountpoint: []const u8, channel_dir: ?[]const u8, build_options: []const []const u8) !void {
    const mountpoint_channel_dir = try fs.path.join(allocator, &.{ mountpoint, channel_directory });
    defer allocator.free(mountpoint_channel_dir);

    const channel_path = if (channel_dir) |dir| try allocator.dupe(u8, dir) else blk: {
        const argv: []const []const u8 = &.{
            "nix-env",
            "-p",
            channel_directory,
            "-q",
            "nixos",
            "--no-name",
            "--out-path",
        };

        const result = runCmd(.{
            .allocator = allocator,
            .argv = argv,
            .stderr_type = .Ignore,
        }) catch break :blk null;

        if (result.status != 0) {
            allocator.free(result.stdout.?);
            break :blk null;
        }

        break :blk result.stdout.?;
    };
    defer if (channel_path) |path| allocator.free(path);

    if (channel_path == null) return;

    var mountpoint_dir = fs.cwd().openDir(mountpoint, .{}) catch |err| {
        log.err("unable to open mountpoint dir: {s}", .{@errorName(err)});
        return InstallError.CopyChannelFailed;
    };
    defer mountpoint_dir.close();

    log.info("copying channel...", .{});

    try mountpoint_dir.makePath(fs.path.dirname(mountpoint_channel_dir).?);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-env", "--store", mountpoint });
    try argv.appendSlice(build_options);
    try argv.appendSlice(&.{ "--extra-substituters", default_extra_substituters });
    try argv.appendSlice(&.{ "-p", mountpoint_channel_dir, "--set", channel_path.?, "--quiet" });

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return InstallError.CopyChannelFailed;

    if (result.status != 0) {
        return InstallError.CopyChannelFailed;
    }

    var defexpr_dir = mountpoint_dir.makeOpenPath("root/.nix-defexpr", .{ .iterate = true }) catch |err| {
        log.err("unable to create .nix-defexpr while copying channel: {s}", .{@errorName(err)});
        return InstallError.CopyChannelFailed;
    };
    defer defexpr_dir.close();

    defexpr_dir.chmod(0o700) catch |err| {
        log.err("unable to chmod .nix-defexpr: {s}", .{@errorName(err)});
        return InstallError.CopyChannelFailed;
    };

    const defexpr_channels_linkname = try fs.path.join(allocator, &.{ mountpoint, "/root/.nix-defexpr/channels" });
    defer allocator.free(defexpr_channels_linkname);

    defexpr_dir.deleteTree("channels") catch |err| {
        log.err("unable to remove existing /root/.nix-defexpr/channels: {s}", .{@errorName(err)});
        return InstallError.CopyChannelFailed;
    };

    posix.symlink(channel_directory, defexpr_channels_linkname) catch |err| {
        log.err("unable to symlink channels directory to .nix-defexpr: {s}", .{@errorName(err)});
    };
}

fn nixBuildFlake(
    allocator: Allocator,
    flake_ref: FlakeRef,
    mountpoint: []const u8,
    options: Options,
    env_map: *process.EnvMap,
) ![]const u8 {
    const target = try fmt.allocPrint(allocator, "{s}#nixosConfigurations.{s}.config.system.build.toplevel", .{ flake_ref.uri, flake_ref.system });
    defer allocator.free(target);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("nix");
    try argv.appendSlice(enable_flake_flags);
    try argv.appendSlice(&.{ "build", target });
    try argv.appendSlice(&.{ "--store", mountpoint });
    try argv.appendSlice(&.{ "--extra-substituters", default_extra_substituters });
    try argv.appendSlice(options.build_options);
    try argv.appendSlice(options.lock_options);
    try argv.appendSlice(&.{ "--no-link", "--print-out-paths" });

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .env_map = env_map,
    }) catch return InstallError.NixBuildFailed;
    errdefer if (result.stdout) |stdout| allocator.free(stdout);

    if (result.status != 0) {
        exit_status = result.status;
        return InstallError.NixBuildFailed;
    }

    return try allocator.dupe(u8, result.stdout.?);
}

fn nixBuild(
    allocator: Allocator,
    config: []const u8,
    mountpoint: []const u8,
    options: Options,
    env_map: *process.EnvMap,
) ![]const u8 {
    const nixos_config_argstr = try fmt.allocPrint(allocator, "nixos-config={s}", .{config});
    defer allocator.free(nixos_config_argstr);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("nix-build");
    try argv.appendSlice(&.{ "--store", mountpoint });
    try argv.appendSlice(options.build_options);
    try argv.appendSlice(&.{ "--extra-substituters", default_extra_substituters });
    try argv.appendSlice(&.{ "<nixpkgs/nixos>", "-A", "system" });
    try argv.appendSlice(&.{ "-I", nixos_config_argstr });
    try argv.append("--no-out-link");

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .env_map = env_map,
    }) catch return InstallError.NixBuildFailed;
    errdefer if (result.stdout) |stdout| allocator.free(stdout);

    if (result.status != 0) {
        exit_status = result.status;
        return InstallError.NixBuildFailed;
    }

    return try allocator.dupe(u8, result.stdout.?);
}

fn setNixEnvProfile(allocator: Allocator, mountpoint: []const u8, build_options: []const []const u8, system: []const u8) !void {
    const profile = try fs.path.join(allocator, &.{ mountpoint, Constants.nix_profiles, "system" });
    defer allocator.free(profile);

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "nix-env", "--store", mountpoint });
    try argv.appendSlice(build_options);
    try argv.appendSlice(&.{ "--extra-substituters", default_extra_substituters });
    try argv.appendSlice(&.{ "-p", profile, "--set", system });

    if (verbose) log.cmd(argv.items);

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return InstallError.SetNixProfileFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return InstallError.SetNixProfileFailed;
    }
}

// Template script to run inside `nixos enter`
const bootloader_template =
    // Create a bind mount for each of the mount points inside the target file
    // system. This preserves the validity of their absolute paths after changing
    // the root with `nixos-enter`.
    // Without this the bootloader installation may fail due to options that
    // contain paths referenced during evaluation, like initrd.secrets.
    // when not root, re-execute the script in an unshared namespace.
    \\mount --rbind --mkdir / '{s}'
    \\mount --make-rslave '{s}'
    \\/run/current-system/bin/switch-to-configuration boot
    \\umount -R '{s}' && rmdir '{s}'
;

fn installBootloader(allocator: Allocator, root: []const u8) !void {
    const bootloader_script = try fmt.allocPrint(allocator, bootloader_template, .{ root, root, root, root });
    defer allocator.free(bootloader_script);

    const mtab_location = try fs.path.join(allocator, &.{ root, "/etc/mtab" });
    defer allocator.free(mtab_location);

    posix.symlink("/proc/mounts", mtab_location) catch |err| {
        if (err != error.PathAlreadyExists) {
            log.err("unable to symlink /proc/mounts to {s}: {s}; this is required for bootloader installation.", .{
                mtab_location, @errorName(err),
            });
            return InstallError.ResourceCreationFailed;
        }
    };

    var orig_args = process.args();
    const argv: []const []const u8 = &.{
        orig_args.next().?,
        "enter",
        "--root",
        root,
        "-c",
        bootloader_script,
    };

    if (verbose) log.cmd(argv);

    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();
    try env_map.put("NIXOS_INSTALL_BOOTLOADER", "1");

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = &env_map,
        .stdout_type = .Inherit,
    }) catch return InstallError.BootloaderInstallFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return InstallError.BootloaderInstallFailed;
    }
}

fn setRootPassword(allocator: Allocator, mountpoint: []const u8) !void {
    var orig_args = process.args();
    const argv: []const []const u8 = &.{
        orig_args.next().?,
        "enter",
        "--root",
        mountpoint,
        "-c",
        "/nix/var/nix/profiles/system/sw/bin/passwd",
    };

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stdin_type = .Inherit,
    }) catch return InstallError.SetRootPasswordFailed;

    if (result.status != 0) {
        exit_status = result.status;
        return InstallError.SetRootPasswordFailed;
    }
}

fn install(allocator: Allocator, args: InstallCommand) InstallError!void {
    const options = .{
        .build_options = args.build_options.items,
        .flake_options = args.flake_options.items,
        .lock_options = args.lock_options.items,
    };

    const root_arg = args.root orelse "/mnt";
    var mountpoint_buf: [posix.PATH_MAX]u8 = undefined;
    const mountpoint = utils.followSymlink(root_arg, &mountpoint_buf) catch |err| {
        log.err("unable to determine real path of {s}: {s}", .{ root_arg, @errorName(err) });
        return InstallError.ConfigurationNotFound;
    };

    isValidMountpoint(mountpoint) catch return InstallError.InvalidMountpoint;

    // Create temporary directory for building system in.
    // This will use the filesystem, to avoid any out of space errors
    // if building off a tmpfs, netboot image or something similar.
    const tmpdir_base = try fs.path.join(allocator, &.{ mountpoint, "system" });
    defer allocator.free(tmpdir_base);
    const tmpdir_name = utils.mkTmpDir(allocator, tmpdir_base) catch |err| {
        if (err == error.PermissionDenied) {
            return InstallError.PermissionDenied;
        } else if (err == error.OutOfMemory) {
            return InstallError.OutOfMemory;
        }
        return InstallError.ResourceCreationFailed;
    };
    defer fs.cwd().deleteTree(tmpdir_name) catch {
        log.warn("unable to remove temporary directory {s}, please remove manually", .{tmpdir_base});
    };

    const out_link = try fs.path.join(allocator, &.{ tmpdir_name, "system" });
    defer allocator.free(out_link);

    // Use this temporary directory for Nix-built artifacts
    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();
    if (env_map.get("TMPDIR") == null) {
        try env_map.put("TMPDIR", out_link);
    }

    var result: []const u8 = undefined;

    // Find configuration and build it
    if (opts.flake) {
        const ref = FlakeRef.fromSlice(args.flake.?);

        if (!args.no_copy_channel) {
            copyChannel(allocator, mountpoint, args.channel, args.build_options.items) catch |err| {
                log.err("unable to copy channel: {s}", .{@errorName(err)});
                return InstallError.CopyChannelFailed;
            };
        }

        if (args.system == null) {
            log.info("building the flake in {s}", .{ref.uri});
            result = nixBuildFlake(allocator, ref, mountpoint, options, &env_map) catch |err| {
                log.err("failed to build the system configuration", .{});
                if (err == error.OutOfMemory) {
                    return InstallError.OutOfMemory;
                }
                return InstallError.NixBuildFailed;
            };
        }
    } else {
        const nixos_config_var = posix.getenv("NIXOS_CONFIG");
        if (nixos_config_var) |config| {
            if (!mem.startsWith(u8, config, "/")) {
                log.err("NIXOS_CONFIG is not an absolute path", .{});
                return InstallError.ConfigurationNotFound;
            }
        }
        const config_file = nixos_config_var orelse try fs.path.join(allocator, &.{ mountpoint, "/etc/nixos/configuration.nix" });
        defer if (nixos_config_var == null) allocator.free(config_file);
        fs.cwd().access(config_file, .{}) catch {
            log.err("configuration not found at {s}", .{config_file});
            return InstallError.ConfigurationNotFound;
        };

        if (!args.no_copy_channel) {
            copyChannel(allocator, mountpoint, args.channel, args.build_options.items) catch |err| {
                log.err("unable to copy channel: {s}", .{@errorName(err)});
                return InstallError.CopyChannelFailed;
            };
        }

        if (args.system == null) {
            log.info("building the configuration in {s}", .{config_file});
            result = nixBuild(allocator, config_file, mountpoint, options, &env_map) catch |err| {
                log.err("failed to build the system configuration", .{});
                if (err == error.OutOfMemory) {
                    return InstallError.OutOfMemory;
                }
                return InstallError.NixBuildFailed;
            };
        }
    }

    defer if (args.system == null) allocator.free(result);

    const system = args.system orelse result;

    // Set initial system profile for install
    try setNixEnvProfile(allocator, mountpoint, args.build_options.items, system);

    var mountpoint_dir = fs.cwd().openDir(mountpoint, .{}) catch |err| {
        log.err("unable to open {s}: {s}", .{ mountpoint, @errorName(err) });
        return InstallError.ResourceCreationFailed;
    };
    defer mountpoint_dir.close();
    mountpoint_dir.makeDir("etc") catch |err| {
        if (err != error.PathAlreadyExists) {
            log.err("unable to create {s}/etc: {s}", .{ mountpoint, @errorName(err) });
            return InstallError.ResourceCreationFailed;
        }
    };
    const file = mountpoint_dir.createFile("etc/NIXOS", .{}) catch |err| {
        log.err("unable to create file {s}/etc/NIXOS: {s}", .{ mountpoint, @errorName(err) });
        return InstallError.ResourceCreationFailed;
    };
    file.close();

    if (!args.no_bootloader) {
        log.info("installing the bootloader...", .{});
        try installBootloader(allocator, mountpoint);
    }

    if (!args.no_root_passwd and std.io.getStdIn().isTty()) {
        log.info("setting root password...", .{});
        setRootPassword(allocator, mountpoint) catch |err| {
            log.err("setting root password failed", .{});
            log.print("You can set the root password manually by executing `nixos enter --root {s}` and then running `passwd` in the shell of them new system", .{mountpoint});
            return err;
        };
    }
}

// Run apply and provide the relevant exit code
pub fn installMain(allocator: Allocator, args: InstallCommand) u8 {
    if (builtin.os.tag != .linux or !fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the install command is currently unsupported on non-NixOS systems", .{});
        return 3;
    }

    install(allocator, args) catch |err| {
        switch (err) {
            InstallError.NixBuildFailed, InstallError.SetNixProfileFailed, InstallError.CopyChannelFailed, InstallError.ConfigurationNotFound, InstallError.BootloaderInstallFailed, InstallError.SetRootPasswordFailed => {
                return if (exit_status != 0) exit_status else 1;
            },
            InstallError.PermissionDenied => return 13,
            InstallError.ResourceCreationFailed => return 4,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
            else => return 1,
        }
    };
    return 0;
}
