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

  # flake functions
  flakes = import ./flakes.nix;

  # function for mapAttrs to examine meta.project or passthru.project
  # and inject src from top-level inputs
  # injectSourceWith :: args -> inputs -> name -> value -> attrset
  injectSourceWith = import ./injectSourceWith.nix args.nixpkgs.lib;

  # sortByVersion :: [drv] -> drv
  sortByVersion = import ./sortByVersion.nix;

  # smartType
  smartType = attrpkgs:
    attrpkgs.type
    or (
      if args.nixpkgs-lib.lib.isFunction attrpkgs
      then "lambda"
      else builtins.typeOf attrpkgs
    );

  analyzeFlake = import ./analyzeFlake.nix;

  # over:: attrset.<n>.<n2> -> attrset.<n2>.<n>
  over = attrs: let
    names = builtins.attrNames attrs;
    names2 = args.nixpkgs.lib.concatMap builtins.attrNames (builtins.attrValues attrs);
  in
    args.nixpkgs.lib.genAttrs names2 (n2: args.nixpkgs.lib.genAttrs names (n: attrs.${n}.${n2}));

  # Like recurseIntoAttrs, but do it for two levels
  recurseIntoAttrs2 = attrs: args.nixpkgs.lib.recurseIntoAttrs (builtins.mapAttrs (_: x: args.nixpkgs.lib.recurseIntoAttrs x) attrs);
  recurseIntoAttrs3 = attrs:
    with args.nixpkgs.lib;
      recurseIntoAttrs (
        builtins.mapAttrs (_: x: recurseIntoAttrs2 x) attrs
      );

  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCondFunc = import ./mapAttrsRecursiveCondFunc.nix;

  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCond = self.lib.mapAttrsRecursiveCondFunc builtins.mapAttrs;
  mapAttrsRecursiveList = self.lib.mapAttrsRecursiveCondFunc args.nixpkgs.lib.mapAttrsToList;

  # collectPaths :: (Any -> Bool) -> AttrSet -> [Any]
  collectPaths = self.lib.mapAttrsRecursiveCondFunc args.nixpkgs.lib.mapAttrsToList;

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
    lib = args.nixpkgs-lib.lib;

    cutomizationArgs = {
      root = args.root;
      nixpkgs =
        if flakeArgs ? nixpkgs # the importing flake defines its own nixpkgs
        then flakeArgs.nixpkgs
        else if args ? root.inputs.nixpkgs # the root flake has nixpkgs
        then args.root.inputs.nixpkgs.outputs
        else args.nixpkgs; # use own nixpkgs as per input declaration
    };

    flakeOutputs = mkOutputs (customisation (flakeArgs // cutomizationArgs) // cutomizationArgs);

    mergedOutputs = let
      projects = builtins.listToAttrs (map
        # rename projects
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
                  derivation_name: derivation_value: let
                    name = lib.removeSuffix "/default" "${project_name}/${derivation_name}";
                  in (lib.nameValuePair name derivation_value)
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

      # mapRoot =
      #   (
      #     flakes self.inputs.root
      #     # ugly, but had infinite recursion
      #     (args.nixpkgs-lib.lib // {
      #       inherit mapAttrsRecursiveList 
      #     # smartType
      #     ;
      #     })
      #   )
      #   .mapRoot;
    in (outputs);

    analysis = analyzeFlake self {
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
    lib = args.nixpkgs-lib.lib;
  in
    capacitate flakeArgs (customisation: let
      # get parent managed packages or generate empty system entries
      managedPackages =
        if (args ? root.packages)
        then args.root.packages
        else (lib.genAttrs systems (name: {}));

      nixpkgs = customisation.nixpkgs;
      root = customisation.root;

      mergedArgs = customisation // flakeArgs // {lib = (self.lib) // customisation.auto;};
      capacitated = let
        a = mkProject mergedArgs;
      in
        # if is only a proto-derivation
        if builtins.isFunction a
        then {
          packages.default = mergedArgs.auto.callPackage a {};
          legacyPackages = mergedArgs.auto.callPackage a {};
          __proto.default = a;
        }
        else if
          (with builtins;
            length (attrNames a)
            == 1
            && a ? __proto
            && length (attrNames a.__proto) == 1
            && a.__proto ? default)
        then {
          packages.default = mergedArgs.auto.callPackage a.__proto.default {};
          legacyPackages = mergedArgs.auto.callPackage a.__proto.default {};
          __proto.default = a.__proto.default;
        }
        else a;

      systems = capacitated.__systems or ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      callWithSystem = system: fn: let
        nixpkgs' = nixpkgs.legacyPackages.${system};
        systemInstaces = {
          pkgs' = nixpkgs';
          pkgs = nixpkgs';
          root' = lib.mapAttrs (_: collection: collection.${system} or {}) root;
          self' = lib.mapAttrs (_: collection: collection.${system} or {}) args.self;
          system = system;
        };
      in
        fn (nixpkgs' // systemInstaces);

      mapped = let
        isApp = as: (as ? type && as.type == "app");

        isAnyOf = stopConditions: as: builtins.any x:x (map (cond: cond as) stopConditions);

        makeUpdate = pathEdit: stop: depth: system: namespace: drvOrAttrset:
          if (stop drvOrAttrset || (depth != null && (builtins.length namespace) >= depth))
          then {
            __updateArg = true;
            path = [system] ++ (pathEdit namespace);
            update = _: drvOrAttrset;
          }
          else
            mapAttrsRecursiveCond
            (path: as: !(stop as || (depth != null && ((builtins.length (namespace ++ path)) > depth))))
            (innerPath: drv: {
              __updateArg = true;
              path = [system] ++ (pathEdit (namespace ++ innerPath));
              update = _: drv;
            })
            drvOrAttrset;

        makeUpdates = {
          stop ? _: true,
          depth ? null,
          pathEdit ? (ns: [(lib.concatStringsSep "/" ns)]),
        }:
          mapAttrsRecursiveCond
          (path: as: !(stop as || lib.isFunction as || (depth != null && (builtins.length path) >= depth)))
          (
            path: attribute: let
              # path = if path' == ["__functor"] then [] else path';
              hasSystem = lib.elem (lib.head path) lib.platforms.all;
              namespace =
                if hasSystem
                then (lib.tail path)
                else path;

              # if has System
              system = lib.head path;
              result = system:
                if lib.isFunction attribute
                then callWithSystem system attribute
                else attribute;
              updatesWithOneSystem = makeUpdate pathEdit stop depth system namespace (result system);

              # if no system
              updatesWithAllSystems =
                lib.genAttrs systems
                (
                  system: (makeUpdate pathEdit stop depth system namespace (result system))
                );
            in
              if
                #  lib.traceSeqN 2 ([(attribute) (path) (updatesWithOneSystem.update {})])
                hasSystem
              then updatesWithOneSystem
              else updatesWithAllSystems
          );
      in
        lib.mapAttrs
        (
          attrName: attrValue:
          # pass __ prefixed values as is
            if !lib.elem attrName ["packages" "apps" "devShells" "legacyPackages"]
            #
            then attrValue
            else let
              updateArgs =
                if attrName == "apps"
                then {stop = lib.isApp;}
                else if attrName == "packages"
                then {stop = lib.isDerivation;}
                else if attrName == "devShells"
                then {stop = lib.isDerivation;}
                else if attrName == "legacyPackages"
                then {
                  depth = 1;
                  pathEdit = _:_;
                } # take as is
                else {}; # take as is

              value =
                if lib.isFunction attrValue
                # then { __functor = self: attrValue; }
                then lib.genAttrs systems (system: callWithSystem system attrValue)
                else attrValue;

              updatesInside = makeUpdates updateArgs value;
              updatesPulled = lib.collect (a: a ? "__updateArg") updatesInside;
            in
              args.nixpkgs-lib.lib.updateManyAttrsByPath updatesPulled {}
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
    make_versioned_attributeset = (lib.flip args.nixpkgs-lib.lib.updateManyAttrsByPath) old;
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

  # perform multiple sanitize actions
  # remove multiple attribute names from a level of attrset
  # TODO: perform all at once in sanitize
  sanitizes = value: builtins.foldl' (acc: x: sanitize acc x) value;

  # sanitize: attrset -> string -> attrset
  # remove an attribute name from a level of attrset
  #
  #
  # builtins.mapAttrs (k: v: sanitize v k)
  # {
  #   legacyPackages.x86-64-linux.x86_64-linux.thing = {};
  #   legacyPackages.x86-64-linux.x86_64-darwin.thing = {};
  # } ["legacyPackages" "x86_64-linux"]
  #
  # {
  #   legacyPackages.x86-64-linux.thing = {};
  # }
  sanitize = let
    lib = args.nixpkgs.lib;
    recurse = depth: fragment: system:
      if depth <= 0
      then fragment
      else
        {
          "derivation" = fragment;
          "lambda" = arg: recurse depth (fragment arg) system;
          "list" = map (x: recurse (depth - 1) x system) fragment;
          "set" =
            if fragment ? ${system}
            then if builtins.isAttrs (fragment.${system})
                 then recurse depth fragment.${system} system
                 else recurse depth fragment.${system} system
            else lib.mapAttrs (_: fragment: recurse (depth - 1) fragment system) fragment;
          __functor = self: type: (self.${type} or fragment);
        } (smartType fragment);
  in
    recurse 8;

  # clean up an flake output schema root and generate things for systems
  mapRoot = let
    lib = args.nixpkgs.lib;
    in attrs: builtins.mapAttrs (key: value:
    if lib.elem key ["legacyPackages" "packages" "devShells" "checks" "apps" "bundlers" ]
    # hydraJobs are backward, nixosConfigurations need system differently
    then lib.genAttrs (attrs.__systems or [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ])
      (s: sanitizes value [key s])
    else value) attrs;

}
