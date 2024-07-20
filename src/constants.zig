pub const etc_nixos = "/etc/NIXOS";
pub const nixos_specialization = "/etc/NIXOS_SPECIALISATION";
pub const resolv_conf = "/etc/resolv.conf";
pub const nix_profiles = "/nix/var/nix/profiles";
pub const nix_system_profiles = nix_profiles ++ "/system-profiles";
pub const default_config_location = "/etc/nixos-cli/config.toml";
pub const current_system = "/run/current-system";
/// DO NOT MUTATE! This is only used to set color printing.
pub var use_color = true;
