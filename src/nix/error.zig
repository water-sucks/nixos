const libutil = @cImport({
    @cInclude("nix/nix_api_util.h");
});

pub const NixError = error{
    Unknown,
    Overflow,
    Key,
    NixError,
};

/// Convert `nix_err` code from `libutil` into Zig `NixError` type.
/// Do not convert NIX_OK (0), as this is not an error.
pub fn nixError(code: libutil.nix_err) NixError {
    return switch (code) {
        -1 => NixError.Unknown,
        -2 => NixError.Overflow,
        -3 => NixError.Key,
        -4 => NixError.NixError,
        else => unreachable,
    };
}
