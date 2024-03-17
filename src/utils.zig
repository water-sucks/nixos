//! Various functions to make life easier but don't fit into any specific
//! category.

const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;
const process = std.process;

const log = @import("./log.zig");

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ChildProcess = std.ChildProcess;
const EnvMap = std.process.EnvMap;

/// Print to a writer, ignoring errors.
pub fn print(out: anytype, comptime format: []const u8, args: anytype) void {
    out.print(format, args) catch return;
}
/// Print to a writer with a newline, ignoring errors.
pub fn println(out: anytype, comptime format: []const u8, args: anytype) void {
    out.print(format ++ "\n", args) catch return;
}

/// Result from a command; output of commands meant for
/// the user will always be on stderr, and the stdout will
/// always be captured into a string.
pub const ExecResult = struct {
    status: u8, // Numerical status of the command
    stdout: ?[]const u8, // Trimmed stdout output of the command
};

pub const ExecError = os.GetCwdError || os.ReadError || ChildProcess.SpawnError || os.PollError || error{
    StdoutStreamTooLong,
    StderrStreamTooLong,
};

// Return a help string or empty space depending on a condition.
pub fn optionalArgString(comptime cond: bool, comptime help: []const u8) []const u8 {
    return if (cond)
        fmt.comptimePrint(
            \\
            \\{s}
            \\
        , .{help})
    else
        \\
        \\
        ;
}

/// A semi-convenient wrapper to run a system command.
/// Caller owns `ExecError.stdout` if it succeeds.
pub fn runCmd(
    args: struct {
        allocator: Allocator,
        argv: []const []const u8,
        stdout_type: ChildProcess.StdIo = .Pipe,
        stderr_type: ChildProcess.StdIo = .Inherit,
        stdin_type: ChildProcess.StdIo = .Ignore,
        env_map: ?*const EnvMap = null,
        max_output_bytes: usize = 50 * 1024,
    },
) ExecError!ExecResult {
    var child = ChildProcess.init(args.argv, args.allocator);

    child.stdin_behavior = .Ignore;
    child.stderr_behavior = args.stderr_type;
    child.stdout_behavior = args.stdout_type;
    child.stdin_behavior = args.stdin_type;

    child.stderr = io.getStdErr();
    child.env_map = args.env_map;

    try child.spawn();

    var stdout: ?[]const u8 = null;

    var stdout_captured = ArrayList(u8).init(args.allocator);
    errdefer stdout_captured.deinit();

    if (args.stdout_type == .Pipe or args.stderr_type == .Pipe) {
        try collectStdoutPosix(&child, &stdout_captured, args.max_output_bytes);
    }

    const term = try child.wait();

    if (args.stdout_type == .Pipe) {
        stdout = try stdout_captured.toOwnedSlice();
        stdout = mem.trim(u8, stdout.?, "\n");
    }

    var result = ExecResult{
        .stdout = stdout,
        .status = switch (term) {
            .Exited => |status| status,
            .Signal => |status| @truncate(status),
            .Stopped => |status| @truncate(status),
            .Unknown => |status| @truncate(status),
        },
    };

    return result;
}

// Shamelessly copied from Zig STD ChildProcess module and modified so it only
// takes stdout. The implementation of this changes with 0.11, so this should
// be revisited.
fn collectStdoutPosix(
    child: *ChildProcess,
    stdout: *std.ArrayList(u8),
    max_output_bytes: usize,
) !void {
    var poll_fds = [_]os.pollfd{
        .{ .fd = child.stdout.?.handle, .events = os.POLL.IN, .revents = undefined },
    };

    var dead_fds: usize = 0;
    // We ask for ensureTotalCapacity with this much extra space. This has more of an
    // effect on small reads because once the reads start to get larger the amount
    // of space an ArrayList will allocate grows exponentially.
    const bump_amt = 512;

    const err_mask = os.POLL.ERR | os.POLL.NVAL | os.POLL.HUP;

    while (dead_fds < poll_fds.len) {
        const events = try os.poll(&poll_fds, std.math.maxInt(i32));
        if (events == 0) continue;

        var remove_stdout = false;
        // Try reading whatever is available before checking the error
        // conditions.
        // It's still possible to read after a POLL.HUP is received, always
        // check if there's some data waiting to be read first.
        if (poll_fds[0].revents & os.POLL.IN != 0) {
            // stdout is ready.
            const new_capacity = @min(stdout.items.len + bump_amt, max_output_bytes);
            try stdout.ensureTotalCapacity(new_capacity);
            const buf = stdout.unusedCapacitySlice();
            if (buf.len == 0) return error.StdoutStreamTooLong;
            const nread = try os.read(poll_fds[0].fd, buf);
            stdout.items.len += nread;

            // Remove the fd when the EOF condition is met.
            remove_stdout = nread == 0;
        } else {
            remove_stdout = poll_fds[0].revents & err_mask != 0;
        }

        // Exclude the fds that signaled an error.
        if (remove_stdout) {
            poll_fds[0].fd = -1;
            dead_fds += 1;
        }
    }
}

/// NixOS configuration location inside a flake
pub const FlakeRef = struct {
    /// URI of flake that contains NixOS configuration
    uri: []const u8,
    /// Name of system configuration to build
    system: []const u8,

    const Self = @This();

    /// Create a FlakeRef from a `flake#hostname` string.
    pub fn fromSlice(slice: []const u8) Self {
        const index = mem.indexOf(u8, slice, "#");

        if (index) |i| {
            return Self{
                .uri = slice[0..i],
                .system = slice[(i + 1)..],
            };
        }

        return Self{
            .uri = slice,
            .system = "",
        };
    }
};

/// Check if a file exists by opening and closing it.
pub fn fileExistsAbsolute(filename: []const u8) bool {
    var file = fs.openFileAbsolute(filename, .{}) catch return false;
    file.close();
    return true;
}

/// Read file in its entirety into a string buffer.
/// Caller owns returned memory.
pub fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = try fs.openFileAbsolute(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    return contents;
}

/// Compare strings lexicographically to see if one is less than other.
pub fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    const result = mem.order(u8, lhs, rhs);
    return result == .lt;
}

/// Concatenate slice of strings together with a separator
/// in between each string. Caller owns returned memory.
pub fn concatStringsSep(allocator: Allocator, strings: []const []const u8, sep: []const u8) ![]u8 {
    if (strings.len < 1) return fmt.allocPrint(allocator, "", .{});
    if (strings.len == 1) return fmt.allocPrint(allocator, "{s}", .{strings[0]});

    // Determine length of resultant buffer
    var total_len: usize = 0;
    for (strings[0..(strings.len - 1)]) |str| {
        total_len += str.len;
        total_len += sep.len;
    }
    total_len += strings[strings.len - 1].len;

    var buf_index: usize = 0;
    var result: []u8 = try allocator.alloc(u8, total_len);
    for (strings[0..(strings.len - 1)]) |string| {
        mem.copy(u8, result[buf_index..], string);
        buf_index += string.len;
        mem.copy(u8, result[buf_index..], sep);
        buf_index += sep.len;
    }
    mem.copy(u8, result[buf_index..], strings[strings.len - 1]);

    return result;
}

/// Make a temporary directory; this is basically just the `mktemp`
/// command but without actually invoking the `mktemp` command.
pub fn mkTmpDir(allocator: Allocator, base: []const u8) ![]const u8 {
    var random = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rng = random.random();

    var i: usize = 1;
    var random_string: [9]u8 = undefined;
    random_string[0] = '.';
    while (i < 9) : (i += 1) {
        random_string[i] = rng.intRangeAtMost(u8, 'A', 'Z');
    }

    const dirname = try mem.concat(allocator, u8, &.{ base, &random_string });
    errdefer allocator.free(dirname);

    fs.makeDirAbsolute(dirname) catch |err| {
        switch (err) {
            error.AccessDenied => log.err("unable to create temporary directory {s}: permission denied", .{dirname}),
            error.PathAlreadyExists => log.err("unable to create temporary directory {s}: path already exists", .{dirname}),
            error.FileNotFound => log.err("unable to create temporary directory {s}: no such file or directory", .{dirname}),
            error.NoSpaceLeft => log.err("unable to create temporary directory {s}: no space left on device", .{dirname}),
            error.NotDir => log.err("{s} is not a directory", .{base}),
            else => log.err("unexpected error creating temporary directory {s}: {s}", .{ dirname, @errorName(err) }),
        }
        return err;
    };

    return dirname;
}

/// Check if a command is executable by looking it up
/// in the PATH variable.
pub fn isExecutable(command: []const u8) bool {
    const path_var = os.getenv("PATH") orelse return false;

    var buf: [os.PATH_MAX]u8 = undefined;

    var dirnames = mem.tokenizeScalar(u8, path_var, ':');
    while (dirnames.next()) |dirname| {
        const real_dirname = os.realpath(dirname, &buf) catch continue;

        var dir = fs.openDirAbsolute(real_dirname, .{}) catch continue;
        defer dir.close();

        dir.access(command, .{}) catch continue;

        return true;
    }

    return false;
}

/// Re-execute command as root using sudo, if it is found.
/// Does not return.
pub fn execAsRoot(allocator: Allocator) !noreturn {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    const original_args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, original_args);

    try argv.append("sudo");
    try argv.appendSlice(original_args);

    var err = process.execve(allocator, argv.items, null);
    switch (err) {
        error.AccessDenied, error.InvalidExe, error.SystemResources => return err,
        else => {},
    }

    // Also try with doas, just in case.
    argv.items[0] = "doas";

    err = process.execve(allocator, argv.items, null);
    return err;
}
