self: args: inputs: let
  # attempt to extract source from a function with a source argument
  fetchFromInputs = self.lib.injectSourceWith args inputs;
in
  # Scopes vs Overrides
  # Scopes provide a way to compose packages sets. They have less
  # power than override with their fixed points, but are simpler to use.
  #
  #
  rec {
    smartType = attrpkgs:
      if args.nixpkgs.lib.isDerivation attrpkgs
      then "derivation"
      else builtins.typeOf attrpkgs;

    # using:: {packageSet} -> {paths} -> {pkgsForThePaths}
    # eg: using pkgs.python3packages { new-application = ./pythonPackages/new-application.nix; }
    ## TODO: turn into mapAttrsRecursiveCond?
    usingClean = clean: local: scope': pkgset: attrpkgs: let
      scope' = extra:
        (
          if pkgset ? newScope
          then pkgset.newScope
          else args.nixpkgs.lib.callPackageWith
        ) (pkgset // extra);
      scope =
        if !builtins.isNull scope'
        then
          if pkgset ? newScope
          then extra: pkgset.newScope (pkgset // extra)
          ### Haskell's package set callPackage is difficult to work with ###
          # else
          #   if pkgset?callPackage
          #   then extra: attr: pkgset.callPackage
          else extra: args.nixpkgs.lib.callPackageWith (pkgset // extra)
        else scope';
    in
      {
        # if the item is a derivation, use it directly
        derivation = attrpkgs;

        # if the item is a raw path, then use injectSource+callPackage on it
        path = scope {inherit fetchFromInputs;} attrpkgs {};

        # if the item is a raw path, then use injectSource+callPackage on it
        string = scope {inherit fetchFromInputs;} attrpkgs {};

        # if the item is a lambda, provide a callPackage for use
        lambda = attrpkgs (scope {inherit fetchFromInputs;});

        # everything else is an error
        __functor = self: type: (
          if self ? ${type}
          then self.${type}
          else throw "last arg to 'using' was '${type}'; should be a path, attrset of paths, derivation, or function"
        );

        # Sets are more complicated and require recursion
        set =
          # if it is a scope already pass it along, don't recurse to allow for isolation
          if attrpkgs ? newScope
          then attrpkgs.packages attrpkgs
          else # <-------- TODO: needs review
            # if there is an "inputs" attribute, consider it a TOML
            if attrpkgs ? meta && attrpkgs.meta ? project && attrpkgs ? inputs
            then processTOML attrpkgs scope
            # if it is still an attrset (non-TOML), recurse into only our packages
            else
              (
                builtins.mapAttrs (
                  n: v: let
                    level = with args.nixpkgs.lib;
                      recursiveUpdate
                      (
                        if pkgset ? ${n} && builtins.isAttrs pkgset.${n}
                        then recursiveUpdate pkgset pkgset.${n}
                        else pkgset
                      )
                      (
                        if attrpkgs ? ${n} && builtins.isAttrs attrpkgs.${n}
                        then recursiveUpdate attrpkgs attrpkgs.${n}
                        else attrpkgs
                      );
                    newScope = s: scope (level // s);
                    me = args.nixpkgs.lib.makeScope newScope (local: usingClean clean local newScope level v);
                  in
                    if clean
                    then me.packages me
                    else me
                )
                attrpkgs
              );
      } (smartType attrpkgs);

    usingRaw = usingClean false (s: {}) null;
    using = usingClean true (s: {}) null;

    # processTOML ::: TODO, adopt other functions, and utilize a scope to
    # resolve attrPaths
    processTOML = toml: pkgs: let
      ins = toml.inputs;
      attrs = builtins.removeAttrs toml ["inputs"];

      # Recurse looking for strings matching "inputs." pattern in order
      # to resolve with scope
      handlers = {
        list = list: map (x: handlers.${builtins.typeOf x} x) list;
        string = x:
          if args.nixpkgs.lib.hasPrefix "inputs." x
          then let
            path = self.lib.parsePath (pkgs.lib.removePrefix "inputs." x);
          in
            args.nixpkgs.lib.attrsets.getAttrFromPath path pkgs
          else x;
        int = x: x;
        set = set:
          args.nixpkgs.lib.mapAttrsRecursive
          (path: value: handlers.${builtins.typeOf value} value)
          set;
      };
      # Read meta.project and inject source from flake
      # TODO: this means we only support fetchFromInputs in TOML
      fixupAttrs = k: v: handlers.${builtins.typeOf v} v;
      fixedAttrs = builtins.mapAttrs fixupAttrs attrs.perlPackages.buildPerlPackage;
      injectSource = fixedAttrs // {src = fetchFromInputs fixedAttrs.src;};
    in
      # TODO: process the inputs as well
      (pkgs.perlPackages.buildPerlPackage injectSource);

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
              then
                (
                  processTOML
                  (builtins.fromTOML (builtins.readFile v.path))
                  pkgs
                )
              else throw "unable to create attrset out of ${v.type}"
            )
          )
          attrs) ["path" "type"];
    in
      using pkgs (func pkgs tree);
  }
