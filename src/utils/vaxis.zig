const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const TextView = vaxis.widgets.TextView;
const TextViewBuffer = TextView.Buffer;

/// Append content to a TextView.Buffer with the given style
/// applied to the passed contents.
pub fn appendToTextBuffer(allocator: Allocator, vx: vaxis.Vaxis, buf: *TextViewBuffer, content: []const u8, style: vaxis.Style) !void {
    const begin = buf.content.items.len;
    const end = begin + content.len + 1;

    try buf.append(allocator, .{
        .bytes = content,
        .gd = &vx.unicode.width_data.g_data,
        .wd = &vx.unicode.width_data,
    });

    try buf.updateStyle(allocator, .{
        .begin = begin,
        .end = end,
        .style = style,
    });
}

/// Append content to a TextView.Buffer, parsing out the ANSI codes
/// into applicable libvaxis styles.
///
/// This only works with the defined codes in utils/ansi.zig.
pub fn appendToTextBufferANSI(allocator: Allocator, vx: vaxis.Vaxis, buf: *TextViewBuffer, content: []const u8) !void {
    // This is the style to apply to the current slice.
    // This will get updated upon every ANSI style encountered.
    var style: vaxis.Style = .{};

    var input = content;
    while (true) {
        const esc_start = mem.indexOf(u8, input, "\x1B[") orelse {
            // No more escape sequences exist, just write the
            // rest of the string and return
            try appendToTextBuffer(allocator, vx, buf, input, style);
            break;
        };

        const esc_end = mem.indexOf(u8, input[esc_start..], "m") orelse return error.MissingTerminator;

        const sequence = input[esc_start .. esc_start + esc_end + 1];
        const text_before_esc = input[0..esc_start];

        try appendToTextBuffer(allocator, vx, buf, text_before_esc, style);
        updateVaxisStyleANSI(&style, sequence);

        input = input[esc_start + esc_end + 1 ..];
    }
}

/// Parse an ANSI sequence and update the corresponding Vaxis sstyle.
///
/// Only works with the codes defined in utils/ansi.zig; other codes are ignored.
/// Also, this is terrible code. This needs to be updated to parse ANSI styles
/// generically and apply them as such.
fn updateVaxisStyleANSI(style: *vaxis.Style, code: []const u8) void {
    const bytes = code[2 .. code.len - 1];

    // Ignore ANSI escape codes that are not numbers.
    const num = fmt.parseInt(usize, bytes, 10) catch return;

    switch (num) {
        // Reset everything
        0 => style.* = .{},

        // Text styles
        1 => style.*.bold = true,
        2 => style.*.dim = true,
        3 => style.*.italic = true,
        4 => style.*.ul_style = .single,
        9 => style.*.strikethrough = true,

        // Text style resets
        21 => style.*.bold = false,
        22 => style.*.dim = false,
        23 => style.*.italic = false,
        24 => style.*.ul_style = .off,
        29 => style.*.strikethrough = false,

        // Foreground colors
        30 => style.*.fg = .{ .index = 0 },
        31 => style.*.fg = .{ .index = 1 },
        32 => style.*.fg = .{ .index = 2 },
        33 => style.*.fg = .{ .index = 3 },
        34 => style.*.fg = .{ .index = 4 },
        35 => style.*.fg = .{ .index = 5 },
        36 => style.*.fg = .{ .index = 6 },
        37 => style.*.fg = .{ .index = 7 },
        39 => style.*.fg = .default,

        else => {},
    }
}
