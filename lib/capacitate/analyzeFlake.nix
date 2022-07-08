{root, lib, nixpkgs}: let

  inherit (lib.capacitor.capacitate.capacitate) materialize;
  inherit (lib.capacitor) mapAttrsRecursiveCond;


  # used to map the attribute part of a flakes' <apps|packages|..>.<system>.*
  # with access to the system
  withSystem = fn: lib.mapAttrs (system: drvs: (fn system drvs));

  # checks whether a given record is a valid derivation
  isValidDrv = d: let
    r = builtins.tryEval (builtins.all lib.id [
      (lib.isDerivation d) # element should be a derivation
      (!(lib.attrByPath ["meta" "broken"] false d)) # element should not be broken
      (builtins.seq d.name true) # element has a name *
      (d ? outputs) # element has outputs *
      # * not sure why we have these
      #   they seem to be necessary for the search
    ]);
  in
    r.success && r.value;
  # filter out all invalid derivations in an attribute set of derivations
  filterValidPkgs = lib.filterAttrs (k: v: isValidDrv v);

  readPackage = {
    attrPath ? [],
    stability ? "unknown",
    channel ? "unknown",
  }: drv: rec {
    element = {
      active = true;
      attrPath = attrPath;
      originalUrl = null;
      url = null;
      storePaths = lib.attrValues eval.outputs;
    };

    eval = {
      flake.locked = 
      {
        inherit (root) narHash lastModified lastModifiedDate;
        rev = root.rev or "dirty";
        out = builtins.unsafeDiscardStringContext root.outPath;
      };

      #flake = builtins.removeAttrs self.inputs.root [ "outPath" ];
      inherit (drv) name system meta;
      inherit stability attrPath;
      drvPath = builtins.unsafeDiscardStringContext drv.drvPath;
      pname = (builtins.parseDrvName drv.name).name;
      version = (builtins.parseDrvName drv.name).version;
      outputs = lib.genAttrs drv.outputs (output: builtins.unsafeDiscardStringContext drv.${output}.outPath);
    };
  };

  readApps = system: apps:
    lib.mapAttrsToList
    (
      attribute_name: app: (
        {
          inherit attribute_name system;
          attrPath = [system attribute_name];
        }
        // lib.optionalAttrs (app ? outPath) {path = builtins.unsafeDiscardStringContext app.outPath;}
        // lib.optionalAttrs (app ? program) {path = builtins.unsafeDiscardStringContext app.program;}
        // lib.optionalAttrs (app ? type) {type = app.type;}
      )
    )
    apps;

  readOptions = let
    declarations = module:
      (
        lib.evalModules {
          modules =
            (
              if lib.isList module
              then module
              else [module]
            )
            ++ [
              (
                {...}: {
                  _module.check = false;
                  nixpkgs.system = lib.mkDefault "x86_64-linux";
                  nixpkgs.config.allowBroken = true;
                }
              )
            ];
        }
      )
      .options;

    # Makes option declarations json serializable by replacing functions for the marker string "<function>"
    # Removes store path from declaration
    cleanUpOption = extraAttrs: opt: let
      applyOnAttr = n: f: lib.optionalAttrs (builtins.hasAttr n opt) {${n} = f opt.${n};};
      mkDeclaration = decl: let
        discard = lib.concatStringsSep "/" (lib.take 4 (lib.splitString "/" decl)) + "/";
        path =
          if lib.hasPrefix builtins.storeDir decl
          then lib.removePrefix discard decl
          else decl;
      in
        path;

      # Replace functions by the string <function>
      substFunction = x:
        if builtins.isAttrs x
        then lib.mapAttrs (_: substFunction) x
        else if builtins.isList x
        then map substFunction x
        else if lib.isFunction x
        then "function"
        else x;
    in
      opt
      // applyOnAttr "default" substFunction
      // applyOnAttr "example" substFunction # (_: { __type = "function"; })
      // applyOnAttr "type" substFunction
      // applyOnAttr "declarations" (map mkDeclaration)
      // extraAttrs;
  in
    {
      module,
      modulePath ? null,
    }: let
      opts = lib.optionAttrSetToDocList (declarations module);
      public_opts = lib.filter (x: !x.internal) opts;
      extraAttrs = lib.optionalAttrs (modulePath != null) {
        flake = modulePath;
      };
    in
      map (cleanUpOption extraAttrs) public_opts;

  flattenAttrset = set: let
    recurse = path: attrs: let
      g = name: value: let
        path' = path ++ [name];
      in
        if !(builtins.tryEval value).success
        then []
        else if lib.isAttrs value && !lib.isDerivation value
        then recurse path' value
        else [
          (
            lib.nameValuePair
            (lib.showAttrPath path')
            (value // {attrPath = path';})
          )
        ];
    in
      builtins.concatLists (lib.mapAttrsToList g attrs);
  in
    builtins.listToAttrs (recurse [] set);

  prefixPath = prefix:
    map (
      set:
        lib.updateManyAttrsByPath
        [
          {
            path = ["element" "attrPath"];
            update = attribute_path: (lib.flatten [prefix]) ++ attribute_path;
          }
        ]
        set
    );

  legacyPackagesMapper = flatten: {
    isCapacitated,
    namespace,
    flakePath,
    value,
    system,
    stability,
    ...
  }: let
    attrPathFlat = ["${lib.showAttrPath (lib.flatten [system stability flakePath namespace])}"];
    attrPath = lib.flatten [system stability flakePath namespace];
  in {
    value =
      if isCapacitated
      then
        readPackage {
          inherit attrPath stability;
          channel = flakePath;
        }
        value
      else
        mapAttrsRecursiveCond
        (path: value: let
          result = builtins.tryEval (lib.isDerivation value);
        in
          !(result.success && result.value))
        (
          path: value:
            if isValidDrv value
            then
              readPackage {
                attrPath = path;
                channel = flakePath;
              }
              value
            else {}
        )
        value;

    path =
      if flatten
      then attrPathFlat
      else attrPath;
    use = !flatten || isCapacitated;
  };

  legacyPackagesGen = generated : let
    materialize' = flatten: materialize (legacyPackagesMapper flatten);

    joinProjects = self': children: adopted: let
      children' =
        lib.mapAttrs (
          name: child: (joinProjects child.self child.children child.adopted)
        )
        children;

      packages = lib.foldl' lib.recursiveUpdate (materialize' false self') (
        (lib.mapAttrsToList (_: c: c.packages) children')
        ++ (lib.mapAttrsToList (_: a: materialize' false) adopted)
      );

      adopted' = lib.mapAttrs (_: materialize' true) adopted;
      capacitated =
        lib.foldl' (a: b: a // b)
        (materialize' true self')
        ((lib.mapAttrsToList (_: c: c.capacitated) children') ++ (lib.attrValues adopted'));

      self = lib.attrValues capacitated;

      derivations = lib.genAttrs ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"] (
        system:
          with nixpkgs.legacyPackages.${system};
            lib.mapAttrs
            (name: value: writeText "${name}_reflection.json" (builtins.toJSON value))
            {inherit self packages;}
      );
    in rec {
      inherit
        capacitated
        packages
        self
        derivations
        ;
      children = children';
    };
  in
    joinProjects generated.self generated.children generated.adopted;
in
  { inherit legacyPackagesGen; 
    plugin = { capacitate, ... }:
    {
      __reflect.analysis = legacyPackagesGen (capacitate.composeSelf "packages");
    };
  }
