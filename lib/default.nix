{
  self,
  args,
}: {
  # UNSAFE: Get latest version from non-empty list of drvs
  # primary :: [drv] -> drv
  primary = values:
    with builtins;
      head (
        sort (a: b:
          isAttrs a
          && isAttrs b
          && a ? version
          && builtins.isString a.version
          && b ? version
          && builtins.isString b.version
          && compareVersions a.version b.version >= 0)
        values
      );

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

  /*
   Like `mapAttrsRecursiveCond`, but the condition can examine the path
   */
  mapAttrsRecursiveCondFunc = with builtins;
    mapper: cond: f: set: let
      recurse = path: let
        g = name: value: let
          path' = path ++ [name];
          try =
            builtins.tryEval
            (
              if isAttrs value && cond path' value
              then recurse path' value
              else f path' value
            );
        in
          if try.success
          then try.value
          else null;
      in
        mapper g;
    in
      recurse [] set;

  /*
   Like `mapAttrsRecursiveCond`, but the condition can examine the path
   */
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
        foldl' (
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
          foldl' (
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

    makeApps = nixpkgs:
      with nixpkgs;
        lib.genAttrs ["x86_64-linux"] (system:
          with legacyPackages.${system}; let
            toApp = name: attrs: text: {
              type = "app";
              program = (writeShellApplication ({inherit name text;} // attrs)).outPath + "/bin/${name}";
            };
          in {
            # Run nix-eval-jobs over the first argument
            # TODO: replaced by pure build?
            eval =
              toApp "eval" {
                runtimeInputs = [coreutils args.nix-eval-jobs.defaultPackage.${system} jq];
              } ''
                nix-eval-jobs --flake "$1" --depth 2
              '';

            checkCache =
              toApp "checkCache" {
                runtimeInputs = [
                  coreutils args.nix-eval-jobs.defaultPackage.${system} jq parallel sqlite
                  self.packages.${system}.builtfilter
k
                ]; # {{{
              } ''
                builtfilter --debug -u activate
              '';

            });
}
