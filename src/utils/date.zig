const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const TimeStamp = struct {
    sec: u128 = 0,
    min: u128 = 0,
    hour: u128 = 0,
    day: u128 = 0,
    month: u128 = 0,
    year: u128 = 0,

    const Self = @This();

    pub fn fromEpochTime(time: u128) Self {
        // Remove nanoseconds
        var tmp: u128 = @intCast(@divFloor(time, 1_000_000_000));

        const seconds = @mod(tmp, 60);
        tmp = @divFloor(tmp, 60);
        const minutes = @mod(tmp, 60);
        tmp = @divFloor(tmp, 60);
        const hours = @mod(tmp, 24);
        tmp = @divFloor(tmp, 24);

        var days_since_epoch: u128 = tmp;
        var year: u128 = 1970;

        while (true) {
            var days_in_year: u16 = 365;
            if (@mod(year, 4) == 0) {
                if (@mod(year, 100) != 0 or @mod(year, 400) == 0) {
                    days_in_year = 366;
                }
            }

            if (days_since_epoch < days_in_year) {
                break;
            }

            days_since_epoch -= days_in_year;
            year += 1;
        }

        var month: u8 = 1;
        while (month <= 12) : (month += 1) {
            const days_in_month: u8 = switch (month) {
                4, 6, 9, 11 => 30,
                2 => blk: {
                    if (@mod(year, 4) == 0) {
                        if (@mod(year, 100) != 0 or @mod(year, 400) == 0) {
                            break :blk 29;
                        }
                    }
                    break :blk 28;
                },
                else => 31,
            };

            if (days_since_epoch < days_in_month) {
                break;
            }

            days_since_epoch -= days_in_month;
        }

        const day = days_since_epoch + 1;

        return TimeStamp{
            .sec = seconds,
            .min = minutes,
            .hour = hours,
            .day = day,
            .month = month,
            .year = year,
        };
    }

    pub fn toDateISO8601(self: Self, allocator: Allocator) ![]const u8 {
        return try fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            self.year,
            self.month,
            self.day,
            self.hour,
            self.min,
            self.sec,
        });
    }
};
