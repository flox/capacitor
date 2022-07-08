rec {
  description = "Flake providing eval invariant over a package set";
  inputs.nixpkgs.url = "github:flox/nixpkgs/stable";
  inputs.root.follows = "nixpkgs";


  outputs = {
    self,
    nixpkgs,
    root,
    ...
  } @ args: let

    bootstrap = let
      lib =
        nixpkgs.lib
        // {
          capacitor = {
            dirToAttrs = import ./lib/dirToAttrs.nix {inherit lib;};
            smartType = import ./lib/smartType.nix {inherit lib;};
            capacitate = {
              capacitate = import ./lib/capacitate/capacitate.nix {
                inherit lib; 
                args = args // {
                  root = bootstrap;
              };};
              legacyPackages = import ./lib/capacitate/legacyPackages.nix {inherit lib;};
              lib = import ./lib/capacitate/lib.nix {inherit lib;};
              auto = import ./lib/capacitate/auto.nix {inherit lib;};
            };
            plugins = {
              localResources = import ./lib/plugins/localResources.nix {inherit lib;};
            };
            mapAttrsRecursiveCondFunc = import ./lib/mapAttrsRecursiveCondFunc.nix {inherit lib;};
            # mapAttrsRecursiveDir = import ./lib/mapAttrsRecursiveDir.nix {inherit lib;};
            # using = import ./lib/using.nix {inherit lib;};
            # sanitizes = import ./lib/sanitizes.nix {inherit lib;};
            # flakes = import ./lib/flakes.nix {inherit lib;};
            # mapRoot = import ./lib/mapRoot.nix {inherit lib;};
          };
        };

      in lib.capacitor.capacitate.capacitate.capacitate args (context @ {auto,self,...}: {
        
        # lib.capacitor = (auto.localResourcesWith {root = root;} "lib" context "lib/");
        
        passthru.__functor = _: bootstrap.lib.capacitor.capacitate.capacitate.capacitate;
        passthru.defaultPlugins = bootstrap.lib.capacitor.capacitate.capacitate.defaultPlugins;
        passthru.plugins = bootstrap.lib.capacitor.plugins;

        config.stabilities = { default = nixpkgs; };
        config.systems = ["aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux"];
        config.plugins = [
          lib.capacitor.capacitate.lib.plugin
          (lib.capacitor.plugins.localResources {
            type = "lib";
            path = ["lib" "capacitor"];
            injectedArgs = {root = root;};
          })
        ];
      });
  in
    bootstrap;
}
