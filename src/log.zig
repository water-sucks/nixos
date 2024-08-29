//! This module provides functions for logging output.
//! It is a stripped down version of `std.log`, and
//! does not filter output based on build type.

const std = @import("std");
const io = std.io;
const mem = std.mem;

const utils = @import("utils.zig");
const ansi = utils.ansi;
const ANSIFilter = ansi.ANSIFilter;

/// Print to stderr. This makes sure that ANSI codes are handled
/// according to whether or not they are disabled.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    var color_filter = ANSIFilter(@TypeOf(stderr)){ .raw_writer = stderr };
    const writer = color_filter.writer();
    writer.print(fmt, args) catch return;
}

/// Base logging function with no level. Prints a newline automatically.
fn log(comptime prefix: []const u8, comptime fmt: []const u8, args: anytype) void {
    const real_prefix = prefix ++ (if (prefix.len != 0) ": " else "");

    print(real_prefix ++ fmt ++ "\n", args);
}

/// Global step counter. This will increase every single time step() is invoked.
var step_num: usize = 0;

pub fn step(comptime fmt: []const u8, args: anytype) void {
    step_num += 1;

    if (step_num > 1) {
        print("\n", .{});
    }

    print(ansi.BOLD ++ ansi.MAGENTA, .{});

    print("{d}. ", .{step_num});
    print(fmt, args);

    print(ansi.RESET ++ "\n", .{});
}

/// Pretty-print a command that will be ran.
pub fn cmd(argv: []const []const u8) void {
    print(ansi.BLUE, .{});

    print(ansi.BLUE ++ "$ ", .{});
    for (argv) |arg| {
        print("{s} ", .{arg});
    }
    print(ansi.RESET, .{});

    print("\n", .{});
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    log(ansi.BOLD ++ ansi.RED ++ "error" ++ ansi.RESET, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    log(ansi.BOLD ++ ansi.YELLOW ++ "warning" ++ ansi.RESET, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(ansi.GREEN ++ "info" ++ ansi.RESET, fmt, args);
}
