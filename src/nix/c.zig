pub const libnix = @cImport({
    @cInclude("nix/nix_api_util.h");
    @cInclude("nix/nix_api_expr.h");
    @cInclude("nix/nix_api_store.h");
    @cInclude("nix/nix_api_value.h");
});
