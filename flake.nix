# Adapted from https://matthewbauer.us/blog/all-the-versions.html
rec {
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  inputs.nix-eval-jobs.url = "github:tomberek/nix-eval-jobs";
  #inputs.nix-eval-jobs.inputs.nixpkgs.follows = "nixpkgs";

  description = "Flake providing eval invariant over a package set";

  outputs = {self, ...} @ args:
    {
      # library functions
      lib = import ./lib/default.nix {inherit self args;};
    };
}
