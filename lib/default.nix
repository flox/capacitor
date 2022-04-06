{ self
, args
,
}: {
  # sortByVersion :: [drv] -> drv
  sortByVersion = import ./sortByVersion.nix;

  # Make the versions attribute safe
  # sanitizeVersionName :: String -> String
  sanitizeVersionName = with builtins;
    with args.nixpkgs.lib.strings;
    string:
    args.nixpkgs.lib.pipe string [
      unsafeDiscardStringContext
      # Strip all leading "."
      (x: elemAt (match "\\.*(.*)" x) 0)
      (split "[^[:alnum:]+_?=-]+")
      # Replace invalid character ranges with a "-"
      (concatMapStrings (s:
        if args.nixpkgs.lib.isList s
        then "_"
        else s))
      (x: substring (args.nixpkgs.lib.max (stringLength x - 207) 0) (-1) x)
      (x:
        if stringLength x == 0
        then "unknown"
        else x)
    ];

  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCondFunc = import ./mapAttrsRecursiveCondFunc.nix;

  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCond = self.lib.mapAttrsRecursiveCondFunc builtins.mapAttrs;
  mapAttrsRecursiveList = self.lib.mapAttrsRecursiveCondFunc args.nixpkgs.lib.mapAttrsToList;

  nixpkgsRecurseFunc = self.lib.nixpkgsRecurseFuncWith args.nixpkgs;
  nixpkgsRecurseFuncWith = pkgs: func:
    pkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      pkgs.lib.genAttrs self.__stabilities (stability: (
        self.lib.mapAttrsRecursiveCond
          (path: a:
            (a.recurseForDerivations or false || a.recurseForRelease or false) && !(a ? type && a.type == "derivation"))
          (path: value: func path value stability)
          (import args.${stability} {
            inherit system;
            #config.allowAliases = false;
            config.allowUnfree = true;
          })
      )));

  toNested = with builtins;
    with args.nixpkgs;
    i:
    let
      raw = lib.splitString "." (i.attrPath or i.attr);
      stripQuotes = replaceStrings [ ''"'' ] [ "" ];
      result =
        foldl'
          (
            acc: i:
              if lib.length acc > 0 && lib.isList (lib.last acc)
              then
                if !isNull (match ''.*("+)$'' i)
                then lib.init acc ++ [ (concatStringsSep "_" (lib.last acc ++ [ (stripQuotes i) ])) ]
                else lib.init acc ++ [ (lib.last acc ++ [ (stripQuotes i) ]) ]
              else if !isNull (match ''^("+).*'' i)
              then acc ++ [ [ (stripQuotes i) ] ]
              else acc ++ [ i ]
          ) [ ]
          raw;
    in
    lib.attrsets.setAttrByPath (lib.drop 2 result) i;

  parsePath = with builtins;
    with args.nixpkgs;
    with args.nixpkgs.lib;
    attrPath:
    let
      raw = splitString "." attrPath;
      stripQuotes = replaceStrings [ ''"'' ] [ "" ];
      result =
        foldl'
          (
            acc: i:
              if length acc > 0 && isList (last acc)
              then
                if !isNull (match ''.*("+)$'' i)
                then init acc ++ [ (concatStringsSep "." (last acc ++ [ (stripQuotes i) ])) ]
                else init acc ++ [ (last acc ++ [ (stripQuotes i) ]) ]
              else if !isNull (match ''^("+).*'' i)
              then acc ++ [ [ (stripQuotes i) ] ]
              else acc ++ [ i ]
          ) [ ]
          raw;
    in
    result;

  # Generate self-evaluating and cache-checking apps
  makeApps = let capacitor = self; in
    self: nixpkgs:
      with nixpkgs;
      {
        apps = lib.genAttrs [ "x86_64-linux" ] (system:
          with legacyPackages.${system}; let
            toApp = name: attrs: text: {
              type = "app";
              program = (writeShellApplication ({ inherit name text; } // attrs)).outPath + "/bin/${name}";
            };
          in
          {
            # Run nix-eval-jobs over the first argument
            # TODO: replaced by pure build?
            eval =
              toApp "eval"
                {
                  runtimeInputs = [ coreutils args.nix-eval-jobs.defaultPackage.${system} jq ];
                } ''
                nix-eval-jobs --flake "$1" --depth 2
              '';

            checkCache =
              toApp "checkCache"
                {
                  runtimeInputs = [
                    coreutils
                    args.nix-eval-jobs.defaultPackage.${system}
                    jq
                    parallel
                    sqlite
                    capacitor.packages.${system}.builtfilter
                  ];
                }
                # FIXME: Make this process more ergonomic
                ''
                  if [[] -z "''${SUBSTITUTER}" ]]; then
                    SUBSTITUTER_FLAG="--substituter ''${SUBSTITUTER}"
                  fi
                  builtfilter --debug -u $SUBSTITUTER_FLAG activate
                '';

          });
        packages = lib.genAttrs [ "x86_64-linux" ] (system: with legacyPackages.${system}; {
          self-eval = runCommand "self-eval"
            {
              nativeBuildInputs = [
                nixUnstable
                jq
                args.nix-eval-jobs.defaultPackage.${system}
              ];
            } ''
            export HOME=$PWD
            export GC_DONT_GC=1
            export NIX_CONFIG="experimental-features = flakes nix-command
            store = $PWD/temp
            substituters =
            "
            ls -alh ${nixpkgs}
            ls -alh ${capacitor}
            mkdir temp gc $out
            set -x
            nix-eval-jobs --gc-roots-dir $PWD/gc \
              --flake ${self.outPath}#legacyPackages.${system} \
              --depth 2 \
            > $out/manifest.json
          '';
          #                | jq -c '.originalUri = "${args.nixpkgs.rev}" |
          #                          .uri = "${builtins.dirOf args.nixpkgs.rev}/${args.nixpkgs.rev}"' \
          #  | tee /dev/fd/2 | jq -cs '{elements:.,version:1}' \
        });
      };

}
