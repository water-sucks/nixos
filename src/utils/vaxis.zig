const std = @import("std");
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
        .gd = &vx.unicode.grapheme_data,
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
pub fn appendToTextBufferANSI(allocator: Allocator, vx: vaxis.Vaxis, buf: *TextViewBuffer, content: []const u8) !void {
    _ = allocator;
    _ = vx;
    _ = buf;
    _ = content;
}
