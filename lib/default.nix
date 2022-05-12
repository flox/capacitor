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

  capacitate = flakeArgs: mkOutputs: let
    lib = args.nixpkgs.lib;
    flakeOutputs = mkOutputs (customisation flakeArgs);

    mergedOutputs = let
      projects = builtins.listToAttrs (map
        (project:
          if builtins.isAttrs project
          then lib.nameValuePair project.as project.project
          else lib.nameValuePair project flakeArgs.${project})
        flakeOutputs.__projects or []);

      prefix_values =
        builtins.mapAttrs
        (project_name: project:
          builtins.mapAttrs
          (set_name: systems:
            builtins.mapAttrs
            (
              system: derivations:
                lib.mapAttrs'
                (
                  derivation_name: derivation_value: lib.nameValuePair "${project_name}/${derivation_name}" derivation_value
                )
                derivations
            )
            systems)
          (lib.filterAttrs (attr: _: lib.elem attr ["packages" "apps" "devShells"]) project))
        projects;

      outputs =
        lib.foldl
        (lib.recursiveUpdate)
        (builtins.removeAttrs flakeOutputs ["__projects"])
        (builtins.attrValues prefix_values);
    in
      outputs;

    analysis = analyzeFlake {
      resolved = mergedOutputs;
      inherit lib;
    };
    referredVersions =
      if lib.hasAttrByPath ["__reflect" "versions"] flakeOutputs
      then lib.attrValues (lib.getAttrs flakeOutputs.__reflect.versions flakeArgs)
      else [];

    versions = findVersions ([analysis.all] ++ referredVersions);

    derivations = lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (
      system:
        with import self.inputs.nixpkgs {inherit system;}; (lib.mapAttrs (name: value: (writeText "${name}_reflection.json" (builtins.toJSON value))) analysis)
    );
    finalOutputs = lib.recursiveUpdate mergedOutputs (makeApps // {__reflect = {inherit analysis derivations versions;};});
  in
    finalOutputs;

  project = flakeArgs: mkProject: let
    nixpkgs =
      if flakeArgs ? nixpkgs
      then flakeArgs.nixpkgs
      else args.nixpkgs;
    lib = args.nixpkgs.lib;
    # get parent managed packages or generate empty system entries
    managedPackages =
      if (flakeArgs ? parent && flakeArgs.parent ? packages)
      then flakeArgs.parent.packages
      else (lib.genAttrs args.flake-utils.lib.defaultSystems (name: {}));
    capacitationArgs = flakeArgs // {inherit nixpkgs;};
  in
    capacitate capacitationArgs (customisation: let
      mergedArgs = customisation // capacitationArgs;
      capacitated = mkProject mergedArgs;

      systems = args.flake-utils.lib.defaultSystems;
      callWithSystem = system: fn: fn (nixpkgs.legacyPackages.${system} // {parent = managedPackages.${system};});

      makeUpdate = system: namespace: drvOrAttrset:
        if lib.isDerivation drvOrAttrset
        then {
          __updateArg = true;
          path = [system namespace];
          update = _: drvOrAttrset;
        }
        else
          mapAttrsRecursiveCond
          (as: !(lib.isDerivation as))
          (innerPath: drv: {
            __updateArg = true;
            path = [system (lib.intersperse "/" ([namespace] ++ innerPath))];
            update = _: drv;
          })
          drvOrAttrset;

      makeUpdates =
        lib.mapAttrsRecursiveCond
        (as: !(lib.isDerivation as || lib.isFunction as))
        (
          path: attribute: let
            hasSystem = lib.elem (lib.head path) lib.platforms.all;
            namespace = builtins.concatStringsSep "/" (
              if hasSystem
              then (lib.tail path)
              else path
            );

            # if has System
            system = lib.head path;
            result =
              if lib.isFunction attribute
              then callWithSystem system attribute
              else attribute;
            updatesWithOneSystem = makeUpdate system namespace result;

            # if no system
            updatesWithAllSystems = builtins.listToAttrs (map
              (
                system:
                  lib.nameValuePair
                  system
                  (makeUpdate system namespace (callWithSystem system attribute))
              )
              systems);
          in
            if hasSystem
            then updatesWithOneSystem
            else updatesWithAllSystems
        );

      mapped =
        lib.mapAttrs
        (
          attrName: attrValue:
            if lib.hasPrefix "__" attrName
            then attrValue
            else if attrName == "legacyPackages"
            then
              if lib.isFunction attrValue
              then lib.genAttrs systems (system: callWithSystem system attrValue)
              else attrValue
            else let
              value =
                if lib.isFunction attrValue
                then builtins.listToAttrs (map (system: lib.nameValuePair system (callWithSystem system attrValue)) systems)
                else attrValue;
              updatesInside = makeUpdates value;

              updatesPulled = lib.collect (a: a ? "__updateArg") updatesInside;
            in
              lib.updateManyAttrsByPath updatesPulled {}
        )
        capacitated;
    in
      mapped);

  findVersions' = old: reports: let
    lib = args.nixpkgs.lib;

    ensure_report = map (
      report:
        if (report ? __reflect)
        then report.__reflect.analysis.all # report is a flake
        else report # resolved_report
    );
    combine_reports = builtins.concatLists;
    filter_versioned = builtins.filter (attr: attr ? version);
    make_update_attrs = map (attribute: {
      path = attribute.attribute_path ++ ["versions"];
      update = versions: let
        versions' =
          if (builtins.tryEval versions).success
          then versions
          else {};
      in
        versions' // {${attribute.version} = attribute;};
    });
    make_versioned_attributeset = (lib.flip lib.updateManyAttrsByPath) old;
  in
    lib.pipe reports [
      ensure_report
      combine_reports
      filter_versioned
      make_update_attrs
      make_versioned_attributeset
    ];

  findVersions = findVersions' {};

  findVersionsImpure = flakes: let
    lib = args.nixpkgs.lib;
    get_flakes = map builtins.getFlake;
  in
    lib.pipe flakes [
      get_flakes
      findVersions
    ];
}
