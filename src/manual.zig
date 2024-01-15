//! Open the NixOS manual. A replacement for `nixos-help`.

const std = @import("std");
const mem = std.mem;
const os = std.os;
const Allocator = mem.Allocator;

const Constants = @import("constants.zig");

const log = @import("log.zig");

const utils = @import("utils.zig");
const fileExistsAbsolute = utils.fileExistsAbsolute;
const isExecutable = utils.isExecutable;

const local_doc_file = "/run/current-system/sw/share/doc/nixos/index.html";

const ManualError = error{
    ExecFailed,
    NoBrowserFound,
    NoDocumentation,
};

fn openManual(allocator: Allocator) !void {
    var browser: ?[]const u8 = null;

    const doc_file = blk: {
        if (!fileExistsAbsolute(local_doc_file)) {
            log.warn("local documentation is not available, opening manual for current NixOS stable version", .{});
            break :blk "https://nixos.org/manual/nixos/stable";
        }
        break :blk local_doc_file;
    };

    var browsers = mem.tokenizeScalar(u8, os.getenv("BROWSERS") orelse "", ':');
    while (browsers.next()) |b| {
        if (isExecutable(b)) {
            browser = b;
            break;
        }
    }

    if (browser == null) {
        if (isExecutable("xdg-open")) {
            browser = "xdg-open";
        } else if (isExecutable("w3m")) {
            browser = "w3m";
        } else {
            log.err("unable to locate suitable browser to open manual", .{});
            return ManualError.NoBrowserFound;
        }
    }

    log.info("opening using {s}", .{browser.?});

    const argv = &.{ browser.?, doc_file };

    const err = std.process.execve(allocator, argv, null);
    if (err == error.OutOfMemory) return error.OutOfMemory;
    log.err("unable to exec {s}: {s}", .{ browser.?, @errorName(err) });
    return ManualError.ExecFailed;
}

pub fn manualMain(allocator: Allocator) u8 {
    if (!fileExistsAbsolute(Constants.etc_nixos)) {
        log.err("the manual command is unsupported on non-NixOS systems", .{});
        return 3;
    }

    openManual(allocator) catch |err| {
        switch (err) {
            ManualError.ExecFailed => return 1,
            ManualError.NoBrowserFound, ManualError.NoDocumentation => return 4,
            error.OutOfMemory => {
                log.err("out of memory, cannot continue", .{});
                return 1;
            },
        }
    };
    return 0;
}
