const std = @import("std");
const io = std.io;
const mem = std.mem;

const Constants = @import("../constants.zig");

pub const BLACK = "\x1B[30m";
pub const RED = "\x1B[31m";
pub const GREEN = "\x1B[32m";
pub const YELLOW = "\x1B[33m";
pub const BLUE = "\x1B[34m";
pub const MAGENTA = "\x1B[35m";
pub const CYAN = "\x1B[36m";
pub const WHITE = "\x1B[37m";
pub const DEFAULT = "\x1B[39m";

pub const RESET = "\x1B[0m";
pub const BOLD = "\x1B[1m";
pub const DIM = "\x1B[2m";
pub const ITALIC = "\x1B[3m";
pub const UNDERLINE = "\x1B[4m";
pub const STRIKE = "\x1B[9m";

pub const R_BOLD = "\x1B[21m";
pub const R_DIM = "\x1B[22m";
pub const R_ITALIC = "\x1B[23m";
pub const R_UNDERLINE = "\x1B[24m";
pub const R_STRIKE = "\x1B[29m";

pub const CLEAR = "\x1B[2J";
pub const MV_TOP_LEFT = "\x1B[H";

/// A thin wrapper writer that strips ANSI codes
/// from the written bytes based on a constant.
pub fn ANSIFilter(comptime WriterType: type) type {
    return struct {
        raw_writer: WriterType,

        pub const Error = WriterType.Error;
        pub const Writer = io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            var input = bytes;

            while (true) {
                const esc_start = mem.indexOf(u8, input, "\x1B[") orelse {
                    // No more escape sequences exist, we are done here.
                    try self.raw_writer.writeAll(input);
                    break;
                };

                const esc_end = mem.indexOf(u8, input[esc_start..], "m") orelse {
                    // This escape sequence is invalid, and there are no more available.
                    try self.raw_writer.writeAll(input);
                    break;
                };

                const sequence = input[esc_start .. esc_start + esc_end + 1];
                const text_before_esc = input[0..esc_start];

                try self.raw_writer.writeAll(text_before_esc);

                if (Constants.use_color) {
                    try self.raw_writer.writeAll(sequence);
                }

                input = input[esc_start + esc_end + 1 ..];
            }

            // This may not be the actual number of bytes due to the
            // skipping of escape sequences, but the writer will fail
            // to flush the actual contents immediately if this is not
            // the case.
            return bytes.len;
        }
    };
}
