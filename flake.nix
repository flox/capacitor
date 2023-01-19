rec {
  description = "Flake providing eval invariant over a package set";
  inputs.nixpkgs.url = "github:flox/nixpkgs/stable";
  inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  # inputs.root.follows = "/";

  outputs = {
    self,
    nixpkgs-lib,
    ...
  } @ args: let
    bootstrap = let
      lib =
        nixpkgs-lib.lib
        // {
          capacitor = {
            dirToAttrs = import ./lib/dirToAttrs.nix {inherit lib;};
            smartType = import ./lib/smartType.nix {inherit lib;};
            exported = import ./lib/exported.nix {};
            hidden = import ./lib/hidden.nix {};
            capacitate = {
              auto = import ./lib/capacitate/auto.nix {inherit lib;};
              capacitate = import ./lib/capacitate/capacitate.nix {
                inherit lib;
                inputs = args;
              };
              collectProtos = import ./lib/capacitate/collectProtos.nix { inherit lib; };
              legacyPackages = import ./lib/capacitate/legacyPackages.nix {inherit lib;};
              lib = import ./lib/capacitate/lib.nix {inherit lib;};
              materialize = import ./lib/capacitate/materialize.nix { inherit lib; };
              protoToClosure = import ./lib/capacitate/protoToClosure.nix { inherit lib; };
            };
            plugins = {
              localResources = import ./lib/plugins/localResources.nix {inherit lib;};
            };
            mapAttrsRecursiveCondFunc = import ./lib/mapAttrsRecursiveCondFunc.nix {};
            # mapAttrsRecursiveDir = import ./lib/mapAttrsRecursiveDir.nix {inherit lib;};
            # using = import ./lib/using.nix {inherit lib;};
            # sanitizes = import ./lib/sanitizes.nix {inherit lib;};
            # flakes = import ./lib/flakes.nix {inherit lib;};
            # mapRoot = import ./lib/mapRoot.nix {inherit lib;};
          };
        };
    in
      lib.capacitor.capacitate.capacitate {} args (context @ {
        auto,
        self,
        ...
      }: {
        passthru = {
          # TODO: is this still necessary?
          # dare to remove
          lib.capacitor = auto.localResourcesWith {} "lib" context "lib/";
          __functor = _: bootstrap.lib.capacitor.capacitate.capacitate {};
        };
        passthru.defaultPlugins = bootstrap.lib.capacitor.plugins.importers.all;
        passthru.plugins = bootstrap.lib.capacitor.plugins;

        config.systems = ["aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux"];
        config.plugins = [
          lib.capacitor.capacitate.lib.plugin
          (lib.capacitor.plugins.localResources {
            type = "lib";
            path = ["lib" "capacitor"];
            injectedArgs = {};
          })
        ];
      });
  in
    bootstrap;
}
