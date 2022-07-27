{lib}:
# args to the capacitor
args: let
  flake-lib = lib.capacitor.flakes;
  auto = lib.capacitor.capacitate.auto args;
  using = lib.capacitor.using;
  smartType = lib.capacitor.smartType;
  mapAttrsRecursiveCondFunc = lib.capacitor.mapAttrsRecursiveCondFunc;

  localFlake = rootPath: path: context:
    flake-lib.localFlake {
      inherit (context) root self;
      inputs = (import (context.self + "/flake.nix")).inputs;
    }
    rootPath
    path;

  # TODO: more generic function refactoring pkgs?
  callPackageWith = injectedArgs: fn: extra: {
    namespace,
    flakePath,
    root',
    self',
    self,
    nixpkgs',
    stability,
    system,
    ...
  } @ customisation: let
    pathElements = let
      recurse = collected: set: fragments: let
        collected' = collected ++ [(set.__adopted or {}) (set.__self or {})];
      in
        if (set == {})
        then collected
        else if (fragments == [])
        then collected'
        else recurse collected' (set.__projects.${lib.head fragments} or {}) (lib.tail fragments);

      recursed = recurse [] (root'.legacyPackages or {}) (
        if flakePath == []
        then []
        else lib.init flakePath
      );

      adopted = self'.legacyPackages.__adopted or {};
      own = self'.legacyPackages.__self or {};

      all =
        recursed
        ++ [adopted]
        ++ [
          (builtins.removeAttrs own [(lib.last namespace)])
        ];
    in
      all;

    flattened = lib.foldl (lib.recursiveUpdate) nixpkgs' pathElements;

    # TODO: look at the meaning of namespace again
    #       namespace currently includes the attribute
    #       name of the (proto) derivation, we maight
    #       want to change this as its not part of a "namespace".
    callPackageBase = let
      recurse = scope: merged: ns: (
        if ns == [] || !(lib.isAttrs scope) || lib.isDerivation scope || !(scope ? ${lib.head ns})
        then merged
        else let
          scope' = scope.${lib.head ns};
          merged' = merged // scope';
          ns' = lib.tail ns;
        in
          recurse scope' merged' ns'
      );
    in (recurse flattened flattened (lib.init namespace));

    callPackageArgs = extra;
    pkgs = callPackageBase // customisation // injectedArgs // { inherit pkgs;};

  in (lib.callPackageWith pkgs fn callPackageArgs);

  callPackage = fn: auto.callPackageWith {} fn;

  # TODO: use this function to call local files in localResourcesWith
  callAny = callee:
    {
      # if the item is a derivation, use it directly
      derivation = auto.callPackage callee;

      # if the item is a raw path, then use injectSource+callPackage on it
      path =
        if lib.hasSuffix ".toml" callee
        then
          auto.callAny {
            type = "toml";
            path = callee;
          }
        else auto.callPackage callee;

      toml = let
        a = using.processTOML callee.path {};
        # TODO: ensure scope is correct
      in
        auto.callPackageWith a.attrs a.func;

      # if the item is a raw path, then use injectSource+callPackage on it
      string =
        if (lib.hasSuffix ".toml" callee)
        then
          auto.callAny {
            type = "toml";
            path = callee;
          }
        # TODO: flakes?
        else if
          (lib.hasSuffix ".nix" callee)
          || (builtins.pathExists (callee + "/default.nix"))
        then auto.callPackage callee
        else throw "Path ${callee} not a nix or toml source";
      # automaticPkgs callee (pkgset // pkgset.${name});

      # if the item is a lambda, provide a callPackage for use
      lambda = auto.callPackage callee;

      # everything else is an error
      __functor = self: type: (
        self.${type}
        or (throw "last arg to 'using' was '${type}'; should be a path to Nix, path to TOML, attrset of paths, derivation, or function")
      );

      # TODO: Do not use on sets...
      # # Sets are more complicated and require recursion
      # set =
      #   # if it is a scope already pass it along, don't recurse to allow for isolation
      #   if callee ? newScope
      #   then callee.packages callee
      #   else # <-------- TODO: needs review
      #     let
      #       res =
      #         builtins.mapAttrs (
      #           n: v:
      #             with  let
      #               # Bring results back in! TODO: check if using // or recursiveUpdate
      #               # only do pkgset.${name} if it is a packageset, not a package or other thing
      #               level = lib.recursiveUpdate (pkgset // (pkgset.${name} or {})) res;
      #               newScope = s: scope (level // s);
      #               me = lib.makeScope newScope (_: usingClean clean n level v);
      #             in let
      #               filterOverrides = a: builtins.removeAttrs a ["override" "__functor" "overrideDerivation"];
      #             in
      #               if clean && me ? packages
      #               then filterOverrides (me.packages me)
      #               else if clean
      #               then filterOverrides me
      #               else me
      #         )
      #         callee;
      #     in
      #       res;
    } (smartType callee);

  localResourcesWith = injectedArgs: x: context: dir: let
    tree = lib.capacitor.dirToAttrs (context.self + "/${dir}") {};
    func = path: attrs:
      builtins.removeAttrs (builtins.mapAttrs (
          k: v: (
            let
              path' = path ++ [k];
            in
              if !(v ? path) || v.type == "directory"
              then func path' v
              else if v.type == "nix" || v.type == "regular"
              then auto.callPackageWith injectedArgs v.path {}
              else if v.type == "toml"
              then
              context:
              let
                  process = {pkgs}: using.processTOML v.path pkgs;
                  processed = auto.callPackageWith injectedArgs process {} context;
              in processed.func processed.attrs
              else if v.type == "flake" # TODO: only supports capacitated Flakes
              then let
                flake = auto.localFlake dir path' context;
              in
                # mapAttrsRecursiveCondFunc
                # (builtins.mapAttrs)
                # (p: v: !lib.isFunction v)
                # (p: v: context: v (context // injectedArgs))
                (flake.__reflect.proto x)
              # retain the "type" in order to allow finding it during
              # other traversal/recursion
              # then v
              else throw "unable to create attrset out of ${v.type}"
          )
        )
        attrs) ["path" "type"];
  in
    func [] tree;
  localResources = res: localResourcesWith {} res;
  localPkgs = localResources "packages";

  reexport = project: paths: let

    translate = {
      "packages" = "legacyPackages";
      __functor = self: name: self.${name} or name;
    };

    update = newPath: oldPath: {
      path = lib.flatten [newPath];
      update = _: {
        system,
        stability,
        outputType,
        ...
      }:
        lib.attrByPath (lib.flatten [oldPath]) {} project.${translate outputType}.${system}.${stability};
    };

    updates =
      if lib.isAttrs paths
      then lib.mapAttrs update paths
      else map (path: update path path) paths;
  in
    lib.updateManyAttrsByPath updates {};
in
  {
    using = lib.flip lib.capacitor.using.using;
    usingWith = inputs: attrs: pkgs: lib.capacitor.using.using (pkgs // {inherit inputs;}) attrs;
    fetchFrom = lib.capacitor.using.fetchFrom;
    fromTOML = path: pkgs: lib.capacitor.using.callTOMLPackageWith pkgs path {};
    # TODO: what is this used for?
    # managedPackage = system: package: args.parent.packages.${system}.${package};
    automaticPkgs = path: pkgs: (lib.capacitor.using.automaticPkgs path pkgs);
    automaticPkgsWith = inputs: path: pkgs: (lib.capacitor.using.automaticPkgs path (pkgs // {inherit inputs;}));

    callPackage = callPackage;
    callPackageWith = callPackageWith;
    callAny = callAny;

    localResourcesWith = localResourcesWith;
    localResources = localResources;

    localPkgs = localPkgs;
    localFlake = localFlake;

    reexport = reexport;

    # withNamespace = namespace: fn: {
    #   namespace = namespace;
    #   __functor = self: customization: auto.callPackage fn (customisation // { namespace = self.namespace; });
    # };
  }
  // (
    builtins.listToAttrs
    (
      map (attrPath: lib.nameValuePair (lib.last attrPath) (args: {nixpkgs', ...}: (lib.getAttrFromPath attrPath nixpkgs') args))
      [
        ["python3Packages" "buildPythonApplication"]
        ["python3Packages" "buildPythonPackage"]
        ["rustPlatform" "buildRustPackage"]
        ["perlPackages" "buildPerlPackage"]
        ["stdenv" "mkDerivation"]
        ["mkShell"]
      ]
    )
  )
