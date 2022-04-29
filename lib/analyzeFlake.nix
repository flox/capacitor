{ flake ? null, resolved ? builtins.getFlake (toString flake), lib }:
let
  # used to map the attribute part of a flakes' <apps|packages|..>.<system>.* 
  # with access to the system
  withSystem = fn: lib.mapAttrs (system: drvs: (fn system drvs));

  # checks whether a given record is a valid derivation
  isValidDrv = d:
    let
      r = builtins.tryEval (builtins.all lib.id [
        (lib.isDerivation d) # element should be a derivation
        (!(lib.attrByPath [ "meta" "broken" ] false d)) # element should not be broken
        (builtins.seq d.name true) # element has a name *
        (d ? outputs) # element has outputs *
        # * not sure why we have these
        #   they seem to be necessary for the search
      ]);
    in
    r.success && r.value;
  # filter out all invalid derivations in an attribute set of derivations
  filterValidPkgs = lib.filterAttrs (k: v: isValidDrv v);

  readPackages = system: drvs: lib.mapAttrsToList
    (
      attribute_name: drv: (
        {
          inherit attribute_name system;
          attribute_path = [ system ] ++ drv.attribute_path or [ attribute_name ];
          outputs = builtins.listToAttrs (map (output: lib.nameValuePair output (builtins.unsafeDiscardStringContext drv.${output}.outPath)) drv.outputs);
          default_output = drv.outputName;
          meta = drv.meta;
        }
        // builtins.parseDrvName drv.name
      )
    )
    (filterValidPkgs drvs);

  readApps = system: apps: lib.mapAttrsToList
    (
      attribute_name: app: (
        {
          inherit attribute_name system;
          attribute_path = [system attribute_name];
        }
        // lib.optionalAttrs (app ? outPath) { path = builtins.unsafeDiscardStringContext app.outPath; }
        // lib.optionalAttrs (app ? program) { path = builtins.unsafeDiscardStringContext app.program; }
        // lib.optionalAttrs (app ? type) { type = app.type; }
      )
    )
    apps;

  readOptions =
    let
      declarations = module: (
        lib.evalModules {
          modules = (if lib.isList module then module else [ module ]) ++ [
            (
              { ... }: {
                _module.check = false;
                nixpkgs.system = lib.mkDefault "x86_64-linux";
                nixpkgs.config.allowBroken = true;
              }
            )
          ];
        }
      ).options;

      # Makes option declarations json serializable by replacing functions for the marker string "<function>"
      # Removes store path from declaration
      cleanUpOption = extraAttrs: opt:
        let
          applyOnAttr = n: f: lib.optionalAttrs (builtins.hasAttr n opt) { ${n} = f opt.${n}; };
          mkDeclaration = decl:
            let
              discard = lib.concatStringsSep "/" (lib.take 4 (lib.splitString "/" decl)) + "/";
              path = if lib.hasPrefix builtins.storeDir decl then lib.removePrefix discard decl else decl;
            in
            path;

          # Replace functions by the string <function>
          substFunction = x:
            if builtins.isAttrs x then
              lib.mapAttrs (_:substFunction) x
            else if builtins.isList x then
              map substFunction x
            else if lib.isFunction x then
              "function"
            else
              x;
        in
        opt
        // applyOnAttr "default" substFunction
        // applyOnAttr "example" substFunction # (_: { __type = "function"; })
        // applyOnAttr "type" substFunction
        // applyOnAttr "declarations" (map mkDeclaration)
        // extraAttrs;

    in
    { module, modulePath ? null }:
    let
      opts = lib.optionAttrSetToDocList (declarations module);
      public_opts = (lib.filter (x: !x.internal) opts);
      extraAttrs = lib.optionalAttrs (modulePath != null) {
        flake = modulePath;
      };
    in
    map (cleanUpOption extraAttrs) public_opts;

  readFlakeOptions =
    let
      nixosModulesOpts = builtins.concatLists (lib.mapAttrsToList
        (moduleName: module:
          readOptions {
            inherit module;
            modulePath = [ flake moduleName ];
          }
        )
        (resolved.nixosModules or { }));

      nixosModuleOpts = lib.optionals (resolved ? nixosModule) (
        readOptions {
          module = resolved.nixosModule;
          modulePath = [ flake ];
        }
      );
    in
    # We assume that `nixosModules` includes `nixosModule` when there
    # are multiple modules
    # TODO: this might be easier or harder now that default modules
    #       are defined as nixosModules.default
    if nixosModulesOpts != [ ] then nixosModulesOpts else nixosModuleOpts;

  read = reader: set: lib.flatten (lib.attrValues (withSystem reader set));

  collectSystems = lib.lists.foldr
    (
      drv@{ attribute_name, system, ... }: set:
        let
          present = set."${attribute_name}" or ({ platforms = [ ]; paths = { }; } // drv);

          drv' = present
            // {
            platforms = present.platforms ++ [ system ];
            paths = lib.recursiveUpdate present.paths drv.paths;
          };

          drv'' = removeAttrs drv' [ "system" ];
        in
        set // {
          ${attribute_name} = drv'';
        }
    )
    { };
  legacyPackages' = lib.pipe
    (resolved.legacyPackages or { })
    [
      # flatten all derivation of each system attribute
      (lib.mapAttrs (_: set: flattenAttrset set))
      (read readPackages)
      (prefixPath "legacyPackages")
    ];
  packages' = lib.pipe (resolved.packages or { }) [ (read readPackages) (prefixPath "packages") ];
  apps' = lib.pipe (resolved.apps or { }) [ (read readApps) (prefixPath "apps") ];

  flattenAttrset = set:
    let
      recurse = path: attrs:
        let
          g =
            name: value:
            let path' = path ++ [ name ]; in
            if !lib.isDerivation value
            then recurse path' value
            else [
              (
                lib.nameValuePair
                  (lib.showAttrPath path')
                  (value // { attribute_path = path'; })
              )
            ];
        in
        builtins.concatLists (lib.mapAttrsToList g attrs);
    in
    builtins.listToAttrs (recurse [ ] set);

  prefixPath = prefix: map (set: set // { attribute_path = (lib.flatten [ prefix ]) ++ set.attribute_path; });

in

rec {
  legacyPackages = lib.attrValues (collectSystems legacyPackages');
  packages = lib.attrValues (collectSystems packages');
  apps = lib.attrValues (collectSystems apps');
  options = readFlakeOptions;

  # a nixos-only attribute that does not fit with flox use case just yet
  # 
  # nixos-options = readOptions {
  #   module = import "${nixpkgs}/nixos/modules/module-list.nix";
  # };

  all = packages ++ apps ++ options;
}
