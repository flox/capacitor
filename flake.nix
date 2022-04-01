# Adapted from https://matthewbauer.us/blog/all-the-versions.html
rec {
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  inputs.nix-eval-jobs.url = "github:tomberek/nix-eval-jobs";
  #inputs.nix-eval-jobs.inputs.nixpkgs.follows = "nixpkgs";

  description = "Flake providing eval invariant over a package set";

  outputs = {self, ...} @ args: {
    # library functions
    lib = import ./lib/default.nix {inherit self args;};

    packages = with args.nixpkgs;
      lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system: {
        builtfilter = with legacyPackages.${system};
          buildGoModule {
            name = "builtfilter";
            src = ./builtfilter;
            vendorSha256 = "sha256-HSR4Dj8trSR85rUnmgCiO5yel3NgOToUnQpUOxBsv+s=";
          };
      });
  };
}
