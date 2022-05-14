rec {
  inputs.nixpkgs.url = "git+ssh://git@github.com/flox/nixpkgs-flox";

  description = "Flake providing eval invariant over a package set";

  outputs = {
    self,
    root ? {},
    nixpkgs,
    ...
  } @ args: let
    capacitor = import ./lib/default.nix {inherit self args;};
    lib = args.nixpkgs.lib;
  in (capacitor.capacitate args (customization: let
    packages = with args.nixpkgs;
      lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system: {
        builtfilter-rs = with legacyPackages.${system};
          rustPlatform.buildRustPackage rec {
            name = "builtfilter";
            cargoLock.lockFile = src + "/Cargo.lock";
            src =
              if lib.inNixShell
              then null
              else ./builtfilter-rs;
            nativeBuildInputs = [pkg-config];
            buildInputs =
              [openssl]
              ++ lib.optional pkgs.stdenv.isDarwin [
                libiconv
                darwin.apple_sdk.frameworks.Security
              ];
          };
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
        runEnv = with legacyPackages.${system};
          buildEnv {
            name = "runEnv";
            paths = builtins.map (x: (builtins.dirOf (builtins.dirOf x.program))) (builtins.attrValues self.apps.${system});
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

          add-input = toApp "add-input" {runtimeInputs = with legacyPackages.${system}; [moreutils];} ''
            #!/usr/bin/env bash
            NAME=''$1
            FLAKE=''$2

            INPUT=$(cat <<-END

              inputs.''${NAME}.url = "''${FLAKE}";
              inputs.''${NAME}.inputs.parent.follows = "/";
              inputs.''${NAME}.inputs.nixpkgs.follows = "nixpkgs";
              inputs.''${NAME}.inputs.capacitor.follows = "capacitor";


            END
            )
            { head -n 1 flake.nix; echo "''${INPUT}"; tail -n +2 flake.nix; } | sponge flake.nix
          '';
        });

    devShells = with args.nixpkgs;
      lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (
        system:
          with legacyPackages.${system}; {
            builtfilter-rs = mkShell {
              inputsFrom = [
                self.packages.${system}.builtfilter-rs
              ];
              packages = [
                rustfmt
              ];
              shellHook = ''
                export RUST_SRC_PATH="${pkgs.rustPlatform.rustLibSrc}";
              '';
            };
          }
      );
  in {
    inherit packages apps devShells;
    lib = args.nixpkgs.lib // capacitor;
  }) // {__functor = _: capacitor.project;});
}
