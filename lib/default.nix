{
  self,
  args,
}: rec {
  # Make the versions attribute safe
  # sanitizeVersionName :: String -> String
  sanitizeVersionName = import ./sanitizeVersionName.nix args.nixpkgs.lib;

  # Customisation functions
  customisation = import ./customisation.nix self;

  # Convert a directory into an attrset of paths
  dirToAttrs = import ./dirToAttrs.nix args.nixpkgs;

  # function for mapAttrs to examine meta.project or passthru.project
  # and inject src from top-level inputs
  # injectSourceWith :: args -> inputs -> name -> value -> attrset
  injectSourceWith = import ./injectSourceWith.nix args.nixpkgs.lib;

  # sortByVersion :: [drv] -> drv
  sortByVersion = import ./sortByVersion.nix;

  analyzeFlake = import ./analyzeFlake.nix;


  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCondFunc = import ./mapAttrsRecursiveCondFunc.nix;

  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCond = self.lib.mapAttrsRecursiveCondFunc builtins.mapAttrs;
  mapAttrsRecursiveList = self.lib.mapAttrsRecursiveCondFunc args.nixpkgs.lib.mapAttrsToList;

  nixpkgsRecurseFunc = self.lib.nixpkgsRecurseFuncWith args.nixpkgs;
  nixpkgsRecurseFuncWith = pkgs: func:
    pkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (system:
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
    i: let
      raw = lib.splitString "." (i.attrPath or i.attr);
      stripQuotes = replaceStrings [''"''] [""];
      result =
        foldl'
        (
          acc: i:
            if lib.length acc > 0 && lib.isList (lib.last acc)
            then
              if !isNull (match ''.*("+)$'' i)
              then lib.init acc ++ [(concatStringsSep "_" (lib.last acc ++ [(stripQuotes i)]))]
              else lib.init acc ++ [(lib.last acc ++ [(stripQuotes i)])]
            else if !isNull (match ''^("+).*'' i)
            then acc ++ [[(stripQuotes i)]]
            else acc ++ [i]
        ) []
        raw;
    in
      lib.attrsets.setAttrByPath (lib.drop 2 result) i;

  parsePath = with builtins;
  with args.nixpkgs;
  with args.nixpkgs.lib;
    attrPath: let
      raw = splitString "." attrPath;
      stripQuotes = replaceStrings [''"''] [""];
      result =
        foldl'
        (
          acc: i:
            if length acc > 0 && isList (last acc)
            then
              if !isNull (match ''.*("+)$'' i)
              then init acc ++ [(concatStringsSep "." (last acc ++ [(stripQuotes i)]))]
              else init acc ++ [(last acc ++ [(stripQuotes i)])]
            else if !isNull (match ''^("+).*'' i)
            then acc ++ [[(stripQuotes i)]]
            else acc ++ [i]
        ) []
        raw;
    in
      result;

  # Generate self-evaluating and cache-checking apps
  makeApps = let
    capacitor = self;
    nixpkgs = capacitor.inputs.nixpkgs;
  in
    with nixpkgs; {
      apps = lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system:
        with legacyPackages.${system}; let
          toApp = name: attrs: text: {
            type = "app";
            program = (writeShellApplication ({inherit name text;} // attrs)).outPath + "/bin/${name}";
          };
        in {
          # Run nix-eval-jobs over the first argument
          # TODO: replaced by pure build?
          eval =
            toApp "eval"
            {
              runtimeInputs = [coreutils args.nix-eval-jobs.defaultPackage.${system} jq];
            } ''
              nix-eval-jobs --depth 2 --flake "$@"
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
            ''
              builtfilter "$@"
            '';

          fixupSplit = let
            fixupjq = capacitor.packages.${system}.fixupjq;
            splitjq = capacitor.packages.${system}.splitjq;
          in
            toApp "fixupSplit"
            {
              runtimeInputs = [
                coreutils
                jq
                fixupjq
                splitjq
              ];
            } ''
              jq --arg originalUri "$1" --arg uri "$2" -f ${fixupjq} | jq -sf ${splitjq}
            '';

          wrapFlake =
            toApp "wrapFlake"
            {
              runtimeInputs = [
                coreutils
                args.nix-eval-jobs.defaultPackage.${system}
                jq
              ];
            }
            ''
              TMPDIR=$(mktemp -d)
              mkdir "$TMPDIR"/self
              trap 'rm "$TMPDIR" -rf && echo exiting ' EXIT
              cat > "$TMPDIR"/self/pkgs.json
              cp ${../templates/flake.nix} "$TMPDIR"/self/flake.nix
              cat > "$TMPDIR"/self/flake.lock <<EOF
              {
                "nodes": {
                  "root": {}
                },
                "root": "root",
                "version": 7
              }
              EOF
              tar -acf out.tar.gz -C "$TMPDIR" self
            '';

          fingerprint =
            toApp "fingerprint"
            {
              runtimeInputs = [coreutils];
            }
            ''
              self=$(echo ${self.outPath} | cut -d/ -f4)
              rev=${builtins.toString (self.revCount or 0)}
              lastMod=${builtins.toString (self.lastModified or 0)}
              echo "$self" >&2
              hash=$(printf "%s;%s;%d;%d;%s" "$self" "" "$rev" "$lastMod" "$(cat ${self.outPath}/flake.lock)" | sha256sum | cut -d' ' -f1)
              printf "$HOME/.cache/nix/eval-cache-v2/%s.sqlite\n" "$hash"
            '';
        });
    };
  
  capacitate = flakeArgs: flakeInputs: mkOutputs:
    let
      lib = self.inputs.nixpkgs.lib;
      flakeOutputs = mkOutputs (customisation flakeArgs flakeInputs);
      analysis = analyzeFlake { resolved = flakeOutputs; inherit lib;}; 

      derivations = lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (system:
        with import self.inputs.nixpkgs {inherit system;};
          (lib.mapAttrs (name: value: ( writeText "${name}_reflection.json" (builtins.toJSON value))) analysis)
      );
      finalOutputs = lib.recursiveUpdate flakeOutputs (makeApps // { __reflect = {inherit analysis derivations; }; });
    in
     finalOutputs;

}
