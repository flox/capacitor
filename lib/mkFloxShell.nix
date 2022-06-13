_: toml: pins: {pkgs, ...}: let
  data =
    _.capacitor.lib.flox-env {
      inherit (_.capacitor.inputs) mach-nix;
      lib = _.capacitor.lib;
    }
    pkgs
    toml
    pins;
in
  _.capacitor.lib.mkNakedShell {
    inherit (_.capacitor.inputs) devshell;
    inherit data;
    inherit pkgs;
    inherit pins;
    floxpkgs = _.self;
    lib = _.capacitor.lib;
  }
