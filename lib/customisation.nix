self: args: inputs: let
  injectSource = self.lib.injectSourceWith args inputs;
in
  # Scopes vs Overrides
  # Scopes provide a way to compose packages sets without. They have less
  # power than override with their fixed points, but are simpler to use.
  #
  #
  rec {
    # using:: {packageSet} -> {paths} -> {pkgsForThePaths}
    # eg: using pkgs.python3packages { new-application = ./pythonPackages/new-application.nix; }
    ## TODO: turn into mapAttrsRecursiveCond?
    using = usingRaw false;
    usingRaw = clean: packageSet: attrpkgs: let
      # {{{
      newScope = extra: args.nixpkgs.lib.callPackageWith (packageSet // extra);
      me = args.nixpkgs.lib.makeScope newScope (
        local:
          if builtins.isAttrs attrpkgs && attrpkgs?meta && attrpkgs.meta?project && attrpkgs?inputs
          then processTOML attrpkgs packageSet

          else if builtins.isAttrs attrpkgs
          then
            builtins.mapAttrs (
              n: v:
                if builtins.isPath v
                then injectSource n (local.callPackage v {})
                else v
            )
            attrpkgs
          # if the package is a raw path, then there is no passed down callpackage
          else if builtins.isPath attrpkgs
          then injectSource null (packageSet.callPackage attrpkgs {})

          else if args.nixpkgs.lib.isDerivation attrpkgs
          then attrpkgs


          else throw "last arg to 'using' is either a path or attrset of paths"
      );
    in
      if clean
      then me.packages me
      else packageSet // me; # }}}


    # processTOML ::: TODO
    processTOML = toml: pkgs: let
      ins = toml.inputs;
      attrs = builtins.removeAttrs toml ["inputs"];

      # Recurse looking for strings matching "inputs." pattern in order
      # to resolve with scope
      handlers = {
        list = list: map (x: handlers.${builtins.typeOf x} x) list;
        string = x: if args.nixpkgs.lib.hasPrefix "inputs." x
        then
          let path = self.lib.parsePath (pkgs.lib.removePrefix "inputs." x);
          in args.nixpkgs.lib.attrsets.getAttrFromPath path pkgs
        else x;
        int = x: x;
        set = set: args.nixpkgs.lib.mapAttrsRecursive
        (path: value: handlers.${builtins.typeOf value} value)
        set;
      };
      fixupAttrs = k: v: handlers.${builtins.typeOf v} v;

      # Read meta.project and inject source from flake
      injectSource = self.lib.injectSourceWith args inputs;
      fixedAttrs = builtins.mapAttrs fixupAttrs attrs.perlPackages.buildPerlPackage;
      in
      # TODO: process the inputs as well
        injectSource null (pkgs.perlPackages.buildPerlPackage fixedAttrs);

    # usincClean ::
    # recurse through a hierarchical packageset and remove remnants of scopes
    usingClean = attrset: rest:
      args.nixpkgs.lib.attrsets.mapAttrsRecursiveCond
      (a: (a.recurseForDerivations or false || a.recurseForRelease or false) && !args.nixpkgs.lib.isDerivation a)
      (path: v:
        if builtins.isAttrs v && v ? packages
        then v.packages v
        else v) (usingRaw true attrset rest);

    # Create packages automatically
    automaticPkgs = path: pkgs: let
      treePre = self.lib.dirToAttrs path pkgs;
      tree = (builtins.removeAttrs treePre ["pkgs"]) // treePre.pkgs;
      func = pkgs: attrs:
        builtins.removeAttrs (builtins.mapAttrs (
            k: v: (
              if v ? path && (v.type == "nix" || v.type == "regular")
              then v.path
              else
                if v ? path && (v.type == "toml" )
                then
                  (processTOML
                  (builtins.fromTOML (builtins.readFile v.path))
                  pkgs
                  )
                else
                  using pkgs.${k} (func pkgs.${k} v)
            )
          )
          attrs) ["path" "type"];
      result = usingClean pkgs (func pkgs tree);
    in
    result;
  }
