self: args: let
  # attempt to extract source from a function with a source argument
  fetchFromInputs = input: args.${input}; #self.lib.injectSourceWith args inputs;
  fetchFrom = inputsRaw: self.lib.injectSourceWith args inputsRaw;
in
  # Scopes vs Overrides
  # Scopes provide a way to compose packages sets. They have less
  # power than override with their fixed points, but are simpler to use.
  #
  #
  rec {
    smartType = attrpkgs:
      attrpkgs.type
      or (
        if args.nixpkgs.lib.isFunction attrpkgs
        then "lambda"
        else builtins.typeOf attrpkgs
      );

    # using:: bool: current_name: {packageSet} -> {paths} -> {pkgsForThePaths}
    usingClean = clean: name: pkgset: attrpkgs: let
      scope' = extra: (pkgset.newScope or args.nixpkgs.lib.callPackageWith) (pkgset // extra);
      # replacing _ above..... deal with various packages set having subpar support for scopes
      scope = let
      in
        if pkgset ? callPackageWith
        then attr: path: over: pkgset.callPackageWith (pkgset // attr) path over
        else
          # Python's is broken
          # if pkgset?callPackage
          # then attr: path: over: pkgset.callPackage path over else
          if pkgset ? newScope
          then attr: pkgset.newScope (pkgset // attr)
          else attr: args.nixpkgs.lib.callPackageWith (pkgset // attr);
          injectedArgs = {
            inherit fetchFromInputs name fetchFrom;
          };
    in
      {
        # if the item is a derivation, use it directly
        derivation = attrpkgs;

        # if the item is a raw path, then use injectSource+callPackage on it
        path =
          if args.nixpkgs.lib.hasSuffix ".toml" attrpkgs
          then
            usingClean clean name pkgset {
              type = "toml";
              path = attrpkgs;
            }
          else scope injectedArgs attrpkgs {};

        toml = let
          a = processTOML attrpkgs.path pkgset;
          # TODO: ensure scope is correct
        in (scope (pkgset // injectedArgs) a.func a.attrs);

        # if the item is a raw path, then use injectSource+callPackage on it
        string =
          if args.nixpkgs.lib.hasSuffix ".toml" attrpkgs
          then
            usingClean clean name pkgset {
              type = "toml";
              path = attrpkgs;
            }
          else scope injectedArgs attrpkgs {};

        # if the item is a lambda, provide a callPackage for use
        lambda = attrpkgs (scope injectedArgs);

        # everything else is an error
        __functor = self: type: (
          self.${type}
          or (throw "last arg to 'using' was '${type}'; should be a path to Nix, path to TOML, attrset of paths, derivation, or function")
        );

        # Sets are more complicated and require recursion
        set =
          # if it is a scope already pass it along, don't recurse to allow for isolation
          if attrpkgs ? newScope
          then attrpkgs.packages attrpkgs
          else # <-------- TODO: needs review
            let
              res =
                builtins.mapAttrs (
                  n: v:
                    with args.nixpkgs; let
                      # Bring results back in! TODO: check if using // or recursiveUpdate
                      # only do pkgset.${name} if it is a packageset, not a package or other thing
                      level = lib.recursiveUpdate (pkgset // (pkgset.${name} or {})) res;
                      newScope = s: scope (level // s);
                      me = lib.makeScope newScope (_: usingClean clean n level v);
                    in
                      if clean && me ? packages
                      then me.packages me
                      else me
                )
                attrpkgs;
            in
              res;
      } (smartType attrpkgs);

    usingRaw = usingClean false "__root";
    using = usingClean true "__root";

    # With https://github.com/NixOS/nix/pull/6436
    evaluateString = scope: str: builtins.scopedImport scope (builtins.toFile "eval" str);
    # With IFD:
    # evaluateString = scope: str: builtins.scopedImport scope (writeText "eval" str);

    # callTOMLPackageWith
    # re-expose callPackageWith, but after processing a TOML argument
    callTOMLPackageWith = pkgs: path: overrides: let
      struct = processTOML path pkgs;
    in
      args.nixpkgs.lib.callPackageWith pkgs struct.func (struct.attrs // overrides);

    # processTOML ::: path -> pkgs -> {func,attrs}
    # Expect an inputs attribute and that strings begining with "inputs." are
    # references, TODO: use ${ instead?
    processTOML = tomlpath: pkgs: let
      packages = with builtins; let
        paths = self.lib.mapAttrsRecursiveCond (_: v: v != {}) (p: _: p) toml.inputs;
        inputPaths = args.nixpkgs.lib.attrsets.collect (builtins.isList) paths;
      in
        foldl' (a: b: args.nixpkgs.lib.recursiveUpdate a b) {} (
          [pkgs]
          ++ (
            map (path: args.nixpkgs.lib.attrsets.getAttrFromPath path pkgs)
            inputPaths
          )
        );

      toml = builtins.fromTOML (builtins.readFile tomlpath);
      ins = toml.inputs;
      attrs = builtins.removeAttrs toml ["inputs"];

      # Recurse looking for strings matching "inputs." pattern in order
      # to resolve with scope
      handlers = isNixExpr: {
        list = list: map (x: (handlers isNixExpr).${builtins.typeOf x} x) list;
        string = with builtins;
          x:
            if isNixExpr
            then args.nixpkgs.lib.attrsets.getAttrFromPath (self.lib.parsePath x) packages # pkgs
            else if args.nixpkgs.lib.hasPrefix "inputs." x
            then let
              path = self.lib.parsePath (args.nixpkgs.lib.removePrefix "inputs." x);
            in
              args.nixpkgs.lib.attrsets.getAttrFromPath path packages # pkgs
            else let
              m = builtins.split "\\$\\{`([^`]*)`}" x;
              res = map (s:
                if isList s
                then evaluateString packages (head s)
                # (evaluateString (
                #   # This defines the namespace precedence, in reverse order:
                #   # top-level pkgs, top-level toml, then inputs, then arguments to function
                #   (
                #     foldl' (a: b: a // b) {} (
                #       [toml pkgs toml.inputs] ++ attrValues (removeAttrs toml ["inputs"])
                #     )
                #   )
                # ) (head s))
                else s)
              m;
            in (
              if length m == 3 && elemAt res 0 == "" && elemAt res 2 == ""
              then elemAt res 1
              else
                (
                  concatStringsSep "" res
                )
            );
        int = x: x;
        bool = x: x;
        set = set:
          args.nixpkgs.lib.mapAttrs' (k: v: {
            name = translations.${k} or k;
            value = (handlers (translations ? ${k})).${builtins.typeOf v} v;
          })
          set;
      };
      translations = {
        "tools" = "nativeBuildInputs";
        # TODO: warning, this means you don't get automatic runtime trimming
        "dependencies" = "propagatedBuildInputs";
        "libraries" = "propagatedBuildInputs";
        "extraLibs" = "extraLibs";
      };
      # Read function call path from attrpath, and return arguments from traversal
      func = with builtins; let
        f = p: a: let
          paths = attrNames a;
        in
          if (length paths) > 0 && !args.nixpkgs.lib.isFunction p
          then f p.${head paths} a.${head paths}
          else {inherit p a;};
      in (f packages attrs);

      fixupAttrs = k: v: {
        name = translations.${k} or k;
        value = (handlers (translations ? ${k})).${builtins.typeOf v} v;
      };

      translateAttrs = builtins.mapAttrs func.a;
      fixedAttrs = args.nixpkgs.lib.mapAttrs' fixupAttrs func.a;
      injectSource =
        if fixedAttrs ? src
        then (fixedAttrs // {src = fetchFromInputs fixedAttrs.src;})
        else if (args.nixpkgs.lib.functionArgs func.p) ? src
        then (fixedAttrs // {src = builtins.dirOf tomlpath;})
        else fixedAttrs;
    in
      # TODO: process the inputs as well
      {
        func = func.p;
        attrs = injectSource;
      };

    # Create packages automatically
    automaticPkgs = path: pkgs: let
      tree = self.lib.dirToAttrs path pkgs;
      func = pkgs: attrs:
        builtins.removeAttrs (builtins.mapAttrs (
            k: v: (
              if !(v ? path) || v.type == "directory"
              then using pkgs.${k} (func pkgs.${k} v)
              else if v.type == "nix" || v.type == "regular"
              then v.path
              else if v.type == "toml"
              # retain the "type" in order to allow finding it during
              # other traversal/recursion
              then v
              else throw "unable to create attrset out of ${v.type}"
            )
          )
          attrs) ["path" "type"];
    in
      using pkgs (func pkgs tree);

    has = {
      both = extra: args': (
        if args.nixpkgs.lib.isFunction args'
        then a: has.both extra (args' a)
        else args.nixpkgs.lib.recursiveUpdate extra args'
      );
      versions = versions: has.both {__reflect.versions = versions;};
      projects = projects: has.both {__projects = projects;};
      hydraJobs = has.both {hydraJobs = args.self.packages;};
      automaticPkgs = path: let
        # TODO
        pkgs = self.inputs.flake-utils.lib.eachDefaultSystem (
          system: {
            packages = automaticPkgs path (args.nixpkgs.legacyPackages.${system});
          }
        );
      in
        has.both pkgs;
    };

    auto = let
      lib = args.nixpkgs.lib;
    in ({
        managedPackage = system: package: args.parent.packages.${system}.${package};
        automaticPkgs = path: pkgs: (automaticPkgs path pkgs);
        automaticPkgsWith = inputs: path: pkgs: (automaticPkgs path (pkgs // {inherit inputs;}));
        fromTOML = path: pkgs: callTOMLPackageWith pkgs path {};
        using = lib.flip using;
        usingWith = inputs: attrs: pkgs: using (pkgs // {inherit inputs;}) attrs;
        fetchFrom = fetchFrom;
      }
      // (
        builtins.listToAttrs
        (
          map (attrPath: lib.nameValuePair (lib.last attrPath) (args: pkgs: (lib.getAttrFromPath attrPath pkgs) args))
          [
            ["python3Packages" "buildPythonApplication"]
            ["python3Packages" "buildPythonPackage"]
            ["rustPlatform" "buildRustPackage"]
            ["perlPackages" "buildPerlPackage"]
            ["stdenv" "mkDerivation"]
            ["mkShell"]
          ]
        )
      ));
  }
