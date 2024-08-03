const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const mem = std.mem;

/// systemd.time span, as defined by systemd.time(7).
pub const TimeSpan = struct {
    year: usize = 0,
    month: usize = 0,
    week: usize = 0,
    day: usize = 0,
    hour: usize = 0,
    min: usize = 0,
    sec: usize = 0,
    msec: usize = 0,
    usec: usize = 0,
    nsec: usize = 0,

    const Self = @This();

    const ParseError = error{
        TooShort,
        InvalidChar,
        MissingUnit,
        InvalidUnit,
    };

    fn containsSlice(candidate: []const u8, candidates: []const []const u8) bool {
        for (candidates) |c| {
            if (mem.eql(u8, c, candidate)) {
                return true;
            }
        }
        return false;
    }

    pub fn fromSlice(input: []const u8) !Self {
        const slice = mem.trim(u8, input, &std.ascii.whitespace);
        if (slice.len < 2) return ParseError.TooShort;

        // Make handling of invalid chars simpler
        for (slice) |c| {
            if (!ascii.isAlphanumeric(c) and !ascii.isWhitespace(c)) {
                return ParseError.InvalidChar;
            }
        }

        if (!ascii.isDigit(slice[0])) {
            return ParseError.InvalidChar;
        }

        var parsed = TimeSpan{};

        var i: usize = 0;
        while (i < slice.len) {
            if (ascii.isWhitespace(slice[i])) {
                i += 1;
                continue;
            } else if (!ascii.isDigit(slice[i])) {
                return ParseError.InvalidChar;
            }

            const num_start = i;
            while (i < slice.len and ascii.isDigit(slice[i])) {
                i += 1;
            }
            const num = fmt.parseInt(usize, slice[num_start..i], 10) catch unreachable;

            if (i >= slice.len) {
                return ParseError.MissingUnit;
            }

            while (ascii.isWhitespace(slice[i])) {
                i += 1;
            }

            const unit_start = i;
            while (i < slice.len and ascii.isAlphabetic(slice[i])) {
                i += 1;
            }
            const unit = slice[unit_start..i];

            if (containsSlice(unit, &.{ "ns", "nsec" })) {
                parsed.nsec = num;
            } else if (containsSlice(unit, &.{ "us", "usec" })) {
                // Microseconds; don't support the μs variant, because that's stupid.
                parsed.usec = num;
            } else if (containsSlice(unit, &.{ "ms", "msec" })) {
                parsed.msec = num;
            } else if (containsSlice(unit, &.{ "s", "sec", "second", "seconds" })) {
                parsed.sec = num;
            } else if (containsSlice(unit, &.{ "m", "min", "minute", "minutes" })) {
                parsed.min = num;
            } else if (containsSlice(unit, &.{ "h", "hr", "hour", "hours" })) {
                parsed.hour = num;
            } else if (containsSlice(unit, &.{ "d", "day", "days" })) {
                parsed.day = num;
            } else if (containsSlice(unit, &.{ "w", "week", "weeks" })) {
                parsed.week = num;
            } else if (containsSlice(unit, &.{ "M", "month", "months" })) {
                parsed.month = num;
            } else if (containsSlice(unit, &.{ "y", "year", "years" })) {
                parsed.year = num;
            } else {
                return ParseError.InvalidUnit;
            }
        }

        return parsed;
    }

    pub fn toEpochTime(self: Self) i128 {
        var result: i128 = 0;
        result += self.nsec;
        result += self.usec * 1_000;
        result += self.msec * 1_000 * 1_000;
        result += self.sec * 1_000 * 1_000 * 1_000;
        result += self.min * 1_000_000_000 * 60;
        result += self.hour * 1_000_000_000 * 60 * 60;
        result += self.day * 1_000_000_000 * 60 * 60 * 24;
        result += self.week * 1_000_000_000 * 60 * 60 * 24 * 7;

        // If these values seem weird, it's because they come from
        // systemd.time(7). They may result in imprecise times if
        // using years, but there's no way people are keeping many
        // generations around like this on this time frame.
        var converted_month: f128 = @floatFromInt(self.month * 1_000_000_000 * 60 * 60 * 24);
        converted_month *= 30.44;
        var converted_year: f128 = @floatFromInt(self.year * 1_000_000_000 * 60 * 60 * 24);
        converted_year *= 365.25;

        result += @intFromFloat(converted_month);
        result += @intFromFloat(converted_year);
        return result;
    }
};
