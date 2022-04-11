# Adapted from https://matthewbauer.us/blog/all-the-versions.html
rec {
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  inputs.nix-eval-jobs.url = "github:tomberek/nix-eval-jobs";
  #inputs.nix-eval-jobs.inputs.nixpkgs.follows = "nixpkgs";

  description = "Flake providing eval invariant over a package set";

  outputs = {self, ...} @ args: let
    packages = with args.nixpkgs;
      lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system: {
        builtfilter = with legacyPackages.${system};
          buildGoModule {
            name = "builtfilter";
            src = ./builtfilter;
            vendorSha256 = "sha256-FNBJoVNuOL3mKM3RyFdsYGWgJYaQxtW6jZR6g7M7+Xo=";
          };
        fixupjq = with legacyPackages.${system};
          stdenv.mkDerivation {
            name = "fixupjq";
            src = ./lib/fixup.jq;
            phases = ["installPhase"];
            installPhase = ''
              cp $src $out
            '';
          };
        splitjq = with legacyPackages.${system};
          stdenv.mkDerivation {
            name = "splitjq";
            src = ./lib/split.jq;
            phases = ["installPhase"];
            installPhase = ''
              cp $src $out
            '';
          };
      });

    apps = with args.nixpkgs;
      lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system:
        with legacyPackages.${system}; let
          toApp = name: attrs: text: {
            type = "app";
            program = (writeShellApplication ({inherit name text;} // attrs)).outPath + "/bin/${name}";
          };
          installables = lib.concatMapStringsSep " " (pkg: ".\\#packages.${system}.${pkg}") (builtins.attrNames packages.${system});
        in {
          cache-binaries = toApp "cache-binaries" {} ''
            ## cache-binaries <s3://..> <sign-key>
            # builds, signs and pushes to S3

            if [[ "$#" -lt 1 ]]; then
              echo "USAGE: cache-binaries <s3://..>"
              echo
              echo "ENVIRONMENT"
              echo "FLOX_BINARY_SIGNING_KEY Private key for the S3 binary cache"
              exit 1
            fi

            # build binaries
            echo "Building binaries"
            nix build ${installables}

            # sign binaries
            if [[ -v FLOX_BINARY_SIGNING_KEY ]]; then
              echo "Signing Key detected - signing binaries"
              nix store sign -k <(echo "''${FLOX_BINARY_SIGNING_KEY}") ${installables}
            else
              echo "Warn: no signing key detected - binaries were not signed"
            fi

            # push binaries to S3
            echo "Pushing binaries to S3 bucket"
            nix copy --verbose --to "''$1" ${installables}
          '';
        });
  in {
    inherit packages apps;
    # library functions
    lib = import ./lib/default.nix {inherit self args;};
  };
}
