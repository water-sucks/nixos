const std = @import("std");
const mem = std.mem;
const zf = @import("zf");

pub const Candidate = struct {
    str: []const u8,
    rank: f64 = 0,
};

pub fn CandidateStruct(comptime T: type) type {
    return struct {
        value: T,
        rank: f64 = 0,
    };
}

pub fn rankCandidates(
    ranked: []Candidate,
    candidates: []const []const u8,
    tokens: []const []const u8,
    keep_order: bool,
    plain: bool,
    case_sensitive: bool,
) []Candidate {
    if (tokens.len == 0) {
        for (candidates, 0..) |candidate, index| {
            ranked[index] = .{ .str = candidate };
        }
        return ranked;
    }

    var index: usize = 0;
    for (candidates) |candidate| {
        if (zf.rank(candidate, tokens, .{ .plain = plain, .to_lower = !case_sensitive })) |rank| {
            ranked[index] = .{ .str = candidate, .rank = rank };
            index += 1;
        }
    }

    if (!keep_order) {
        std.sort.block(Candidate, ranked[0..index], {}, sortCandidates);
    }

    return ranked[0..index];
}

pub fn rankCandidatesStruct(
    comptime T: type,
    comptime field_name: []const u8,
    ranked: []CandidateStruct(T),
    candidates: []const T,
    tokens: []const []const u8,
    plain: bool,
    case_sensitive: bool,
) []CandidateStruct(T) {
    switch (@typeInfo(T)) {
        .Struct => |_| {
            if (!@hasField(T, field_name)) {
                @compileError(@typeName(T) ++ " has no field named " ++ field_name);
            }
        },
        else => @compileError("rankCandidatesStruct must take a struct type"),
    }

    if (tokens.len == 0) {
        for (candidates, 0..) |candidate, index| {
            ranked[index] = .{ .value = candidate };
        }
        return ranked;
    }

    var index: usize = 0;
    for (candidates) |candidate| {
        const candidate_str: []const u8 = blk: {
            if (@TypeOf(@field(candidate, field_name)) == ?[]const u8) {
                break :blk @field(candidate, field_name) orelse "";
            } else {
                break :blk @field(candidate, field_name);
            }
        };

        if (zf.rank(candidate_str, tokens, .{ .plain = plain, .to_lower = !case_sensitive })) |rank| {
            ranked[index] = .{ .value = candidate, .rank = rank };
            index += 1;
        }
    }

    return ranked[0..index];
}

fn sortCandidates(_: void, a: Candidate, b: Candidate) bool {
    if (a.rank < b.rank) return true;
    if (a.rank > b.rank) return false;

    if (a.str.len < b.str.len) return true;
    if (a.str.len > b.str.len) return false;

    for (a.str, 0..) |c, i| {
        if (c < b.str[i]) return true;
        if (c > b.str[i]) return false;
    }

    return false;
}
