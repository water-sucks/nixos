//! This module provides functions for logging output.
//! It is a stripped down version of `std.log`, and
//! does not filter output based on build type.

const std = @import("std");

const utils = @import("utils.zig");
const ansi = utils.ansi;

const Constants = @import("constants.zig");

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

/// Global step counter. This will increase every single time step() is invoked.
var step_num: usize = 0;

pub fn step(comptime fmt: []const u8, args: anytype) void {
    step_num += 1;

    if (step_num > 1) {
        print("\n", .{});
    }
    if (Constants.use_color) {
        print(ansi.BOLD ++ ansi.MAGENTA, .{});
    }

    print("{d}. ", .{step_num});
    print(fmt, args);

    if (Constants.use_color) {
        print(ansi.RESET, .{});
    }
    print("\n", .{});
}

/// Pretty-print a command that will be ran.
pub fn cmd(argv: []const []const u8) void {
    if (Constants.use_color) {
        print(ansi.BR_BLUE, .{});
    }

    print("$ ", .{});
    for (argv) |arg| {
        print("{s} ", .{arg});
    }

    if (Constants.use_color) {
        print(ansi.RESET, .{});
    }

    print("\n", .{});
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (Constants.use_color) {
        log(ansi.BOLD ++ ansi.RED ++ "error" ++ ansi.RESET, fmt, args);
    } else {
        log("error", fmt, args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (Constants.use_color) {
        log(ansi.BOLD ++ ansi.YELLOW ++ "warning" ++ ansi.RESET, fmt, args);
    } else {
        log("warning", fmt, args);
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (Constants.use_color) {
        log(ansi.GREEN ++ "info" ++ ansi.RESET, fmt, args);
    } else {
        log("info", fmt, args);
    }
}
