//! This module provides functions for logging output.
//! It is a stripped down version of `std.log`, and
//! does not filter output based on build type.

const std = @import("std");

/// Base logging function with no level. Prints a newline automatically.
fn log(comptime prefix: []const u8, comptime fmt: []const u8, args: anytype) void {
    const real_prefix = prefix ++ (if (prefix.len != 0) ": " else "");

    const stderr = std.io.getStdErr().writer();
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend stderr.print(real_prefix ++ fmt ++ "\n", args) catch return;
}

/// Bare print that gets rid of the `std.debug` prefix,
/// which is clunky.
pub const print = std.debug.print;

/// Pretty-print a command that will be ran.
pub fn cmd(argv: []const []const u8) void {
    print("$ ", .{});
    for (argv) |arg| {
        print("{s} ", .{arg});
    }
    print("\n", .{});
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    log("error", fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    log("warning", fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log("info", fmt, args);
}
