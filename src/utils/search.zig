const std = @import("std");
const zf = @import("zf");

pub const Candidate = struct {
    str: []const u8,
    rank: f64 = 0,
};

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
        if (zf.rank(candidate, tokens, case_sensitive, plain)) |rank| {
            ranked[index] = .{ .str = candidate, .rank = rank };
            index += 1;
        }
    }

    if (!keep_order) {
        std.sort.block(Candidate, ranked[0..index], {}, sortCandidates);
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
