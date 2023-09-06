//! Run command(s) in a NixOS chroot environment
//! A replacement for `nixos-enter`

const std = @import("std");
const builtin = @import("builtin");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const linux = os.linux;
const process = std.process;

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArgIterator = process.ArgIterator;

const argparse = @import("argparse.zig");
const argIs = argparse.argIs;
const getNextArgs = argparse.getNextArgs;
const ArgParseError = argparse.ArgParseError;

const log = @import("log.zig");

const utils = @import("utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const runCmd = utils.runCmd;

const NIXOS_REEXEC = "_NIXOS_ENTER_REEXEC";

pub const EnterArgs = struct {
    // Command to execute in Bash
    command: ?[]const u8 = null,
    // Path to the NixOS system root to enter (default: /mnt)
    root: ?[]const u8 = null,
    // Suppress all system activation output
    silent: bool = false,
    // Print verbose info about setup
    verbose: bool = false,
    // NixOS system configuration to activate (default: /nix/var/nix/profiles/system)
    system: ?[]const u8 = null,

    // Args passed after --
    command_args: ArrayList([]const u8),

    const Self = @This();

    const usage =
        \\Usage:
        \\    nixos enter [options]
        \\
        \\Options:
        \\    -c, --command    Command to execute in Bash
        \\    -r, --root       Path to the NixOS system root to enter (default: /mnt)
        \\    -s, --silent     Suppress all system activation output
        \\    --system         NixOS system configuration to activate (default:
        \\                     /nix/var/nix/profiles/system)
        \\    -v, --verbose    Print verbose info about setup
        \\    --               Interpret the remaining args as the command to be invoked
        \\
    ;

    fn init(allocator: Allocator) Self {
        return EnterArgs{
            .command_args = ArrayList([]const u8).init(allocator),
        };
    }

    pub fn parseArgs(allocator: Allocator, args: *ArgIterator) !EnterArgs {
        var result: EnterArgs = EnterArgs.init(allocator);
        errdefer result.deinit();

        var next_arg: ?[]const u8 = args.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--command", "-c")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                result.command = next;
            } else if (argIs(arg, "--root", "-r")) {
                const next = (try getNextArgs(args, arg, 1))[0];
                result.command = next;
            } else if (argIs(arg, "--silent", "-s")) {
                result.silent = true;
            } else if (argIs(arg, "--help", "-h")) {
                log.print(usage, .{});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--verbose", "-v")) {
                result.verbose = true;
            } else if (mem.eql(u8, arg, "--")) {
                // Append rest of command args to list and break
                while (args.next()) |a| {
                    try result.command_args.append(a);
                }
                break;
            } else {
                log.print("{s}\n", .{usage});
                log.err("unrecognised flag {s}", .{arg});
                return ArgParseError.InvalidArgument;
            }

            next_arg = args.next();
        }

        if (result.command_args.items.len != 0 and result.command != null) {
            log.err("cannot specify both --command and --", .{});
            return ArgParseError.ConflictingOptions;
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.command_args.deinit();
    }
};

const EnterError = error{
    ActivationError,
    ChrootError,
    MountFailed,
    PermissionDenied,
    UnshareError,
    UnsupportedOs,
};

var verbose: bool = false;
var exit_status: u8 = 0;

/// Create private namespace for chroot process (TODO: should this call out to
/// unshare command, or be implemented by itself with the syscalls?)
fn unshare(allocator: Allocator) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "unshare", "--fork", "--mount", "--uts", "--mount-proc", "--pid" });

    // Map root user if not running as root
    if (os.linux.geteuid() != 0) {
        try argv.append("-r");
    }

    try argv.append("--");

    // append rest of args to command
    var it = try process.argsWithAllocator(allocator);
    while (it.next()) |arg| {
        try argv.append(arg);
    }

    if (verbose) {
        log.info("replacing process with unshare", .{});
        log.cmd(argv.items);
    }

    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();
    try env_map.put(NIXOS_REEXEC, "1");

    process.execve(allocator, argv.items, &env_map) catch {
        return EnterError.UnshareError;
    };
}

// Bind mount a directory in / to a directory in mountpoint.
fn bindMount(allocator: Allocator, mountpoint: []const u8, dir: []const u8) !void {
    const dirname = try fmt.allocPrintZ(allocator, "{s}/{s}", .{ mountpoint, dir });
    defer allocator.free(dirname);

    os.mkdir(dirname, 0o755) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                // This warning is kind of annoying because those directories
                // usually exist, but are empty, so only show it while verbose.
                if (verbose) log.warn("{s} already exists", .{dirname});
            },
            else => {
                log.err("creating {s} failed: {s}", .{ dirname, @errorName(err) });
                return EnterError.PermissionDenied;
            },
        }
    };

    const root_dirname = try fmt.allocPrintZ(allocator, "/{s}", .{dir});
    defer allocator.free(root_dirname);

    const errno = linux.mount(root_dirname, dirname.ptr, "", linux.MS.BIND | linux.MS.REC, 0);
    switch (os.errno(errno)) {
        .SUCCESS => if (verbose) log.info("bind-mounted /{s} successfully", .{dir}),
        .PERM => {
            log.err("mounting /{s} failed: permission denied", .{dir});
            return EnterError.PermissionDenied;
        },
        else => {
            log.err("mount error while mounting /{s}: {d}\n", .{ dir, os.errno(errno) });
            exit_status = @truncate(errno);
            return EnterError.MountFailed;
        },
    }
}

// Get the location at which to bind-mount resolv.conf.
// Caller owns returned memory.
fn getResolvConfLocation(allocator: Allocator, mountpoint: []const u8) ![:0]const u8 {
    const target_resolv_conf = try fmt.allocPrint(allocator, "{s}/etc/resolv.conf", .{mountpoint});
    defer allocator.free(target_resolv_conf);

    var created: bool = false;

    var trc_handle: std.fs.File = blk: {
        var file = fs.openFileAbsolute(target_resolv_conf, .{}) catch |err| {
            if (err == error.FileNotFound) {
                var new_file = try fs.createFileAbsolute(target_resolv_conf, .{});
                created = true;
                break :blk new_file;
            } else {
                return err;
            }
        };
        break :blk file;
    };
    defer trc_handle.close();

    if (created) {
        return allocator.dupeZ(u8, target_resolv_conf);
    }

    const is_symlink = (try trc_handle.metadata()).kind() == .sym_link;
    if (is_symlink) {
        var path_buf: [os.PATH_MAX]u8 = undefined;
        const real_location = try os.realpath(target_resolv_conf, &path_buf);

        var path_builder = ArrayList([]const u8).init(allocator);
        defer path_builder.deinit();

        try path_builder.append(mountpoint);
        if (!mem.startsWith(u8, real_location, "/")) {
            try path_builder.append("etc");
        }
        try path_builder.append(real_location);

        return fs.path.joinZ(allocator, path_builder.items);
    }

    return allocator.dupeZ(u8, target_resolv_conf);
}

// Run the NixOS activation script for the specified system configuration.
fn activate(allocator: Allocator, root: []const u8, system: []const u8, silent: bool) !void {
    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();

    const locale_archive = try fmt.allocPrint(allocator, "{s}/sw/lib/locale/locale-archive", .{system});
    defer allocator.free(locale_archive);

    try env_map.put("LOCALE_ARCHIVE", locale_archive);
    try env_map.put("IN_NIXOS_ENTER", "1");

    const activate_script = try fmt.allocPrint(allocator, "{s}/activate", .{system});

    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.appendSlice(&.{ "chroot", root, activate_script });

    if (verbose) log.cmd(argv.items);

    // Run activations script for reals; ignore errors because why not ig
    _ = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .env_map = &env_map,
        .stdout_type = if (silent) .Ignore else .Inherit,
        .stderr_type = if (silent) .Ignore else .Inherit,
    }) catch return EnterError.ActivationError;

    argv.clearAndFree();

    const systemd_tmpfiles = try fmt.allocPrint(allocator, "{s}/sw/bin/systemd-tmpfiles", .{system});
    defer allocator.free(systemd_tmpfiles);

    try argv.appendSlice(&.{ "chroot", root, systemd_tmpfiles, "--create", "--remove", "-E" });
    if (verbose) log.cmd(argv.items);

    _ = runCmd(.{
        .allocator = allocator,
        .argv = argv.items,
        .stderr_type = .Ignore,
        .stdout_type = .Ignore,
    }) catch return EnterError.ActivationError;
}

fn startChroot(allocator: Allocator, root: []const u8, args: []const []const u8) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "chroot", root });
    try argv.appendSlice(args);

    if (verbose) log.cmd(argv.items);

    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();

    // unset TMPDIR
    env_map.remove("TMPDIR");

    process.execve(allocator, argv.items, &env_map) catch return EnterError.ChrootError;
}

fn enter(allocator: Allocator, raw_args: *ArgIterator) !void {
    var args = try EnterArgs.parseArgs(allocator, raw_args);
    defer args.deinit();

    // Just for cleanliness's sake in other functions
    if (args.verbose) {
        verbose = true;
    }

    // Re-exec current process in private namespace with unshare
    const is_reexec = (os.getenv(NIXOS_REEXEC) orelse "").len != 0;
    if (!is_reexec) {
        unshare(allocator) catch |err| {
            log.err("unable to unshare: {s}", .{@errorName(err)});
            return EnterError.UnshareError;
        };
    }

    if (verbose) log.info("unshared successfully", .{});

    // Recursively mount root as private
    if (verbose) log.info("remounting root privately for namespace", .{});

    var errno = linux.mount("/", "/", "", linux.MS.REMOUNT | linux.MS.PRIVATE | linux.MS.REC, 0);
    switch (os.errno(errno)) {
        .SUCCESS => if (verbose) log.info("remounted root successfully", .{}),
        .PERM => {
            log.err("mount failed: permission denied", .{});
            return EnterError.PermissionDenied;
        },
        else => {
            log.err("mount error while remounting root: {d}\n", .{os.errno(errno)});
            exit_status = @truncate(errno);
            return EnterError.MountFailed;
        },
    }

    // Check if mountpoint is valid NixOS system
    var mountpoint_buffer: [os.PATH_MAX]u8 = undefined;
    const mountpoint = try os.realpath(args.root orelse "/mnt", &mountpoint_buffer);

    const mountpoint_is_nixos = blk: {
        const filename = try fmt.allocPrint(allocator, "{s}/etc/NIXOS", .{mountpoint});
        defer allocator.free(filename);
        break :blk fileExistsAbsolute(filename);
    };
    if (!mountpoint_is_nixos) {
        log.err("mountpoint {s} is not a valid NixOS system", .{mountpoint});
        return EnterError.UnsupportedOs;
    }

    // Recursively bind mount current /dev and /proc to mountpoint
    if (verbose) log.info("bind-mounting /dev and /proc to {s}", .{mountpoint});
    try bindMount(allocator, mountpoint, "dev");
    try bindMount(allocator, mountpoint, "proc");

    // Bind mount resolv.conf from current system to root if it exists
    if (fileExistsAbsolute("/etc/resolv.conf")) {
        if (verbose) log.info("bind-mounting /etc/resolv.conf for Internet access", .{});
        const resolv_conf = getResolvConfLocation(allocator, mountpoint) catch |err| {
            log.err("failed to determine where to mount resolv.conf: {s}", .{@errorName(err)});
            return EnterError.MountFailed;
        };
        defer allocator.free(resolv_conf);

        errno = linux.mount("/etc/resolv.conf", resolv_conf, "", linux.MS.BIND, 0);
        switch (os.errno(errno)) {
            .SUCCESS => if (verbose) log.info("bind-mounted resolv.conf successfully", .{}),
            .PERM => {
                log.err("mounting resolv.conf failed: permission denied", .{});
                return EnterError.PermissionDenied;
            },
            else => {
                log.err("mount error while mounting resolv.conf /: {d}\n", .{os.errno(errno)});
                exit_status = @truncate(errno);
                return EnterError.MountFailed;
            },
        }
    }

    const system = args.system orelse "/nix/var/nix/profiles/system";

    try activate(allocator, mountpoint, system, args.silent);

    // Chroot into system and execve specified command
    if (verbose) log.info("entering chroot environment", .{});

    const bash = try fmt.allocPrint(allocator, "{s}/sw/bin/bash", .{system});
    defer allocator.free(bash);

    if (args.command) |command| {
        try startChroot(allocator, mountpoint, &.{ bash, "-c", command });
    } else if (args.command_args.items.len > 0) {
        try startChroot(allocator, mountpoint, args.command_args.items);
    } else {
        try startChroot(allocator, mountpoint, &.{ bash, "--login" });
    }
}

pub fn enterMain(allocator: Allocator, args: *ArgIterator) u8 {
    if (builtin.os.tag != .linux) {
        log.err("the enter command is unsupported on non-Linux systems", .{});
        return 3;
    }

    enter(allocator, args) catch |err| {
        switch (err) {
            ArgParseError.HelpInvoked => return 0,
            EnterError.MountFailed => return exit_status,
            EnterError.PermissionDenied => return 13,
            EnterError.UnsupportedOs => return 1,
            EnterError.UnshareError => return 2,
            else => |e| {
                log.err("unhandled error: {s}", .{@errorName(e)});
            },
        }
    };

    return 0;
}
