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
      attrpkgs.type or (builtins.typeOf attrpkgs);

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
          else scope {inherit fetchFromInputs name;} attrpkgs {};

        toml = let
          a = processTOML attrpkgs.path pkgset;
        in
          scope {inherit fetchFromInputs name;} a.func a.attrs;

        # if the item is a raw path, then use injectSource+callPackage on it
        string = scope {inherit fetchFromInputs name;} attrpkgs {};

        # if the item is a lambda, provide a callPackage for use
        lambda = attrpkgs (scope {inherit fetchFromInputs name;});

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

    usingRaw = usingClean false "root";
    using = usingClean true "root";

    # processTOML ::: path -> pkgs -> {func,attrs}
    # Expect an inputs attribute and that strings begining with "inputs." are
    # references, TODO: use ${ instead?
    processTOML = tomlpath: pkgs: let
      toml = builtins.fromTOML (builtins.readFile tomlpath);
      ins = toml.inputs;
      attrs = builtins.removeAttrs toml ["inputs"];

      # Recurse looking for strings matching "inputs." pattern in order
      # to resolve with scope
      handlers = with args.nixpkgs; {
        list = list: map (x: handlers.${builtins.typeOf x} x) list;
        string = x:
          if lib.hasPrefix "inputs." x
          then let
            path = self.lib.parsePath (pkgs.lib.removePrefix "inputs." x);
          in
            lib.attrsets.getAttrFromPath path pkgs
          else x;
        int = x: x;
        set = set:
          lib.mapAttrsRecursive
          (path: value: handlers.${builtins.typeOf value} value)
          set;
      };

      # Read function call path from attrpath, and return arguments from traversal
      func = with builtins; let
        f = p: a: let
          paths = attrNames a;
        in
          if (length paths) == 1
          then f p.${head paths} a.${head paths}
          else {inherit p a;};
      in
        f pkgs attrs;

      fixupAttrs = k: v: handlers.${builtins.typeOf v} v;
      fixedAttrs = builtins.mapAttrs fixupAttrs func.a;
      injectSource =
        if fixedAttrs ? src
        then (fixedAttrs // {src = fetchFromInputs fixedAttrs.src;})
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
  }
