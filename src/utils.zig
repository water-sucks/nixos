//! Various functions to make life easier but don't fit into any specific
//! category.

const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ChildProcess = std.ChildProcess;
const EnvMap = std.process.EnvMap;

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

/// A semi-convenient wrapper to run a system command.
/// Caller owns `ExecError.stdout` if it succeeds.
pub fn runCmd(
    args: struct {
        allocator: Allocator,
        argv: []const []const u8,
        stdout_type: ChildProcess.StdIo = .Pipe,
        stderr_type: ChildProcess.StdIo = .Inherit,
        env_map: ?*const EnvMap = null,
        max_output_bytes: usize = 50 * 1024,
    },
) ExecError!ExecResult {
    var child = ChildProcess.init(args.argv, args.allocator);

    child.stdin_behavior = .Ignore;
    child.stderr_behavior = args.stderr_type;
    child.stdout_behavior = args.stdout_type;

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

/// Check if a file exists by opening and closing it.
pub fn fileExistsAbsolute(filename: []const u8) bool {
    var file = fs.openFileAbsolute(filename, .{}) catch return false;
    file.close();
    return true;
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
