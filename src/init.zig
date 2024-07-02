const std = @import("std");
const builtin = @import("builtin");
const opts = @import("options");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const json = std.json;
const mem = std.mem;
const math = std.math;
const posix = std.posix;
const linux = std.os.linux;
const Allocator = mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

const argparse = @import("argparse.zig");
const argIn = argparse.argIn;
const argIs = argparse.argIs;
const argError = argparse.argError;
const getNextArgs = argparse.getNextArgs;
const ArgParseError = argparse.ArgParseError;

const config = @import("config.zig");

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const KVPair = utils.KVPair;
const fileExistsAbsolute = utils.fileExistsAbsolute;
const readFile = utils.readFile;
const concatStringsSep = utils.concatStringsSep;
const runCmd = utils.runCmd;

const nix = @import("nix");
const NixState = nix.expr.EvalState;

pub const InitConfigCommand = struct {
    dir: ?[]const u8 = null,
    force: bool = false,
    no_fs: bool = false,
    root: ?[]const u8 = null,
    show_hw_config: bool = false,

    const usage =
        \\Initialize a NixOS configuration template.
        \\
        \\Usage:
        \\    nixos init [options]
        \\
        \\Options:
        \\    -d, --dir <NAME>              Directory to write configuration to
        \\    -f, --force                   Force generation of all configuration files
        \\    -n, --no-fs                   Do not generate `fileSystem` option configuration
        \\    -r, --root <DIR>              Treat the given directory as the root directory
        \\    -s, --show-hardware-config    Print hardware config to stdout and exit
        \\
    ;

    pub fn parseArgs(argv: *ArgIterator, parsed: *InitConfigCommand) !?[]const u8 {
        var next_arg: ?[]const u8 = argv.next();
        while (next_arg) |arg| {
            if (argIs(arg, "--dir", "-d")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                parsed.dir = next;
            } else if (argIs(arg, "--help", "-h")) {
                log.print("{s}", .{usage});
                return ArgParseError.HelpInvoked;
            } else if (argIs(arg, "--force", "-f")) {
                parsed.force = true;
            } else if (argIs(arg, "--no-fs", "-n")) {
                parsed.no_fs = true;
            } else if (argIs(arg, "--root", "-r")) {
                const next = (try getNextArgs(argv, arg, 1))[0];
                if (mem.eql(u8, next, "/")) {
                    argError("no need to specify '/' with '--root', it is the default", .{});
                    return ArgParseError.InvalidArgument;
                }
                parsed.root = next;
            } else if (argIs(arg, "--show-hardware-config", "-s")) {
                parsed.show_hw_config = true;
            } else {
                return arg;
            }

            next_arg = argv.next();
        }

        return null;
    }
};

const InitConfigError = error{
    PermissionDenied,
    ResourceAccessFailed,
} || Allocator.Error;

// Return string with double quotes around it. Caller owns returned memory.
fn quote(allocator: Allocator, string: []const u8) ![]u8 {
    return fmt.allocPrint(allocator, "\"{s}\"", .{string});
}

const hw_config_template = @embedFile("./resources/hw_config_template.txt");
const config_template = @embedFile("./resources/config_template.txt");
const flake_template = @embedFile("./resources/flake_template.txt");

const CPUInfo = struct {
    kvm: bool,
    manufacturer: enum { amd, intel, other },
};

fn getCpuInfo(allocator: Allocator) !CPUInfo {
    const cpuinfo_file = try fs.openFileAbsolute("/proc/cpuinfo", .{});
    defer cpuinfo_file.close();

    const cpuinfo = try cpuinfo_file.readToEndAlloc(allocator, math.maxInt(usize));
    var lines = mem.tokenizeScalar(u8, cpuinfo, '\n');

    var result = CPUInfo{
        .kvm = false,
        .manufacturer = .other,
    };

    while (lines.next()) |line| {
        // Check for KVM
        if (mem.startsWith(u8, line, "flags")) {
            if (mem.indexOf(u8, line, "vmx") != null or mem.indexOf(u8, line, "svm") != null) {
                result.kvm = true;
            }
        } else if (mem.startsWith(u8, line, "vendor_id")) {
            if (mem.indexOf(u8, line, "AuthenticAMD") != null) {
                result.manufacturer = .amd;
            } else if (mem.indexOf(u8, line, "GenuineIntel") != null) {
                result.manufacturer = .intel;
            }
        }
    }

    return result;
}

// Find module name of given PCI device path. Caller owns returned memory.
fn findModuleName(allocator: Allocator, path: []const u8) !?[]u8 {
    var module_buf: [posix.PATH_MAX]u8 = undefined;
    const module_filename = try fs.path.join(allocator, &.{ path, "driver/module" });
    defer allocator.free(module_filename);

    if (fileExistsAbsolute(module_filename)) {
        const link = try posix.readlink(module_filename, &module_buf);
        const module = fs.path.basename(link);
        return try allocator.dupe(u8, module);
    }

    return null;
}

// zig fmt: off
// Broadcom STA driver (wl.ko)
const broadcom_sta_devices: []const []const u8 = &.{
    "0x4311", "0x4312", "0x4313", "0x4315",
    "0x4327", "0x4328", "0x4329", "0x432a",
    "0x432b", "0x432c", "0x432d", "0x4353",
    "0x4357", "0x4358", "0x4359", "0x4331",
    "0x43a0", "0x43b1",
};

// Broadcom FullMac driver
const broadcom_fullmac_devices: []const []const u8 = &.{
    "0x43a3", "0x43df", "0x43ec", "0x43d3",
    "0x43d9", "0x43e9", "0x43ba", "0x43bb",
    "0x43bc", "0xaa52", "0x43ca", "0x43cb",
    "0x43cc", "0x43c3", "0x43c4", "0x43c5",
};

// VirtIO SCSI devices
const virtio_scsi_devices: []const []const u8 = &.{
    "0x1004", "0x1048",
};

// Intel 22000BG network devices
const intel_2200bg_devices: []const []const u8 = &.{
    "0x1043", "0x104f", "0x4220",
    "0x4221", "0x4223", "0x4224",
};

// Intel 3945ABG network devices
const intel_3945abg_devices: []const []const u8 = &.{
    "0x4229", "0x4230", "0x4222", "0x4227",
};
// zig fmt: on

const ArrayRefs = struct {
    imports: *ArrayList([]const u8),
    modules: *ArrayList([]const u8),
    module_packages: *ArrayList([]const u8),
    initrd_available: *ArrayList([]const u8),
    attrs: *ArrayList(KVPair),
};

fn pciCheck(allocator: Allocator, path: []const u8, array_refs: ArrayRefs) !void {
    const vendor_filename = try fs.path.join(allocator, &.{ path, "vendor" });
    defer allocator.free(vendor_filename);
    const device_filename = try fs.path.join(allocator, &.{ path, "device" });
    defer allocator.free(device_filename);
    const class_filename = try fs.path.join(allocator, &.{ path, "class" });
    defer allocator.free(class_filename);

    const vendor_contents = readFile(allocator, vendor_filename) catch null;
    const device_contents = readFile(allocator, vendor_filename) catch null;
    const class_contents = readFile(allocator, class_filename) catch null;
    defer {
        if (vendor_contents) |contents| allocator.free(contents);
        if (device_contents) |contents| allocator.free(contents);
        if (class_contents) |contents| allocator.free(contents);
    }

    const vendor = mem.trim(u8, vendor_contents orelse "", "\n");
    const device = mem.trim(u8, device_contents orelse "", "\n");
    const class = mem.trim(u8, class_contents orelse "", "\n");

    const module = findModuleName(allocator, path) catch null;
    if (module) |m| {
        if (mem.startsWith(u8, class, "0x01") // Mass storage controller
        or mem.startsWith(u8, class, "0x0c00") // Firewire controller
        or mem.startsWith(u8, class, "0x0c03")) // USB controller
        {
            try array_refs.initrd_available.append(m);
        }
    }

    // Broadcom devices
    if (mem.eql(u8, vendor, "0x14e4")) {
        // Broadcom STA driver
        for (broadcom_sta_devices) |sta_device| {
            if (mem.eql(u8, device, sta_device)) {
                try array_refs.module_packages.append("config.boot.kernelPackages.broadcom_sta");
                try array_refs.modules.append("wl");
                break;
            }
        } else for (broadcom_fullmac_devices) |fullmac_device| {
            if (mem.eql(u8, device, fullmac_device)) {
                try array_refs.imports.append("(modulesPath + \"/hardware/network/broadcom-43xx.nix\")");
                break;
            }
        }
    }
    // VirtIO SCSI devices
    else if (mem.eql(u8, vendor, "0x1af4")) {
        for (virtio_scsi_devices) |vio_device| {
            if (mem.eql(u8, device, vio_device)) {
                try array_refs.initrd_available.append("virtio_scsi");
                break;
            }
        }
    }
    // Intel devices
    else if (mem.eql(u8, vendor, "0x8086")) {
        for (intel_2200bg_devices) |i2200_device| {
            if (mem.eql(u8, device, i2200_device)) {
                try array_refs.attrs.append(KVPair{
                    .name = "networking.enableIntel2200BGFirmware",
                    .value = "true",
                });
                break;
            }
        } else for (intel_3945abg_devices) |i3945_device| {
            if (mem.eql(u8, device, i3945_device)) {
                try array_refs.attrs.append(KVPair{
                    .name = "networking.enableIntel3945ABGFirmware",
                    .value = "true",
                });
                break;
            }
        }
    }
}

fn usbCheck(allocator: Allocator, path: []const u8, array_refs: ArrayRefs) !void {
    const class_filename = try fs.path.join(allocator, &.{ path, "bInterfaceClass" });
    defer allocator.free(class_filename);
    // const subclass_filename = try fs.path.join(allocator, &.{path, "bInterfaceSubClass"});
    // defer allocator.free(subclass_filename);
    const protocol_filename = try fs.path.join(allocator, &.{ path, "bInterfaceProtocol" });
    defer allocator.free(protocol_filename);

    const class_contents = readFile(allocator, class_filename) catch null;
    // const subclass_contents = readFile(allocator, subclass_filename) catch null;
    const protocol_contents = readFile(allocator, protocol_filename) catch null;
    defer {
        if (class_contents) |contents| allocator.free(contents);
        // if (subclass_contents) |contents| allocator.free(contents);
        if (protocol_contents) |contents| allocator.free(contents);
    }

    const class = mem.trim(u8, class_contents orelse "", "\n");
    const protocol = mem.trim(u8, protocol_contents orelse "", "\n");

    const module = findModuleName(allocator, path) catch null;
    if (module) |m| {
        if (mem.eql(u8, class, "08") // Mass storage controller
        or (mem.eql(u8, class, "03") and mem.eql(u8, protocol, "01")) // Keyboard
        ) {
            try array_refs.initrd_available.append(m);
        }
    }
}

const VirtualizationType = enum {
    oracle,
    parallels,
    qemu,
    kvm,
    bochs,
    hyperv,
    systemd_nspawn,
    none,
    other,
};

fn determineVirtualizationType(allocator: Allocator) VirtualizationType {
    const argv = &.{"systemd-detect-virt"};

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stderr_type = .Ignore,
    }) catch |err| {
        log.warn("unable to run systemd-detect-virt: {s}", .{@errorName(err)});
        return .other;
    };
    defer {
        if (result.stdout) |stdout| allocator.free(stdout);
    }

    const virt_type = mem.trim(u8, result.stdout orelse "", "\n ");
    return if (mem.eql(u8, virt_type, "oracle"))
        .oracle
    else if (mem.eql(u8, virt_type, "parallels"))
        .parallels
    else if (mem.eql(u8, virt_type, "qemu"))
        .qemu
    else if (mem.eql(u8, virt_type, "kvm"))
        .kvm
    else if (mem.eql(u8, virt_type, "bochs"))
        .bochs
    else if (mem.eql(u8, virt_type, "microsoft"))
        .hyperv
    else if (mem.eql(u8, virt_type, "systemd-nspawn"))
        .systemd_nspawn
    else if (mem.eql(u8, virt_type, "none"))
        .none
    else
        .other;
}

fn isLVM(allocator: Allocator) bool {
    const argv = &.{ "lsblk", "-o", "TYPE" };

    const result = runCmd(.{
        .allocator = allocator,
        .argv = argv,
        .stderr_type = .Ignore,
    }) catch |err| {
        log.warn("unable to run lsblk: {s}", .{@errorName(err)});
        return false;
    };
    defer {
        if (result.stdout) |stdout| allocator.free(stdout);
    }

    return mem.indexOf(u8, result.stdout orelse "", "lvm") != null;
}

// Caller owns returned memory.
fn findStableDevPath(allocator: Allocator, device: []const u8) ![]const u8 {
    if (mem.indexOf(u8, device, "/") != 0) {
        return try allocator.dupe(u8, device);
    }

    const device_name = posix.toPosixPath(device) catch return InitConfigError.OutOfMemory;
    var dev_stat: linux.Stat = undefined;
    var errno: usize = linux.stat(&device_name, &dev_stat);
    if (errno > 0) {
        return try allocator.dupe(u8, device);
    }

    // Find if device is in `by-uuid` dir
    const by_uuid_dirname = "/dev/disk/by-uuid";
    var by_uuid_dir = fs.openDirAbsolute(by_uuid_dirname, .{ .iterate = true }) catch |err| {
        log.warn("unable to open {s}: {s}", .{ by_uuid_dirname, @errorName(err) });
        return try allocator.dupe(u8, device);
    };
    defer by_uuid_dir.close();
    var uuid_iter = by_uuid_dir.iterate();
    while (uuid_iter.next() catch |err| {
        log.warn("error iterating {s}: {s}", .{ by_uuid_dirname, @errorName(err) });
        return try allocator.dupe(u8, device);
    }) |entry| {
        const device2_name = try fs.path.joinZ(allocator, &.{ by_uuid_dirname, entry.name });
        defer allocator.free(device2_name);

        var dev2_stat: linux.Stat = undefined;
        errno = linux.stat(device2_name.ptr, &dev2_stat);
        if (errno > 0) {
            return try allocator.dupe(u8, device);
        }

        if (dev_stat.rdev == dev2_stat.rdev) {
            return try fs.path.join(allocator, &.{ by_uuid_dirname, entry.name });
        }
    }

    // Find if device is in `/dev/mapper` (usually a LUKS device)
    const mapper_dirname = "/dev/mapper";
    var mapper_dir = fs.openDirAbsolute(mapper_dirname, .{ .iterate = true }) catch |err| {
        log.warn("unable to open {s}: {s}", .{ mapper_dirname, @errorName(err) });
        return try allocator.dupe(u8, device);
    };
    defer mapper_dir.close();
    var mapper_iter = mapper_dir.iterate();
    while (mapper_iter.next() catch |err| {
        log.err("error iterating {s}: {s}", .{ mapper_dirname, @errorName(err) });
        return try allocator.dupe(u8, device);
    }) |entry| {
        const device2_name = try fs.path.joinZ(allocator, &.{ mapper_dirname, entry.name });
        defer allocator.free(device2_name);

        var dev2_stat: linux.Stat = undefined;
        errno = linux.stat(device2_name.ptr, &dev2_stat);
        if (errno > 0) {
            return try allocator.dupe(u8, device);
        }

        if (dev_stat.rdev == dev2_stat.rdev) {
            return try fs.path.join(allocator, &.{ mapper_dirname, entry.name });
        }
    }

    // Find if device is in `/dev/disk/by-label`. Not preferred, as these can change.
    const by_label_dirname = "/dev/disk/by-label";
    var by_label_dir = fs.openDirAbsolute(by_label_dirname, .{ .iterate = true }) catch |err| {
        log.warn("unable to open {s}: {s}", .{ by_label_dirname, @errorName(err) });
        return try allocator.dupe(u8, device);
    };
    defer by_label_dir.close();
    var by_label_iter = by_label_dir.iterate();
    while (by_label_iter.next() catch |err| {
        log.err("error iterating {s}: {s}", .{ by_label_dirname, @errorName(err) });
        return try allocator.dupe(u8, device);
    }) |entry| {
        const device2_name = try fs.path.joinZ(allocator, &.{ by_label_dirname, entry.name });
        defer allocator.free(device2_name);

        var dev2_stat: linux.Stat = undefined;
        errno = linux.stat(device2_name.ptr, &dev2_stat);
        if (errno > 0) {
            return try allocator.dupe(u8, device);
        }

        if (dev_stat.rdev == dev2_stat.rdev) {
            return try fs.path.join(allocator, &.{ by_label_dirname, entry.name });
        }
    }

    // TODO: check if device is a Stratis pool.

    return try allocator.dupe(u8, device);
}

fn findSwapDevices(allocator: Allocator) ![][]const u8 {
    var devices = ArrayList([]const u8).init(allocator);
    errdefer devices.deinit();

    const swap_info = try readFile(allocator, "/proc/swaps");
    defer allocator.free(swap_info);

    var lines = mem.tokenize(u8, swap_info, "\n");
    _ = lines.next(); // Skip header line
    while (lines.next()) |line| {
        var fields = mem.tokenize(u8, line, " \t");
        const swap_filename = fields.next().?;
        const swap_type = fields.next().?;

        if (mem.eql(u8, swap_type, "partition")) {
            const path = try findStableDevPath(allocator, swap_filename);
            try devices.append(path);
        } else if (mem.eql(u8, swap_type, "file")) {
            // Skip swap files, these are better to be
            // specified in configuration.nix manually
        } else {
            log.warn("unsupported swap type for {s}: {s}, skipping", .{ swap_filename, swap_type });
        }
    }

    return try devices.toOwnedSlice();
}

const Filesystem = struct {
    mountpoint: []const u8,
    device: []const u8,
    fsType: []const u8,
    options: []const []const u8,
    luks: ?struct {
        name: ?[]const u8 = null,
        device: ?[]const u8 = null,
    } = null,

    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.mountpoint);
        allocator.free(self.device);
        allocator.free(self.fsType);
        allocator.free(self.options);
        if (self.luks) |luks| {
            if (luks.name) |name| allocator.free(name);
            if (luks.device) |device| allocator.free(device);
        }
    }
};

/// Check if `subdir` is a subdirectory of `dir`
fn is_subdir(subdir: []const u8, dir: []const u8) bool {
    // A dir is always in root, since dirs are absolute.
    // // Intel 3945ABG network devices
    if (dir.len == 0 or mem.eql(u8, dir, "/")) return true;
    // If the dirs are the same, they are in each other.
    if (mem.eql(u8, subdir, dir)) return true;
    // subdir.len <= dir.len + 1 -> "/home/user/Documents".len < "/home/user/".len
    if (subdir.len <= dir.len + 1) return false;
    // "/home/user" matches, and trails with a /
    return mem.indexOf(u8, subdir, dir) == 0 and subdir[dir.len] == '/';
}

fn findFilesystems(allocator: Allocator, root_dir: []const u8) ![]Filesystem {
    const mount_info = try readFile(allocator, "/proc/self/mountinfo");
    var lines = mem.tokenizeScalar(u8, mount_info, '\n');

    var found_filesystems = std.StringHashMap([]const u8).init(allocator);
    defer found_filesystems.deinit();

    var filesystems = ArrayList(Filesystem).init(allocator);
    errdefer {
        for (filesystems.items) |filesystem| filesystem.deinit(allocator);
        filesystems.deinit();
    }

    var found_luks_devices = std.StringHashMap(void).init(allocator);
    defer found_luks_devices.deinit();

    while (lines.next()) |line| {
        var fields = mem.tokenizeAny(u8, line, " \t");

        _ = fields.next(); // Skip mount ID
        _ = fields.next(); // Skip parent ID

        // st_dev, effective ID to use to determine uniqueness
        const mount_id = fields.next().?;

        // Subpath for mount
        var path = fields.next().?;
        if (mem.eql(u8, path, "/")) path = "";

        const mountpoint_absolute = try mem.replaceOwned(u8, allocator, fields.next().?, "\\040", "");
        defer allocator.free(mountpoint_absolute);

        // Check if mountpoint is directory
        const is_dir = blk: {
            const dirname = try posix.toPosixPath(mountpoint_absolute);
            var stat_buf: linux.Stat = undefined;
            const errno = linux.stat(&dirname, &stat_buf);
            if (errno > 0) {
                break :blk false;
            }
            break :blk linux.S.ISDIR(stat_buf.mode);
        };
        if (!is_dir) continue;

        if (!is_subdir(mountpoint_absolute, root_dir)) continue;
        const mountpoint = if (mem.eql(u8, mountpoint_absolute, root_dir))
            "/"
        else
            mountpoint_absolute[(root_dir.len)..];

        // Mount options
        var mount_options_strings = mem.tokenizeScalar(u8, fields.next().?, ',');
        var mount_options = ArrayList([]const u8).init(allocator);
        defer mount_options.deinit();
        while (mount_options_strings.next()) |option| {
            try mount_options.append(option);
        }

        // Skip special filesystems
        if (is_subdir(mountpoint, "/proc") or
            is_subdir(mountpoint, "/dev") or
            is_subdir(mountpoint, "/sys") or
            is_subdir(mountpoint, "/run") or
            mem.eql(u8, mountpoint, "/var/lib/nfs/rpc_pipefs"))
        {
            continue;
        }

        // Skip irrelevant optional fields
        while (fields.next()) |next| {
            if (mem.eql(u8, next, "-")) break;
        }

        // Filesystem type
        const fs_type = fields.next().?;
        // Device name
        const device_raw = try mem.replaceOwned(u8, allocator, fields.next().?, "\\040", " ");
        defer allocator.free(device_raw);
        var device: []const u8 = try mem.replaceOwned(u8, allocator, device_raw, "\\011", "\t");
        defer allocator.free(device);

        // Superblock options
        var superblock_option_strings = mem.tokenizeScalar(u8, fields.next().?, ',');
        var superblock_options = ArrayList([]const u8).init(allocator);
        defer superblock_options.deinit();
        while (superblock_option_strings.next()) |option| {
            try superblock_options.append(option);
        }

        // Skip read-only Nix store bind mount.
        if (mem.eql(u8, mountpoint, "/nix/store") and
            argIn("ro", mount_options.items) and
            argIn("rw", superblock_options.items))
        {
            continue;
        }

        // Check if `fuse` or `fuseblk` and skip.
        if (mem.eql(u8, fs_type, "fuse") or mem.eql(u8, fs_type, "fuseblk")) {
            log.warn("don't know how to emit `fileSystem` option for FUSE filesystem '{s}'", .{mountpoint});
            continue;
        }

        // Don't emit tmpfs entry for /tmp, because it likely comes from
        // `boot.tmp.useTmpfs` in configuration.nix.
        if (mem.eql(u8, mountpoint, "/tmp") and mem.eql(u8, fs_type, "tmpfs")) {
            continue;
        }

        var extra_options = ArrayList([]const u8).init(allocator);
        defer extra_options.deinit();

        // Check if bind mount
        if (found_filesystems.get(device)) |b| {
            // TODO: check if filesystem is a btrfs subvolume

            const base = if (mem.eql(u8, b, "/")) "" else b;
            const options = try allocator.alloc([]const u8, 1);
            options[0] = "bind";
            try filesystems.append(Filesystem{
                .mountpoint = try allocator.dupe(u8, mountpoint),
                .device = try fs.path.join(allocator, &.{ base, path }),
                .fsType = fs_type,
                .options = options,
            });
            continue;
        }
        try found_filesystems.put(mount_id, mountpoint);

        // check if loopback device
        if (mem.startsWith(u8, device, "/dev/loop")) {
            const endIndex = mem.indexOfScalarPos(u8, device, 9, '/') orelse device.len;
            const loop_number = device[9..endIndex];

            const backer_filename = try fmt.allocPrint(allocator, "/sys/block/loop{s}/loop/backing_file", .{loop_number});
            defer allocator.free(backer_filename);
            const backer_contents = readFile(allocator, backer_filename) catch null;
            if (backer_contents) |backer| {
                allocator.free(device);
                device = backer;
                try extra_options.append("loop");
            }
        }

        // TODO: check if filesystem is a btrfs subvolume

        // TODO: check if Stratis pool

        var filesystem = Filesystem{
            .mountpoint = try allocator.dupe(u8, mountpoint),
            .device = try findStableDevPath(allocator, device),
            .fsType = fs_type,
            .options = try extra_options.toOwnedSlice(),
        };

        const device_name = fs.path.basename(device);
        const is_luks = blk: {
            const filename = try fmt.allocPrintZ(allocator, "/sys/class/block/{s}/dm/uuid", .{device_name});
            defer allocator.free(filename);

            var stat_buf: linux.Stat = undefined;
            const errno = linux.stat(filename, &stat_buf);
            if (errno > 0) {
                break :blk false;
            }

            const contents = readFile(allocator, filename) catch break :blk false;
            defer allocator.free(contents);

            if (mem.startsWith(u8, contents, "CRYPT_LUKS")) {
                break :blk true;
            }

            break :blk false;
        };
        if (is_luks) {
            const slave_device_dirname = try fmt.allocPrint(allocator, "/sys/class/block/{s}/slaves", .{device_name});
            defer allocator.free(slave_device_dirname);

            var slave_device_dir = fs.openDirAbsolute(slave_device_dirname, .{ .iterate = true }) catch |err| blk: {
                log.warn("unable to open {s}: {s}", .{ slave_device_dirname, @errorName(err) });
                break :blk null;
            };
            var slave_name: ?[]const u8 = null;
            var has_one_slave = false;
            if (slave_device_dir) |*dir| {
                defer dir.close();
                var iter = dir.iterate();
                while (iter.next() catch |err| blk: {
                    log.warn("error iterating {s}: {s}", .{ slave_device_dirname, @errorName(err) });
                    break :blk null;
                }) |entry| {
                    if (!has_one_slave and slave_name == null) {
                        has_one_slave = true;
                        slave_name = entry.name;
                    } else if (has_one_slave) {
                        has_one_slave = false;
                        break;
                    }
                }
            }

            if (has_one_slave) {
                const slave_device = try fs.path.join(allocator, &.{ "/dev", slave_name.? });
                defer allocator.free(slave_device);

                const dm_name_filename = try fmt.allocPrint(allocator, "/sys/class/block/{s}/dm/name", .{device_name});
                defer allocator.free(device_name);

                const contents = try readFile(allocator, dm_name_filename);
                const dm_name = mem.trim(u8, contents, "\n");

                const device_path = try findStableDevPath(allocator, slave_device);

                if (found_luks_devices.get(dm_name)) |_| {
                    allocator.free(device_path);
                    allocator.free(dm_name);
                } else {
                    try found_luks_devices.put(dm_name, {});
                    filesystem.luks = .{
                        .name = dm_name,
                        .device = device_path,
                    };
                }
            }
        }

        try filesystems.append(filesystem);
    }

    return try filesystems.toOwnedSlice();
}

// Convert array to a list of concatenated Nix string values
// without dupes. Caller owns returned memory.
fn nixStringList(allocator: Allocator, items: []const []const u8, sep: []const u8) ![]u8 {
    var temp = try allocator.dupe([]const u8, items);
    defer allocator.free(temp);
    mem.sort([]const u8, temp, {}, utils.stringLessThan);

    if (temp.len < 1) return fmt.allocPrint(allocator, "", .{});
    if (temp.len == 1) {
        return try quote(allocator, temp[0]);
    }

    // Determine length of resultant buffer
    var total_len: usize = 0;
    for (temp[0..(temp.len - 1)], 0..) |str, i| {
        if (mem.eql(u8, str, temp[i + 1])) {
            continue;
        }

        total_len += str.len;
        total_len += sep.len;
        total_len += 2; // For string quotes
    }
    total_len += temp[temp.len - 1].len + 2;

    var buf_index: usize = 0;
    var result: []u8 = try allocator.alloc(u8, total_len);
    for (temp[0..(temp.len - 1)], 0..) |str, i| {
        if (mem.eql(u8, str, temp[i + 1])) {
            continue;
        }

        const value = try quote(allocator, str);
        defer allocator.free(value);

        mem.copyForwards(u8, result[buf_index..], value);
        buf_index += value.len;
        mem.copyForwards(u8, result[buf_index..], sep);
        buf_index += sep.len;
    }
    const value = try quote(allocator, temp[temp.len - 1]);
    defer allocator.free(value);
    mem.copyForwards(u8, result[buf_index..], value);

    return result;
}

/// Generate hardware-configuration.nix text.
/// Caller owns returned memory.
// TODO: cleanup allocs properly
fn generateHwConfigNix(allocator: Allocator, args: InitConfigCommand, nix_state: NixState, virt_type: VirtualizationType) ![]const u8 {
    const c = config.getConfig();

    var imports = ArrayList([]const u8).init(allocator);
    defer imports.deinit();

    var initrd_available_modules = ArrayList([]const u8).init(allocator);
    defer initrd_available_modules.deinit();

    var initrd_modules = ArrayList([]const u8).init(allocator);
    defer initrd_modules.deinit();

    var kernel_modules = ArrayList([]const u8).init(allocator);
    defer kernel_modules.deinit();

    var module_packages = ArrayList([]const u8).init(allocator);
    defer module_packages.deinit();

    var attrs = ArrayList(KVPair).init(allocator);
    defer attrs.deinit();
    if (c.init.extra_attrs) |extra_attrs| {
        var it = extra_attrs.iterator();
        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            const value = kv.value_ptr.string;
            try attrs.append(KVPair{
                .name = key,
                .value = value,
            });
        }
    }

    const array_refs = ArrayRefs{
        .imports = &imports,
        .modules = &kernel_modules,
        .module_packages = &module_packages,
        .initrd_available = &initrd_available_modules,
        .attrs = &attrs,
    };

    // Determine `nixpkgs.hostPlatform` using the current system.
    // Initializing a config is inherently impure, so no problems here.
    const nix_context = nix.util.NixContext.init() catch return InitConfigError.OutOfMemory;
    const nix_value = nix_state.evalFromString(nix_context, "builtins.currentSystem", "") catch {
        const err_msg = nix_context.errorMessage(nix_context) catch @panic("unable to read error context");
        log.print("{s}\n", .{err_msg.?});
        return InitConfigError.ResourceAccessFailed;
    };

    const host_system = nix_value.string(allocator, nix_context) catch unreachable;
    defer allocator.free(host_system);

    try attrs.append(KVPair{
        .name = "nixpkgs.hostPlatform",
        .value = try quote(allocator, host_system),
    });

    // Check if KVM is enabled
    const cpuinfo = getCpuInfo(allocator) catch null;
    if (cpuinfo) |info| {
        if (info.kvm) {
            switch (info.manufacturer) {
                .amd => try kernel_modules.append("kvm-amd"),
                .intel => try kernel_modules.append("kvm-intel"),
                else => {},
            }
        }
    }

    // Find all needed kernel modules and packages corresponding to connected PCI devices
    const pci_dirname = "/sys/bus/pci/devices";
    var pci_dir = fs.openDirAbsolute(pci_dirname, .{ .iterate = true }) catch |err| blk: {
        log.err("unable to open {s}: {s}", .{ pci_dirname, @errorName(err) });
        break :blk null;
    };
    if (pci_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const name = try fs.path.join(allocator, &.{ pci_dirname, entry.name });
            defer allocator.free(name);
            pciCheck(allocator, name, array_refs) catch return InitConfigError.ResourceAccessFailed;
        }
    }

    // Find all needed kernel modules and packages corresponding to connected USB devices
    const usb_dirname = "/sys/bus/usb/devices";
    var usb_dir = fs.openDirAbsolute(usb_dirname, .{ .iterate = true }) catch |err| blk: {
        log.warn("unable to open {s}: {s}", .{ usb_dirname, @errorName(err) });
        break :blk null;
    };
    if (usb_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const name = try fs.path.join(allocator, &.{ usb_dirname, entry.name });
            defer allocator.free(name);
            usbCheck(allocator, name, array_refs) catch return InitConfigError.ResourceAccessFailed;
        }
    }

    // Find all needed kernel modules corresponding to connected block devices
    const block_dirname = "/sys/class/block";
    var block_dir = fs.openDirAbsolute(block_dirname, .{ .iterate = true }) catch |err| blk: {
        log.warn("unable to open {s}: {s}", .{ block_dirname, @errorName(err) });
        break :blk null;
    };
    if (block_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const path = try fs.path.join(allocator, &.{ block_dirname, entry.name, "device" });
            defer allocator.free(path);
            const module = findModuleName(allocator, path) catch null;
            if (module) |m| {
                try initrd_available_modules.append(m);
            }
        }
    }

    // Find all needed kernel modules corresponding to connected MMC devices
    const mmc_host_dirname = "/sys/class/mmc_host";
    var mmc_host_dir = fs.openDirAbsolute(mmc_host_dirname, .{ .iterate = true }) catch |err| blk: {
        log.warn("unable to open {s}: {s}", .{ mmc_host_dirname, @errorName(err) });
        break :blk null;
    };
    if (mmc_host_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const path = try fs.path.join(allocator, &.{ mmc_host_dirname, entry.name, "device" });
            defer allocator.free(path);
            const module = findModuleName(allocator, path) catch null;
            if (module) |m| {
                try initrd_available_modules.append(m);
            }
        }
    }

    // Detect bcachefs
    const dev_dir = fs.openDirAbsolute("/dev", .{ .iterate = true }) catch |err| blk: {
        log.warn("unable to open /dev: {s}", .{@errorName(err)});
        break :blk null;
    };
    if (dev_dir) |dir| {
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (mem.startsWith(u8, entry.name, "bcache")) {
                try initrd_available_modules.append("bcache");
                break;
            }
        }
    }

    if (isLVM(allocator)) {
        try initrd_modules.append("dm-snapshot");
    }

    // Add extra VM configuration if current system is virtualized
    switch (virt_type) {
        .oracle => try attrs.append(.{
            .name = "virtualisation.virtualbox.guest.enable",
            .value = "true",
        }),
        .parallels => {
            try attrs.append(.{
                .name = "hardware.parallels.enable",
                .value = "true",
            });
            try attrs.append(.{ .name = "nixpkgs.config.allowUnfreePredicate", .value = "pkg: builtins.elem (lib.getName pkg [ \"prl-tools\" ])" });
        },
        .qemu, .kvm, .bochs => try imports.append("(modulesPath + \"/profiles/qemu-guest.nix\")"),
        .hyperv => try attrs.append(.{
            .name = "virtualisation.hypervGuest.enable",
            .value = "true",
        }),
        .systemd_nspawn => try attrs.append(.{
            .name = "boot.isContainer",
            .value = "true",
        }),
        .none => {
            try imports.append("(modulesPath + \"/installer/scan/not-detected.nix\")");
            if (cpuinfo) |info| {
                switch (info.manufacturer) {
                    .amd => try attrs.append(.{
                        .name = "hardware.cpu.amd.updateMicrocode",
                        .value = "lib.mkDefault config.hardware.enableRedistributableFirmware",
                    }),
                    .intel => try attrs.append(.{
                        .name = "hardware.cpu.intel.updateMicrocode",
                        .value = "lib.mkDefault config.hardware.enableRedistributableFirmware",
                    }),
                    .other => {},
                }
            }
        },
        .other => {},
    }

    // Generate swap device configuration
    const swap_devices = findSwapDevices(allocator) catch |err| blk: {
        log.warn("error finding swap devices: {s}", .{@errorName(err)});
        break :blk try allocator.alloc([]u8, 0);
    };
    defer {
        for (swap_devices) |dev| allocator.free(dev);
        allocator.free(swap_devices);
    }

    var absolute_buf: [posix.PATH_MAX]u8 = undefined;
    const absolute_root = posix.realpath(args.root orelse "/", &absolute_buf) catch |err| {
        log.err("unable to find realpath of root: {s}", .{@errorName(err)});
        return InitConfigError.ResourceAccessFailed;
    };
    const root = if (mem.eql(u8, absolute_root, "/")) "" else absolute_root;

    // Generate configuration entries for mounted filesystems
    const filesystems = if (!args.no_fs)
        findFilesystems(allocator, root) catch try allocator.alloc(Filesystem, 0)
    else
        try allocator.alloc(Filesystem, 0);
    defer {
        for (filesystems) |*filesystem| filesystem.deinit(allocator);
        allocator.free(filesystems);
    }

    var networking_attrs = ArrayList([]const u8).init(allocator);
    defer {
        for (networking_attrs.items) |item| allocator.free(item);
        networking_attrs.deinit();
    }

    const net_dirname = "/sys/class/net";
    var net_dir = fs.openDirAbsolute(net_dirname, .{ .iterate = true }) catch |err| blk: {
        log.warn("unable to open {s}: {s}", .{ net_dirname, @errorName(err) });
        break :blk null;
    };
    if (net_dir) |*dir| {
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (!mem.eql(u8, entry.name, "lo")) {
                const attr = try fmt.allocPrint(allocator, "  # networking.interfaces.{s}.useDHCP = lib.mkDefault true;\n", .{entry.name});
                try networking_attrs.append(attr);
            }
        }
    }

    // Stringify everything!
    const imports_str = try concatStringsSep(allocator, imports.items, "\n    ");
    defer allocator.free(imports_str);
    const initrd_available_modules_str = try nixStringList(allocator, initrd_available_modules.items, " ");
    defer allocator.free(initrd_available_modules_str);
    const initrd_modules_str = try nixStringList(allocator, initrd_modules.items, " ");
    defer allocator.free(initrd_modules_str);
    const kernel_modules_str = try nixStringList(allocator, kernel_modules.items, " ");
    defer allocator.free(kernel_modules_str);
    const module_packages_str = try concatStringsSep(allocator, module_packages.items, " ");
    defer allocator.free(module_packages_str);

    var swap_devices_str: []const u8 = undefined;
    if (swap_devices.len > 0) {
        const swap_device_strings = try allocator.alloc([]const u8, swap_devices.len);
        defer allocator.free(swap_device_strings);

        var i: usize = 0;
        defer {
            var j = i;
            while (j != 0) : (j -= 1) {
                allocator.free(swap_device_strings[j - 1]);
            }
        }

        for (swap_devices, swap_device_strings) |dev, *str| {
            str.* = try fmt.allocPrint(allocator, "{{device = \"{s}\";}}", .{dev});
            i += 1;
        }

        const concated = try concatStringsSep(allocator, swap_device_strings, "\n    ");
        swap_devices_str = try fmt.allocPrint(allocator,
            \\  swapDevices = [
            \\    {s}
            \\  ];
        , .{concated});
    } else {
        swap_devices_str = try fmt.allocPrint(allocator, "", .{});
    }
    defer allocator.free(swap_devices_str);

    var filesystems_str: []const u8 = undefined;
    if (filesystems.len > 0) {
        const fs_strings = try allocator.alloc([]const u8, filesystems.len);
        defer allocator.free(fs_strings);

        for (filesystems, fs_strings) |filesystem, *str| {
            const options = try nixStringList(allocator, filesystem.options, " ");
            defer allocator.free(options);

            if (options.len > 0) {
                str.* = try fmt.allocPrint(allocator,
                    \\  fileSystems."{s}" = {{
                    \\    device = "{s}";
                    \\    fsType = "{s}";
                    \\    options = [{s}];
                    \\  }};
                    \\
                , .{ filesystem.mountpoint, filesystem.device, filesystem.fsType, options });
            } else {
                str.* = try fmt.allocPrint(allocator,
                    \\  fileSystems."{s}" = {{
                    \\    device = "{s}";
                    \\    fsType = "{s}";
                    \\  }};
                    \\
                , .{ filesystem.mountpoint, filesystem.device, filesystem.fsType });
            }
        }
        filesystems_str = try concatStringsSep(allocator, fs_strings, "\n");
    } else {
        filesystems_str = try fmt.allocPrint(allocator, "", .{});
    }
    defer allocator.free(filesystems_str);

    const networking_attrs_str = try concatStringsSep(allocator, networking_attrs.items, "");
    defer allocator.free(networking_attrs_str);

    const extra_attrs_str = blk: {
        const strings = try allocator.alloc([]const u8, attrs.items.len);
        defer allocator.free(strings);
        for (attrs.items, strings) |attr, *str| {
            str.* = try fmt.allocPrint(allocator, "  {s} = {s};", .{ attr.name, attr.value });
        }
        break :blk try concatStringsSep(allocator, strings, "\n");
    };
    defer allocator.free(extra_attrs_str);

    return fmt.allocPrint(allocator, hw_config_template, .{
        imports_str,
        initrd_available_modules_str,
        initrd_modules_str,
        kernel_modules_str,
        module_packages_str,
        filesystems_str,
        swap_devices_str,
        networking_attrs_str,
        extra_attrs_str,
    });
}

/// Generate configuration.nix text.
/// Caller owns returned memory.
fn generateConfigNix(allocator: Allocator, virt_type: VirtualizationType) ![]const u8 {
    const c = config.getConfig().init;

    var bootloader_config: []const u8 = undefined;
    const is_efi = blk: {
        const efi_dirname = "/sys/firmware/efi/efivars";
        var stat_buf: linux.Stat = undefined;
        const errno = linux.stat(efi_dirname, &stat_buf);
        if (errno > 0) {
            break :blk false;
        }
        break :blk linux.S.ISDIR(stat_buf.mode);
    };
    const is_extlinux = blk: {
        const extlinux_dirname = "/boot/extlinux";
        var stat_buf: linux.Stat = undefined;
        const errno = linux.stat(extlinux_dirname, &stat_buf);
        if (errno > 0) {
            break :blk false;
        }
        break :blk linux.S.ISDIR(stat_buf.mode);
    };

    if (is_efi) {
        bootloader_config =
            \\  # Use the systemd-boot EFI bootloader.
            \\  boot.loader.systemd-boot.enable = true;
            \\  boot.loader.efi.canTouchEfiVariables = true;
            \\
        ;
    } else if (is_extlinux) {
        bootloader_config =
            \\  # Use the extlinux bootloader.
            \\  boot.loader.generic-extlinux-compatible.enable = true;
            \\  # Disable GRUB, because NixOS enables it by default.
            \\  boot.loader.grub.enable = false
            \\
        ;
    } else if (virt_type != .systemd_nspawn) {
        bootloader_config =
            \\  # Use the GRUB 2 bootloader.
            \\  boot.loader.grub.enable = true;
            \\  # boot.loader.grub.efiSupport = true;
            \\  # boot.loader.grub.efiInstallAsRemovable = true;
            \\  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
            \\  # Define on which hard drive you want to install Grub.
            \\  # boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only
            \\
        ;
    }

    const xserver_config = if (c.enable_xserver)
        \\  # Enable the X11 windowing system.
        \\  services.xserver.enable = true;
        \\
    else
        \\  # Enable the X11 Windowing system.
        \\  # services.xserver.enable = true; 
        \\
        ;

    return fmt.allocPrint(allocator, config_template, .{
        bootloader_config,
        xserver_config,
        c.desktop_config orelse "",
        c.extra_config orelse "",
    });
}

fn initConfig(allocator: Allocator, args: InitConfigCommand) !void {
    // This is needed by both configuration.nix and
    // hardware-configuration.nix, so it's generated outside.
    const virt_type = determineVirtualizationType(allocator);

    const nix_context = nix.util.NixContext.init() catch return InitConfigError.OutOfMemory;
    defer nix_context.deinit();

    // To generate the hardware config, we need access to the Nix
    // store to determine the current system string with a Nix interpreter.
    const nix_store = nix.store.Store.open(allocator, nix_context, "", .{}) catch {
        const err_msg = nix_context.errorMessage(nix_context) catch @panic("fatal: unable to read error context");
        log.print("{s}\n", .{err_msg.?});
        return InitConfigError.ResourceAccessFailed;
    };
    defer nix_store.deinit();
    const nix_state = nix.expr.EvalState.init(nix_context, nix_store) catch {
        const err_msg = nix_context.errorMessage(nix_context) catch @panic("fatal: unable to read error context");
        log.print("{s}\n", .{err_msg.?});
        return InitConfigError.ResourceAccessFailed;
    };

    // Generate hardware-configuration.nix.
    const hw_config = try generateHwConfigNix(allocator, args, nix_state, virt_type);
    defer allocator.free(hw_config);

    if (args.show_hw_config) {
        const stdout = io.getStdOut().writer();
        stdout.print("{s}", .{hw_config}) catch |err| {
            log.err("unable to print to stdout: {s}", .{@errorName(err)});
            return InitConfigError.ResourceAccessFailed;
        };
        return;
    }

    // Generate configuration.nix
    const config_str = try generateConfigNix(allocator, virt_type);
    defer allocator.free(config_str);

    // Write configurations to disk.
    const root = args.root orelse "/";
    const dir = args.dir orelse "/etc/nixos";

    const hw_nix_filename = try fs.path.join(allocator, &.{ root, dir, "hardware-configuration.nix" });
    defer allocator.free(hw_nix_filename);

    log.info("writing {s}", .{hw_nix_filename});
    const hw_nix_file = fs.createFileAbsolute(hw_nix_filename, .{}) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to open {s}: permission denied", .{hw_nix_filename});
                return InitConfigError.PermissionDenied;
            },
            error.FileNotFound => log.err("unable to open {s}: no such file or directory", .{hw_nix_filename}),
            else => log.err("unable to open {s}: {s}", .{ hw_nix_filename, @errorName(err) }),
        }
        return InitConfigError.ResourceAccessFailed;
    };
    defer hw_nix_file.close();
    _ = hw_nix_file.write(hw_config) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to write config to {s}: permission denied", .{hw_nix_filename});
                return InitConfigError.PermissionDenied;
            },
            else => log.err("unexpected error writing contents to {s}: {s}", .{ hw_nix_filename, @errorName(err) }),
        }
        return InitConfigError.ResourceAccessFailed;
    };

    const config_nix_filename = try fs.path.join(allocator, &.{ root, dir, "configuration.nix" });
    defer allocator.free(config_nix_filename);
    if (fileExistsAbsolute(config_nix_filename)) {
        if (args.force) {
            log.warn("overwriting existing configuration.nix", .{});
        } else {
            log.warn("not overwriting existing configuration.nix", .{});
            return;
        }
    }

    log.info("writing {s}...", .{config_nix_filename});
    const config_nix_file = fs.createFileAbsolute(config_nix_filename, .{}) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to open {s}: permission denied", .{config_nix_filename});
                return InitConfigError.PermissionDenied;
            },
            error.FileNotFound => log.err("unable to open {s}", .{config_nix_filename}),
            else => log.err("unable to open {s}: {s}", .{ config_nix_filename, @errorName(err) }),
        }
        return InitConfigError.ResourceAccessFailed;
    };
    defer config_nix_file.close();
    _ = config_nix_file.write(config_str) catch |err| {
        switch (err) {
            error.AccessDenied => {
                log.err("unable to write config to {s}: permission denied", .{config_nix_filename});
                return InitConfigError.PermissionDenied;
            },
            else => log.err("unexpected error writing contents to {s}: {s}", .{ config_nix_filename, @errorName(err) }),
        }
        return InitConfigError.ResourceAccessFailed;
    };

    const flake_nix_filename = try fs.path.join(allocator, &.{ root, dir, "flake.nix" });
    defer allocator.free(flake_nix_filename);
    if (fileExistsAbsolute(flake_nix_filename)) {
        if (args.force) {
            log.warn("overwriting existing flake.nix", .{});
        } else {
            log.warn("not overwriting existing flake.nix", .{});
            return;
        }
    }

    if (opts.flake) {
        // Use the NixOS version of the currently running system.
        const nixpkgs_input = "\n    nixpkgs.url = \"github:NixOS/nixpkgs/" ++ opts.nixpkgs_version ++ "\";\n";
        const flake_str = try fmt.allocPrint(allocator, flake_template, .{nixpkgs_input});

        log.info("writing {s}...", .{flake_nix_filename});
        const flake_nix_file = fs.createFileAbsolute(flake_nix_filename, .{}) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    log.err("unable to open {s}: permission denied", .{flake_nix_filename});
                    return InitConfigError.PermissionDenied;
                },
                error.FileNotFound => log.err("unable to open {s}", .{flake_nix_filename}),
                else => log.err("unable to open {s}: {s}", .{ flake_nix_filename, @errorName(err) }),
            }
            return InitConfigError.ResourceAccessFailed;
        };
        defer flake_nix_file.close();
        _ = flake_nix_file.write(flake_str) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    log.err("unable to write config to {s}: permission denied", .{flake_nix_filename});
                    return InitConfigError.PermissionDenied;
                },
                else => log.err("unexpected error writing contents to {s}: {s}", .{ flake_nix_filename, @errorName(err) }),
            }
            return InitConfigError.ResourceAccessFailed;
        };
    }
}

pub fn initConfigMain(allocator: Allocator, args: InitConfigCommand) u8 {
    if (builtin.os.tag != .linux) {
        log.err("the init command is unsupported on non-Linux systems");
        return 3;
    }

    initConfig(allocator, args) catch |err| {
        switch (err) {
            InitConfigError.ResourceAccessFailed => return 4,
            InitConfigError.PermissionDenied => return 13,
            Allocator.Error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };
    return 0;
}
